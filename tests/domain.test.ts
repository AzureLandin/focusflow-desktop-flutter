import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test, type TestContext } from 'node:test';
import { defaultSettings, type TaskInput } from '../src/shared/model';
import { exportBackup, restoreBackup } from '../src/main/backup';
import { Repository } from '../src/main/repository';

const day = '2026-11-23';
const at = (date: string) => new Date(`${date}T12:00:00`).getTime();
const minutes = (amount: number) => amount * 60_000;

function setup(t: TestContext, persistent = false) {
  const path = persistent ? mkdtempSync(join(tmpdir(), 'focusflow-test-')) : undefined;
  const file = path ? join(path, 'test.sqlite3') : ':memory:';
  let now = at(day);
  const notifications: string[] = [];
  const open = () => new Repository(file, () => now, (message) => notifications.push(message));
  let store = open();
  t.after(() => {
    store.db.close();
    if (path) rmSync(path, { recursive: true, force: true });
  });
  return { get store() { return store; }, get now() { return now; }, notifications,
    set: (instant: number) => { now = instant; }, add: (amount: number) => { now += minutes(amount); },
    reopen: () => { store.db.close(); store = open(); return store; } };
}

function task(store: Repository, fields: Partial<TaskInput> = {}) {
  store.command({ type: 'saveTask', task: { title: '设计方案', description: '', scheduled_date: day,
    pomodoro_enabled: false, planned_pomodoros: 1, ...fields } });
  return store.db.get<{ id: string }>('SELECT id FROM tasks ORDER BY rowid DESC LIMIT 1')!.id;
}

test('task CRUD, rank, completion, undo, and moving a task retain its ID', (t) => {
  const { store } = setup(t);
  const first = task(store, { title: '第一项' });
  const second = task(store, { title: '第二项' });
  store.command({ type: 'moveTask', id: second, direction: -1 });
  assert.deepEqual(store.read({}).todayData.tasks.map(({ id }) => id), [second, first]);
  store.command({ type: 'toggleTask', id: first });
  assert.equal(store.read({}).todayData.record.completed_tasks, 1);
  store.command({ type: 'toggleTask', id: first });
  assert.equal(store.read({}).todayData.record.completed_tasks, 0);
  store.command({ type: 'saveTask', id: first, task: { title: '改名', scheduled_date: '2026-11-25', description: '详情',
    pomodoro_enabled: true, planned_pomodoros: 2 } });
  assert.deepEqual(store.read({}).todayData.tasks.map(({ id }) => id), [second]);
  assert.equal(store.read({ day: '2026-11-25' }).selectedData.tasks[0].id, first);
  store.command({ type: 'deleteTask', id: first });
  assert.equal(store.read({ day: '2026-11-25' }).selectedData.tasks.length, 0);
  assert.notEqual(store.db.get<{ deleted_at: number }>('SELECT deleted_at FROM tasks WHERE id=?', first)?.deleted_at, null);
});

test('opening after several days archives empty and populated days, preserving future IDs and final states', (t) => {
  const plan = setup(t, true);
  const finished = task(plan.store);
  const unfinished = task(plan.store);
  const future = task(plan.store, { scheduled_date: '2026-11-26' });
  plan.store.command({ type: 'toggleTask', id: finished });
  plan.set(at('2026-11-26'));
  const reopened = plan.reopen();
  const snapshot = reopened.read({ day });
  assert.deepEqual(snapshot.todayData.tasks.map(({ id }) => id), [future]);
  assert.deepEqual(snapshot.selectedData.tasks.map(({ id, status }) => [id, status]), [[finished, 'completed'], [unfinished, 'unfinished']]);
  assert.deepEqual(reopened.db.all<{ date: string }>('SELECT date FROM daily_records ORDER BY date').map(({ date }) => date), [day, '2026-11-24', '2026-11-25']);
  assert.throws(() => reopened.command({ type: 'toggleTask', id: unfinished }), /历史日期/);
  assert.equal(reopened.db.get<{ count: number }>('SELECT COUNT(*) count FROM tasks')?.count, 3);
});

test('six cycles use short and long breaks correctly and require explicit completion', (t) => {
  const plan = setup(t);
  const { store } = plan;
  const id = task(store, { pomodoro_enabled: true, planned_pomodoros: 6 });
  store.command({ type: 'start', taskId: id, count: 6 });
  const active = () => store.pulse().session!;
  const session = active().id;
  const advance = () => store.command({ type: 'advance', id: session });
  assert.equal(active().phase_ends_at - active().phase_started_at, minutes(25));
  for (let cycle = 1; cycle <= 6; cycle++) {
    plan.add(25);
    assert.equal(active().status, 'focus_elapsed');
    assert.equal(active().current_cycle, cycle);
    assert.equal(active().completed_pomodoros, cycle);
    assert.equal(store.read({}).todayData.tasks[0].completed_pomodoros, cycle);
    advance();
    if (cycle === 6) break;
    assert.equal(active().status, cycle === 4 ? 'long_break_running' : 'short_break_running');
    assert.equal(active().phase_ends_at - active().phase_started_at, minutes(cycle === 4 ? 15 : 5));
    plan.add(cycle === 4 ? 15 : 5);
    assert.equal(active().status, 'break_elapsed');
    advance();
  }
  assert.equal(active().status, 'session_completed');
  assert.equal(store.read({}).todayData.tasks[0].status, 'in_progress');
  store.command({ type: 'resolve', id: session, completed: true });
  assert.equal(store.read({}).todayData.tasks[0].status, 'completed');
  assert.equal(store.read({}).todayData.record.total_focus_seconds, 6 * 25 * 60);
  assert.equal(plan.notifications.length, 11);
});

test('the optional final long break can be skipped and a continued task can append more cycles', (t) => {
  const plan = setup(t);
  const { store } = plan;
  store.command({ type: 'settings', settings: { ...defaultSettings, finalLongBreak: true, longEvery: 1 } });
  const id = task(store, { pomodoro_enabled: true });
  store.command({ type: 'start', count: 1, taskId: id });
  const session = store.pulse().session!.id;
  plan.add(25);
  assert.equal(store.pulse().session!.nextBreak, 'long_break');
  store.command({ type: 'endSession', id: session });
  assert.equal(store.pulse().session!.status, 'session_completed');
  store.command({ type: 'resolve', id: session, completed: false });
  store.command({ type: 'start', count: 1, taskId: id });
  plan.add(25);
  assert.equal(store.read({}).todayData.tasks[0].completed_pomodoros, 2);
});

test('interruption captures the reason, leaves thoughts intact, and counts no tomato', (t) => {
  const plan = setup(t, true);
  const id = task(plan.store, { pomodoro_enabled: true });
  plan.store.command({ type: 'start', count: 2, taskId: id });
  const session = plan.store.pulse().session!.id;
  plan.store.command({ type: 'saveThought', content: '把资料放进草稿' });
  assert.throws(() => plan.store.command({ type: 'toggleTask', id }), /专注期间/);
  assert.throws(() => plan.store.command({ type: 'interrupt', id: session, reason: ' ' }));
  plan.add(3);
  plan.store.command({ type: 'interrupt', id: session, reason: '紧急电话' });
  plan.reopen();
  const { todayData, session: active } = plan.store.read({});
  assert.equal(active, null);
  assert.equal(todayData.tasks[0].completed_pomodoros, 0);
  assert.equal(todayData.thoughts[0].session_id, session);
  assert.equal(todayData.activity[0].reason, '紧急电话');
  assert.equal(todayData.activity[0].focus_seconds, 180);
  plan.store.command({ type: 'deleteTask', id });
  assert.equal(plan.store.read({}).todayData.activity[0].title, '设计方案');
  plan.add(1440);
  assert.equal(plan.store.read({}).todayData.thoughts.length, 0);
  assert.equal(plan.store.read({ day }).selectedData.thoughts.length, 1);
});

test('a restart after elapsed time records exactly one completed phase and waits for the user', (t) => {
  const plan = setup(t, true);
  const id = task(plan.store, { pomodoro_enabled: true, planned_pomodoros: 2 });
  plan.store.command({ type: 'start', count: 2, taskId: id });
  const oldEnd = plan.store.pulse().session!.phase_ends_at;
  plan.add(5);
  plan.reopen();
  assert.equal(plan.store.pulse().session!.phase_ends_at, oldEnd);
  assert.equal(plan.store.pulse().session!.status, 'focus_running');
  plan.add(48 * 60);
  plan.reopen();
  const state = plan.store.pulse().session!;
  assert.equal(state.status, 'focus_elapsed');
  assert.equal(state.completed_pomodoros, 1);
  assert.equal(plan.store.read({ day }).selectedData.record.total_completed_pomodoros, 1);
  plan.store.command({ type: 'advance', id: state.id });
  plan.add(100);
  plan.reopen();
  assert.equal(plan.store.pulse().session!.status, 'break_elapsed');
  assert.equal(plan.store.pulse().session!.current_cycle, 1);
});

test('quick focus saves to today only when requested and a resolved backup restores atomically', (t) => {
  const plan = setup(t);
  const { store } = plan;
  for (const saveQuick of [false, true]) {
    store.command({ type: 'start', count: 1, title: '自由阅读' });
    const id = store.pulse().session!.id;
    plan.add(25);
    store.command({ type: 'advance', id });
    store.command({ type: 'resolve', id, completed: saveQuick, saveQuick });
  }
  assert.equal(store.read({}).todayData.tasks.length, 1);
  assert.equal(store.read({}).todayData.tasks[0].status, 'completed');
  const raw = exportBackup(store.db);
  task(store, { title: '备份之外' });
  restoreBackup(store.db, raw);
  assert.equal(store.read({}).todayData.tasks.length, 1);
  const broken = JSON.parse(raw);
  broken.data.pomodoro_cycles[0].session_id = 'missing';
  assert.throws(() => restoreBackup(store.db, JSON.stringify(broken)), /无法恢复/);
  assert.equal(exportBackup(store.db), raw);
});

test('an interrupted quick session can become a single task without counting the interrupted cycle', (t) => {
  const plan = setup(t);
  plan.store.command({ type: 'start', count: 1, title: '随手练习' });
  const id = plan.store.pulse().session!.id;
  plan.store.command({ type: 'interrupt', id, reason: '需要离开' });
  assert.equal(plan.store.read({}).todayData.tasks.length, 0);
  plan.store.command({ type: 'saveInterruptedQuick', id });
  assert.throws(() => plan.store.command({ type: 'saveInterruptedQuick', id }), /已保存/);
  const [saved] = plan.store.read({}).todayData.tasks;
  assert.equal(saved.completed_pomodoros, 0);
  assert.equal(saved.title, '随手练习');
});
