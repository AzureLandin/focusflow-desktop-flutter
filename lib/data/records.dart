import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../shared/model.dart';

/// repository.rs:241-282 与 321-339 的共享 SQL 辅助。

Future<DayRecord> stats(DatabaseConnectionUser db, String date) async {
  final rows = await db.customSelect(
    'SELECT ?1 AS date, NULL AS finalized_at, total_tasks, completed_tasks, '
    'unfinished_tasks, total_completed_pomodoros, total_focus_seconds FROM '
    '(SELECT COUNT(*) AS total_tasks, '
    "COUNT(*) FILTER (WHERE status='completed') AS completed_tasks, "
    "COUNT(*) FILTER (WHERE status!='completed') AS unfinished_tasks "
    'FROM tasks WHERE scheduled_date=?1 AND deleted_at IS NULL), '
    '(SELECT COUNT(*) AS total_completed_pomodoros, '
    "COALESCE(SUM(focus_seconds),0) AS total_focus_seconds FROM pomodoro_cycles "
    "WHERE local_date=?1 AND status='completed')",
    variables: [Variable.withString(date)],
  ).get();
  return DayRecord.fromRow(rows.single.data);
}

Future<void> storeRecord(
  DatabaseConnectionUser db,
  String date,
  int now,
) async {
  final r = await stats(db, date);
  await db.customStatement(
    'INSERT INTO daily_records VALUES (?,?,?,?,?,?,?) ON CONFLICT(date) DO UPDATE SET '
    'total_tasks=excluded.total_tasks, completed_tasks=excluded.completed_tasks, '
    'unfinished_tasks=excluded.unfinished_tasks, '
    'total_completed_pomodoros=excluded.total_completed_pomodoros, '
    'total_focus_seconds=excluded.total_focus_seconds',
    [
      date,
      now,
      r.totalTasks,
      r.completedTasks,
      r.unfinishedTasks,
      r.totalCompletedPomodoros,
      r.totalFocusSeconds,
    ],
  );
}

Future<DayRecord> record(DatabaseConnectionUser db, String date) async {
  final rows = await db.customSelect(
    'SELECT * FROM daily_records WHERE date=?',
    variables: [Variable.withString(date)],
  ).get();
  if (rows.isEmpty) return stats(db, date);
  return DayRecord.fromRow(rows.single.data);
}

Future<DayData> dayData(DatabaseConnectionUser db, String date) async {
  final tasks = await db.customSelect(
    'SELECT * FROM tasks WHERE scheduled_date=? AND deleted_at IS NULL '
    'ORDER BY sort_order,id',
    variables: [Variable.withString(date)],
  ).get();
  final thoughts = await db.customSelect(
    'SELECT * FROM thought_notes WHERE local_date=? ORDER BY created_at DESC,id',
    variables: [Variable.withString(date)],
  ).get();
  final activity = await db.customSelect(
    'SELECT c.id,s.task_title_snapshot AS title,c.cycle_index,i.reason,'
    'c.ended_at,c.focus_seconds FROM pomodoro_cycles c '
    'JOIN pomodoro_sessions s ON s.id=c.session_id '
    'LEFT JOIN pomodoro_interruptions i ON i.cycle_id=c.id '
    'WHERE c.local_date=? ORDER BY c.ended_at DESC',
    variables: [Variable.withString(date)],
  ).get();
  return DayData(
    tasks: tasks.map((row) => Task.fromRow(row.data)).toList(),
    thoughts: thoughts.map((row) => Thought.fromRow(row.data)).toList(),
    record: await record(db, date),
    activity: activity.map((row) => Activity.fromRow(row.data)).toList(),
  );
}

/// repository.rs:321-339：把一次专注的快照转成当天的快速任务。
Future<String> insertQuickTask(
  DatabaseConnectionUser db,
  Session session,
  String today,
  int now,
) async {
  final id = const Uuid().v4();
  final rows = await db.customSelect(
    'SELECT COALESCE(MAX(sort_order),-1)+1 AS next FROM tasks '
    'WHERE scheduled_date=? AND deleted_at IS NULL',
    variables: [Variable.withString(today)],
  ).get();
  final next = rows.single.read<int>('next');
  await db.customStatement(
    'INSERT INTO tasks (id,title,description,scheduled_date,status,'
    'pomodoro_enabled,planned_pomodoros,completed_pomodoros,sort_order,'
    'created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
    [
      id,
      session.taskTitleSnapshot,
      '',
      today,
      session.completedPomodoros == 0 ? 'todo' : 'in_progress',
      1,
      session.plannedPomodoros,
      session.completedPomodoros,
      next,
      now,
      now,
    ],
  );
  return id;
}
