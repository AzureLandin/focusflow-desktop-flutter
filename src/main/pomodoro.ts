import { randomUUID } from 'node:crypto';
import { localDay, settingsSchema, type ActiveSession, type Phase, type Session, type Settings, type Task } from '../shared/model';
import { Database, UserError } from './database';

const ended = new Set(['focus_elapsed', 'break_elapsed', 'session_completed']);

export function nextBreak(session: Session, rules: Settings): Phase | null {
  const long = session.completed_pomodoros % rules.longEvery === 0;
  if (session.completed_pomodoros >= session.planned_pomodoros) {
    return long && rules.finalLongBreak ? 'long_break' : null;
  }
  return long ? 'long_break' : 'short_break';
}

export class Pomodoro {
  constructor(private db: Database, private refreshHistory: (date: string, now: number) => void) {}

  active() {
    return this.db.get<Session>("SELECT * FROM pomodoro_sessions WHERE status NOT IN ('interrupted','completed')");
  }

  view(): ActiveSession | null {
    const session = this.active();
    if (!session) return null;
    const rules = this.rules(session);
    const { seconds } = this.db.get<{ seconds: number }>(
      "SELECT COALESCE(SUM(focus_seconds),0) seconds FROM pomodoro_cycles WHERE session_id=? AND status='completed'", session.id,
    )!;
    const { count } = this.db.get<{ count: number }>('SELECT COUNT(*) count FROM thought_notes WHERE session_id=?', session.id)!;
    const projected = session.status === 'focus_running' ? { ...session, completed_pomodoros: session.completed_pomodoros + 1 } : session;
    return { ...session, nextBreak: session.current_phase === 'focus' ? nextBreak(projected, rules) : null,
      focusSeconds: seconds, thoughtCount: count, canConfirm: this.canConfirm(session) };
  }

  private rules(session: Session) { return settingsSchema.parse(JSON.parse(session.rules)); }

  private find(id: string) {
    const session = this.active();
    if (session?.id !== id) throw new UserError('该专注会话已结束，请刷新后重试。');
    return session;
  }

  start(title: string, taskId: string | null, plan: number, now: number, rules: Settings) {
    this.db.run(`INSERT INTO pomodoro_sessions
      (id,task_id,task_title_snapshot,planned_pomodoros,current_cycle,current_phase,status,phase_started_at,phase_ends_at,started_at,rules)
      VALUES (?,?,?,?,1,'focus','focus_running',?,?,?,?)`,
      randomUUID(), taskId, title, plan, now, now + rules.focusMinutes * 60_000, now, JSON.stringify(rules));
    if (taskId) this.db.run("UPDATE tasks SET status='in_progress', updated_at=? WHERE id=?", now, taskId);
  }

  tick(session: Session, now: number) {
    if (ended.has(session.status) || now < session.phase_ends_at) return false;
    if (session.status !== 'focus_running') {
      this.db.run("UPDATE pomodoro_sessions SET status='break_elapsed' WHERE id=?", session.id);
      return true;
    }
    const { phase_ends_at: end, phase_started_at: start } = session;
    const day = localDay(end);
    this.db.run(`INSERT INTO pomodoro_cycles (id,session_id,cycle_index,status,started_at,ended_at,local_date,focus_seconds)
      VALUES (?,?,?,'completed',?,?,?,?)`, randomUUID(), session.id, session.current_cycle, start, end, day, (end - start) / 1000);
    this.db.run("UPDATE pomodoro_sessions SET status='focus_elapsed', completed_pomodoros=completed_pomodoros+1 WHERE id=?", session.id);
    if (session.task_id) this.db.run('UPDATE tasks SET completed_pomodoros=completed_pomodoros+1, updated_at=? WHERE id=?', now, session.task_id);
    this.refreshHistory(day, now);
    return true;
  }

  isDue(session: Session, now: number) { return !ended.has(session.status) && now >= session.phase_ends_at; }

  private startPhase(session: Session, phase: Phase, minutes: number, now: number, finalBreak = false) {
    this.db.run(`UPDATE pomodoro_sessions SET current_phase=?,status=?,phase_started_at=?,phase_ends_at=?,
      current_cycle=current_cycle+?,ending_break=? WHERE id=?`,
      phase, `${phase}_running`, now, now + minutes * 60_000, Number(phase === 'focus'), Number(finalBreak), session.id);
  }

  private summarize(session: Session, now: number) {
    this.db.run("UPDATE pomodoro_sessions SET status='session_completed', finished_at=? WHERE id=?", now, session.id);
  }

  advance(id: string, now: number) {
    const session = this.find(id);
    const rules = this.rules(session);
    if (session.status === 'focus_elapsed') {
      const next = nextBreak(session, rules);
      if (next) {
        this.startPhase(session, next, next === 'long_break' ? rules.longMinutes : rules.shortMinutes, now,
          session.completed_pomodoros === session.planned_pomodoros);
      } else this.summarize(session, now);
      return;
    }
    if (session.status === 'break_elapsed') {
      if (session.ending_break) this.summarize(session, now);
      else this.startPhase(session, 'focus', rules.focusMinutes, now);
      return;
    }
    throw new UserError('请等待当前阶段结束。');
  }

  end(id: string, now: number) {
    const session = this.find(id);
    if (session.status === 'focus_running' || session.status === 'session_completed') {
      throw new UserError('请先结束正在进行的专注阶段。');
    }
    this.summarize(session, now);
  }

  interrupt(id: string, reason: string, now: number) {
    const session = this.find(id);
    if (session.status !== 'focus_running') throw new UserError('本轮专注已结束，无法再标记为打断。');
    const cycleId = randomUUID();
    const end = Math.max(now, session.phase_started_at);
    this.db.run(`INSERT INTO pomodoro_cycles (id,session_id,cycle_index,status,started_at,ended_at,local_date,focus_seconds)
      VALUES (?,?,?,'interrupted',?,?,?,?)`, cycleId, id, session.current_cycle, session.phase_started_at, end,
      localDay(now), Math.floor((end - session.phase_started_at) / 1000));
    this.db.run('INSERT INTO pomodoro_interruptions (id,session_id,cycle_id,reason,occurred_at) VALUES (?,?,?,?,?)',
      randomUUID(), id, cycleId, reason, now);
    this.db.run("UPDATE pomodoro_sessions SET status='interrupted',finished_at=? WHERE id=?", now, id);
  }

  private canConfirm(session: Session) {
    if (!session.task_id) return true;
    const task = this.db.get<Task>('SELECT * FROM tasks WHERE id=?', session.task_id);
    return Boolean(task && task.completed_pomodoros >= task.planned_pomodoros);
  }

  resolve(id: string, completed: boolean, saveQuick: boolean, now: number, saveTask: (session: Session) => string) {
    const session = this.find(id);
    if (session.status !== 'session_completed') throw new UserError('请先结束专注会话。');
    if (completed && !this.canConfirm(session)) throw new UserError('该任务还未达到计划番茄数。');
    const taskId = session.task_id ?? (saveQuick ? saveTask(session) : null);
    if (completed && taskId) {
      this.db.run("UPDATE tasks SET status='completed', completed_at=?, updated_at=? WHERE id=?", now, now, taskId);
      const task = this.db.get<Task>('SELECT * FROM tasks WHERE id=?', taskId)!;
      this.refreshHistory(task.scheduled_date, now);
    }
    this.db.run("UPDATE pomodoro_sessions SET status='completed',task_id=? WHERE id=?", taskId, id);
  }
}
