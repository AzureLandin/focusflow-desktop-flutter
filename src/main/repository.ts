import { randomUUID } from 'node:crypto';
import { calendarDays, commandSchema, defaultSettings, localDay, readRequest, settingsSchema, shiftDay, type DayData,
  type Activity, type DayRecord, type Pulse, type Session, type Task, type TaskInput, type Thought, type Workspace } from '../shared/model';
import { Database, UserError } from './database';
import { Pomodoro } from './pomodoro';

export class Repository {
  readonly db: Database;
  readonly pomodoro: Pomodoro;
  private lastDay?: string;

  constructor(readonly path: string, private clock = Date.now, private onElapsed: (message: string) => void = () => {}) {
    this.db = new Database(path);
    this.pomodoro = new Pomodoro(this.db, (day, now) => this.refreshArchived(day, now));
  }

  settings() {
    const row = this.db.get<{ value: string }>("SELECT value FROM app_settings WHERE key='preferences'");
    return row ? settingsSchema.parse(JSON.parse(row.value)) : defaultSettings;
  }

  sync(now = this.clock()) {
    const today = localDay(now);
    const session = this.pomodoro.active();
    if (session && this.pomodoro.isDue(session, now)) {
      const changed = this.db.transaction(() => this.pomodoro.tick(session, now));
      if (changed) this.onElapsed(session.current_phase === 'focus' ? '本轮专注已完成' : '休息结束，可以继续了');
    }
    if (this.lastDay !== today) {
      this.db.transaction(() => this.archive(today, now));
      this.lastDay = today;
    }
    return today;
  }

  recheck() { this.lastDay = undefined; this.sync(); }

  pulse(): Pulse {
    const now = this.clock();
    return { now, today: this.sync(now), session: this.pomodoro.view() };
  }

  read(input: unknown): Workspace {
    const { day, month } = readRequest.parse(input);
    const pulse = this.pulse();
    const todayData = this.dayData(pulse.today);
    const days = calendarDays(month ?? pulse.today);
    return { ...pulse, todayData, selectedData: day && day !== pulse.today ? this.dayData(day) : todayData,
      calendar: days.map((date) => this.record(date)), settings: this.settings(), dataPath: this.path };
  }

  private archive(today: string, now: number) {
    this.db.run("INSERT OR IGNORE INTO app_settings VALUES ('archive_origin',?)", today);
    const { first } = this.db.get<{ first: string }>(`SELECT MIN(day) first FROM (
      SELECT scheduled_date day FROM tasks WHERE deleted_at IS NULL UNION ALL
      SELECT local_date FROM thought_notes UNION ALL SELECT local_date FROM pomodoro_cycles UNION ALL
      SELECT value FROM app_settings WHERE key='archive_origin')`)!;
    const archived = new Set(this.db.all<{ date: string }>('SELECT date FROM daily_records WHERE date>=? AND date<?', first, today).map(({ date }) => date));
    this.db.run("UPDATE tasks SET status='unfinished',updated_at=? WHERE scheduled_date<? AND deleted_at IS NULL AND status IN ('todo','in_progress')", now, today);
    for (let day = first; day < today; day = shiftDay(day, 1)) {
      if (!archived.has(day)) this.storeRecord(day, now);
    }
  }

  private stats(day: string): DayRecord {
    const tasks = this.db.get<Pick<DayRecord, 'total_tasks' | 'completed_tasks' | 'unfinished_tasks'>>(`SELECT COUNT(*) total_tasks,
      COUNT(*) FILTER (WHERE status='completed') completed_tasks,COUNT(*) FILTER (WHERE status!='completed') unfinished_tasks
      FROM tasks WHERE scheduled_date=? AND deleted_at IS NULL`, day)!;
    const cycles = this.db.get<Pick<DayRecord, 'total_completed_pomodoros' | 'total_focus_seconds'>>(`SELECT COUNT(*) total_completed_pomodoros,
      COALESCE(SUM(focus_seconds),0) total_focus_seconds FROM pomodoro_cycles WHERE local_date=? AND status='completed'`, day)!;
    return { date: day, finalized_at: null, ...tasks, ...cycles };
  }

  private storeRecord(day: string, now: number) {
    const r = this.stats(day);
    this.db.run(`INSERT INTO daily_records VALUES (?,?,?,?,?,?,?) ON CONFLICT(date) DO UPDATE SET
      total_tasks=excluded.total_tasks, completed_tasks=excluded.completed_tasks, unfinished_tasks=excluded.unfinished_tasks,
      total_completed_pomodoros=excluded.total_completed_pomodoros, total_focus_seconds=excluded.total_focus_seconds`,
      day, now, r.total_tasks, r.completed_tasks, r.unfinished_tasks, r.total_completed_pomodoros, r.total_focus_seconds);
  }

  private refreshArchived(day: string, now: number) {
    if (day < localDay(now)) this.storeRecord(day, now);
  }

  private record(date: string) {
    return this.db.get<DayRecord>('SELECT * FROM daily_records WHERE date=?', date) ?? this.stats(date);
  }

  private dayData(date: string): DayData {
    return {
      record: this.record(date),
      tasks: this.db.all<Task>('SELECT * FROM tasks WHERE scheduled_date=? AND deleted_at IS NULL ORDER BY sort_order,id', date),
      thoughts: this.db.all<Thought>('SELECT * FROM thought_notes WHERE local_date=? ORDER BY created_at DESC,id', date),
      activity: this.db.all<Activity>(`SELECT c.id,s.task_title_snapshot title,c.cycle_index,i.reason,c.ended_at,c.focus_seconds
        FROM pomodoro_cycles c JOIN pomodoro_sessions s ON s.id=c.session_id LEFT JOIN pomodoro_interruptions i ON i.cycle_id=c.id
        WHERE c.local_date=? ORDER BY c.ended_at DESC`, date),
    };
  }

  private task(id: string) {
    const task = this.db.get<Task>('SELECT * FROM tasks WHERE id=? AND deleted_at IS NULL', id);
    if (!task) throw new UserError('这项任务已删除或不存在。');
    return task;
  }

  private checkDay(date: string, today: string) {
    if (date < today) throw new UserError('历史日期仅供查看。请选择今天或未来日期。');
  }

  private nextOrder(day: string) {
    return this.db.get<{ next: number }>('SELECT COALESCE(MAX(sort_order),-1)+1 next FROM tasks WHERE scheduled_date=? AND deleted_at IS NULL', day)!.next;
  }

  private insertTask(input: TaskInput, now: number, count = 0) {
    const id = randomUUID();
    this.db.run(`INSERT INTO tasks (id,title,description,scheduled_date,status,pomodoro_enabled,planned_pomodoros,
      completed_pomodoros,sort_order,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
      id, input.title, input.description, input.scheduled_date, count ? 'in_progress' : 'todo', Number(input.pomodoro_enabled),
      input.planned_pomodoros, count, this.nextOrder(input.scheduled_date), now, now);
    return id;
  }

  private saveTask(input: TaskInput, today: string, now: number, id?: string) {
    this.checkDay(input.scheduled_date, today);
    if (!id) return this.insertTask(input, now);
    const task = this.task(id);
    this.checkDay(task.scheduled_date, today);
    this.db.run(`UPDATE tasks SET title=?,description=?,scheduled_date=?,pomodoro_enabled=?,planned_pomodoros=?,sort_order=?,updated_at=? WHERE id=?`,
      input.title, input.description, input.scheduled_date, Number(input.pomodoro_enabled), input.planned_pomodoros,
      task.scheduled_date === input.scheduled_date ? task.sort_order : this.nextOrder(input.scheduled_date), now, id);
  }

  private moveTask(task: Task, direction: -1 | 1, now: number) {
    const peers = this.dayData(task.scheduled_date).tasks.filter((item) => (item.status === 'completed') === (task.status === 'completed'));
    const neighbor = peers[peers.findIndex(({ id }) => id === task.id) + direction];
    if (!neighbor) return;
    this.db.run('UPDATE tasks SET sort_order=?,updated_at=? WHERE id=?', neighbor.sort_order, now, task.id);
    this.db.run('UPDATE tasks SET sort_order=?,updated_at=? WHERE id=?', task.sort_order, now, neighbor.id);
  }

  private saveQuickTask(session: Session, today: string, now: number) {
    return this.insertTask({ title: session.task_title_snapshot, description: '', scheduled_date: today,
      pomodoro_enabled: true, planned_pomodoros: session.planned_pomodoros }, now, session.completed_pomodoros);
  }

  command(input: unknown): void {
    const action = commandSchema.parse(input);
    const now = this.clock();
    const today = this.sync(now);
    this.db.transaction(() => {
      const active = this.pomodoro.active();
      if (active && ['saveTask', 'toggleTask', 'moveTask', 'deleteTask', 'saveInterruptedQuick', 'settings', 'start'].includes(action.type)) {
        throw new UserError('专注期间请先结束当前会话。');
      }
      switch (action.type) {
        case 'saveTask': this.saveTask(action.task, today, now, action.id); break;
        case 'toggleTask':
        case 'moveTask':
        case 'deleteTask': {
          const task = this.task(action.id);
          this.checkDay(task.scheduled_date, today);
          if (action.type === 'moveTask') this.moveTask(task, action.direction, now);
          if (action.type === 'deleteTask') this.db.run('UPDATE tasks SET deleted_at=?,updated_at=? WHERE id=?', now, now, task.id);
          if (action.type === 'toggleTask') {
            const done = task.status === 'completed';
            const status = done ? task.completed_pomodoros ? 'in_progress' : 'todo' : 'completed';
            this.db.run('UPDATE tasks SET status=?,completed_at=?,updated_at=? WHERE id=?', status, done ? null : now, now, task.id);
          }
          break;
        }
        case 'saveThought':
        case 'deleteThought': {
          const note = action.id && this.db.get<Thought>('SELECT * FROM thought_notes WHERE id=?', action.id);
          if (action.id && (!note || note.local_date !== today)) throw new UserError('只能修改当天的番茄想法。');
          if (action.type === 'deleteThought') this.db.run('DELETE FROM thought_notes WHERE id=?', action.id);
          else if (note) this.db.run('UPDATE thought_notes SET content=?,updated_at=? WHERE id=?', action.content, now, note.id);
          else this.db.run('INSERT INTO thought_notes VALUES (?,?,?,?,?,?)', randomUUID(), today, active?.id ?? null, action.content, now, now);
          break;
        }
        case 'start': {
          const task = action.taskId ? this.task(action.taskId) : null;
          if (task && (task.status === 'completed' || task.scheduled_date !== today || !task.pomodoro_enabled)) {
            throw new UserError('请从今天启用了番茄时钟的待完成任务开始。');
          }
          const title = task?.title ?? action.title;
          if (!title) throw new UserError('请输入这次想专注做的事。');
          this.pomodoro.start(title, task?.id ?? null, action.count, now, this.settings());
          break;
        }
        case 'advance': this.pomodoro.advance(action.id, now); break;
        case 'endSession': this.pomodoro.end(action.id, now); break;
        case 'interrupt': this.pomodoro.interrupt(action.id, action.reason, now); break;
        case 'saveInterruptedQuick': {
          const session = this.db.get<Session>("SELECT * FROM pomodoro_sessions WHERE id=? AND status='interrupted' AND task_id IS NULL", action.id);
          if (!session) throw new UserError('该次快速专注已保存或不存在。');
          this.db.run('UPDATE pomodoro_sessions SET task_id=? WHERE id=?', this.saveQuickTask(session, today, now), session.id);
          break;
        }
        case 'resolve':
          this.pomodoro.resolve(action.id, action.completed, action.saveQuick ?? false, now, (session) => this.saveQuickTask(session, today, now));
          break;
        case 'settings':
          this.db.run("INSERT INTO app_settings VALUES ('preferences',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", JSON.stringify(action.settings));
      }
    });
  }
}
