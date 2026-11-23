/// src-tauri/src/pomodoro.rs 的 1:1 Dart 移植。
/// 所有函数都接受 DatabaseConnectionUser，因此既能直接用在 AppDatabase 上，
/// 也能用在 repository.run() 开启的事务里。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/records.dart';
import '../shared/dates.dart';
import '../shared/errors.dart';
import '../shared/model.dart';

Future<Session?> activeSession(DatabaseConnectionUser db) async {
  final rows = await db.customSelect(
    "SELECT * FROM pomodoro_sessions WHERE status NOT IN ('interrupted','completed')",
  ).get();
  if (rows.isEmpty) return null;
  return Session.fromRow(rows.single.data);
}

Future<Session> findSession(DatabaseConnectionUser db, String id) async {
  final session = await activeSession(db);
  if (session == null || session.id != id) {
    throw FocusFlowException('该专注会话已结束，请刷新后重试。');
  }
  return session;
}

Settings sessionRules(Session session) {
  try {
    final settings = Settings.fromJson(
      jsonDecode(session.rules) as Map<String, dynamic>,
    );
    settings.validate();
    return settings;
  } on FocusFlowException {
    rethrow;
  } on Object {
    throw FocusFlowException('本地数据格式有误。请核对备份后重试。');
  }
}

/// pomodoro.rs:33-39。
String? nextBreak(int completed, int planned, Settings rules) {
  final long = completed % rules.longEvery == 0;
  if (completed >= planned) {
    return long && rules.finalLongBreak ? 'long_break' : null;
  }
  return long ? 'long_break' : 'short_break';
}

Future<ActiveSession?> view(DatabaseConnectionUser db) async {
  final session = await activeSession(db);
  if (session == null) return null;

  final focusRows = await db.customSelect(
    "SELECT COALESCE(SUM(focus_seconds),0) AS n FROM pomodoro_cycles "
    "WHERE session_id=? AND status='completed'",
    variables: [Variable.withString(session.id)],
  ).get();
  final thoughtRows = await db.customSelect(
    'SELECT COUNT(*) AS n FROM thought_notes WHERE session_id=?',
    variables: [Variable.withString(session.id)],
  ).get();

  String? breakName;
  if (session.currentPhase == 'focus') {
    final projected =
        session.completedPomodoros + (session.status == 'focus_running' ? 1 : 0);
    breakName = nextBreak(projected, session.plannedPomodoros, sessionRules(session));
  }

  return ActiveSession(
    session: session,
    nextBreak: breakName,
    focusSeconds: focusRows.single.read<int>('n'),
    thoughtCount: thoughtRows.single.read<int>('n'),
    canConfirm: await canConfirm(db, session),
  );
}

/// pomodoro.rs:68-87。
Future<void> start(
  DatabaseConnectionUser db, {
  required String title,
  required String? taskId,
  required int plan,
  required int now,
  required Settings rules,
}) async {
  await db.customStatement(
    'INSERT INTO pomodoro_sessions '
    "(id,task_id,task_title_snapshot,planned_pomodoros,current_cycle,current_phase,"
    "status,phase_started_at,phase_ends_at,started_at,rules) "
    "VALUES (?,?,?,?,1,'focus','focus_running',?,?,?,?)",
    [
      const Uuid().v4(),
      taskId,
      title,
      plan,
      now,
      now + rules.focusMinutes * 60_000,
      now,
      jsonEncode(rules.toJson()),
    ],
  );
  if (taskId != null) {
    await db.customStatement(
      "UPDATE tasks SET status='in_progress', updated_at=? WHERE id=?",
      [now, taskId],
    );
  }
}

bool isDue(Session session, int now) =>
    const {'focus_running', 'short_break_running', 'long_break_running'}
        .contains(session.status) &&
    now >= session.phaseEndsAt;

/// pomodoro.rs:96-126。到期推进，重复调用幂等。
Future<String> tick(
  DatabaseConnectionUser db,
  Session session,
  String today,
  int now,
) async {
  if (session.status != 'focus_running') {
    await db.customStatement(
      "UPDATE pomodoro_sessions SET status='break_elapsed' WHERE id=?",
      [session.id],
    );
    return '休息结束，可以继续了';
  }
  final end = session.phaseEndsAt;
  final start = session.phaseStartedAt;
  final day = localDay(end);
  await db.customStatement(
    'INSERT INTO pomodoro_cycles '
    "(id,session_id,cycle_index,status,started_at,ended_at,local_date,focus_seconds) "
    "VALUES (?,?,?,'completed',?,?,?,?)",
    [
      const Uuid().v4(),
      session.id,
      session.currentCycle,
      start,
      end,
      day,
      (end - start) ~/ 1000,
    ],
  );
  await db.customStatement(
    "UPDATE pomodoro_sessions SET status='focus_elapsed',"
    'completed_pomodoros=completed_pomodoros+1 WHERE id=?',
    [session.id],
  );
  if (session.taskId != null) {
    await db.customStatement(
      'UPDATE tasks SET completed_pomodoros=completed_pomodoros+1,updated_at=? '
      'WHERE id=?',
      [now, session.taskId],
    );
  }
  if (day.compareTo(today) < 0) {
    await storeRecord(db, day, now);
  }
  return '本轮专注已完成';
}

Future<void> startPhase(
  DatabaseConnectionUser db, {
  required String id,
  required String phase,
  required int minutes,
  required int now,
  required bool finalBreak,
}) async {
  await db.customStatement(
    'UPDATE pomodoro_sessions SET current_phase=?,status=?,phase_started_at=?,'
    'phase_ends_at=?,current_cycle=current_cycle+?,ending_break=? WHERE id=?',
    [
      phase,
      '${phase}_running',
      now,
      now + minutes * 60_000,
      phase == 'focus' ? 1 : 0,
      finalBreak ? 1 : 0,
      id,
    ],
  );
}

Future<void> summarize(DatabaseConnectionUser db, String id, int now) async {
  await db.customStatement(
    "UPDATE pomodoro_sessions SET status='session_completed',finished_at=? "
    'WHERE id=?',
    [now, id],
  );
}

/// pomodoro.rs:160-191。
Future<void> advance(DatabaseConnectionUser db, String id, int now) async {
  final session = await findSession(db, id);
  final rules = sessionRules(session);
  switch (session.status) {
    case 'focus_elapsed':
      final next = nextBreak(
        session.completedPomodoros,
        session.plannedPomodoros,
        rules,
      );
      if (next != null) {
        final minutes = next == 'long_break'
            ? rules.longMinutes
            : rules.shortMinutes;
        await startPhase(
          db,
          id: id,
          phase: next,
          minutes: minutes,
          now: now,
          finalBreak:
              session.completedPomodoros == session.plannedPomodoros,
        );
      } else {
        await summarize(db, id, now);
      }
    case 'break_elapsed':
      if (session.endingBreak == 1) {
        await summarize(db, id, now);
      } else {
        await startPhase(
          db,
          id: id,
          phase: 'focus',
          minutes: rules.focusMinutes,
          now: now,
          finalBreak: false,
        );
      }
    default:
      throw FocusFlowException('请等待当前阶段结束。');
  }
}

/// pomodoro.rs:193-202。
Future<void> end(DatabaseConnectionUser db, String id, int now) async {
  final session = await findSession(db, id);
  if (session.status == 'focus_running' ||
      session.status == 'session_completed') {
    throw FocusFlowException('请先结束正在进行的专注阶段。');
  }
  await summarize(db, id, now);
}

/// pomodoro.rs:204-221。
Future<void> interrupt(
  DatabaseConnectionUser db,
  String id,
  String reason,
  String day,
  int now,
) async {
  final session = await findSession(db, id);
  if (session.status != 'focus_running') {
    throw FocusFlowException('本轮专注已结束，无法再标记为打断。');
  }
  final cycle = const Uuid().v4();
  final end = now > session.phaseStartedAt ? now : session.phaseStartedAt;
  await db.customStatement(
    'INSERT INTO pomodoro_cycles '
    "(id,session_id,cycle_index,status,started_at,ended_at,local_date,focus_seconds) "
    "VALUES (?,?,?,'interrupted',?,?,?,?)",
    [
      cycle,
      id,
      session.currentCycle,
      session.phaseStartedAt,
      end,
      day,
      (end - session.phaseStartedAt) ~/ 1000,
    ],
  );
  await db.customStatement(
    'INSERT INTO pomodoro_interruptions (id,session_id,cycle_id,reason,occurred_at) '
    'VALUES (?,?,?,?,?)',
    [const Uuid().v4(), id, cycle, reason, now],
  );
  await db.customStatement(
    "UPDATE pomodoro_sessions SET status='interrupted',finished_at=? WHERE id=?",
    [now, id],
  );
}

Future<bool> canConfirm(DatabaseConnectionUser db, Session session) async {
  if (session.taskId == null) return true;
  final rows = await db.customSelect(
    'SELECT completed_pomodoros>=planned_pomodoros AS ok FROM tasks WHERE id=?',
    variables: [Variable.withString(session.taskId!)],
  ).get();
  if (rows.isEmpty) return false;
  return rows.single.read<int>('ok') == 1;
}

/// pomodoro.rs:237-276。
Future<void> resolve(
  DatabaseConnectionUser db, {
  required String id,
  required bool completed,
  required bool saveQuick,
  required String today,
  required int now,
}) async {
  final session = await findSession(db, id);
  if (session.status != 'session_completed') {
    throw FocusFlowException('请先结束专注会话。');
  }
  if (completed && !await canConfirm(db, session)) {
    throw FocusFlowException('该任务还未达到计划番茄数。');
  }
  final String? task;
  if (session.taskId == null && saveQuick) {
    task = await insertQuickTask(db, session, today, now);
  } else {
    task = session.taskId;
  }
  if (task != null && completed) {
    await db.customStatement(
      "UPDATE tasks SET status='completed',completed_at=?,updated_at=? WHERE id=?",
      [now, now, task],
    );
    final rows = await db.customSelect(
      'SELECT scheduled_date FROM tasks WHERE id=?',
      variables: [Variable.withString(task)],
    ).get();
    final scheduled = rows.single.read<String>('scheduled_date');
    if (scheduled.compareTo(today) < 0) {
      await storeRecord(db, scheduled, now);
    }
  }
  await db.customStatement(
    "UPDATE pomodoro_sessions SET status='completed',task_id=? WHERE id=?",
    [task, id],
  );
}

/// pomodoro.rs:278-287。
Future<void> saveInterruptedQuick(
  DatabaseConnectionUser db,
  String id,
  String day,
  int now,
) async {
  final rows = await db.customSelect(
    "SELECT * FROM pomodoro_sessions WHERE id=? AND status='interrupted' "
    'AND task_id IS NULL',
    variables: [Variable.withString(id)],
  ).get();
  if (rows.isEmpty) {
    throw FocusFlowException('该次快速专注已保存或不存在。');
  }
  final task =
      await insertQuickTask(db, Session.fromRow(rows.single.data), day, now);
  await db.customStatement(
    'UPDATE pomodoro_sessions SET task_id=? WHERE id=?',
    [task, id],
  );
}
