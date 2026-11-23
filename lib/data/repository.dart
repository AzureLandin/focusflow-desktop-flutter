/// src-tauri/src/repository.rs 的 1:1 Dart 移植。
/// 命令通过 async 队列串行执行，对齐 React 版 operation.current 的防重入。
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide Query;
import 'package:uuid/uuid.dart';

import '../domain/pomodoro.dart' as pomodoro;
import '../shared/dates.dart';
import '../shared/errors.dart';
import '../shared/model.dart';
import 'db/database.dart';
import 'records.dart';
import 'settings.dart';

class Repository {
  Repository(
    this.db,
    this.dataPath, {
    int Function()? clock,
    this._onElapsed,
  }) : _clock = clock ?? nowMillis;

  final AppDatabase db;
  final String dataPath;
  final int Function() _clock;
  final void Function(String)? _onElapsed;

  /// 上次归档的本地日期；首次 sync 必然归档。
  String? lastDay;

  Future<void> close() => db.close();

  static Future<Repository> open(
    File file, {
    int Function()? clock,
    void Function(String)? onElapsed,
  }) async {
    return Repository(
      await AppDatabase.open(file),
      file.path,
      clock: clock,
      onElapsed: onElapsed,
    );
  }

  /// 关闭并按相同路径/时钟重新打开，用于“重启恢复”用例。
  Future<Repository> reopen() async {
    await db.close();
    return Repository.open(
      File(dataPath),
      clock: _clock,
      onElapsed: _onElapsed,
    );
  }

  int nowOf(int? now) => now ?? _clock();

  // ---------------------------------------------------------------- 串行队列

  Future<void> _last = Future.value();

  Future<T> _lock<T>(Future<T> Function() action) {
    final previous = _last;
    final gate = Completer<void>();
    _last = gate.future;
    return previous
        .then((_) => action(), onError: (Object _) => action())
        .whenComplete(() => gate.complete());
  }

  // ------------------------------------------------------------------ sync

  Future<TimerEvent?> sync([int? now]) => _lock(() => _sync(nowOf(now)));

  Future<TimerEvent?> _sync(int now) async {
    final today = localDay(now);
    final archive = lastDay != today;
    final session = await pomodoro.activeSession(db);
    final due = session != null && pomodoro.isDue(session, now);
    if (!archive && !due) return null;

    final event = await db.transaction(() async {
      TimerEvent? e;
      if (due) {
        final message = await pomodoro.tick(db, session, today, now);
        final preferences = await readSettings(db);
        e = TimerEvent(
          message: message,
          sound: preferences.sound,
          notify: preferences.notifications,
        );
      }
      if (archive) await _archiveDays(db, today, now);
      lastDay = today;
      return e;
    });
    if (event != null) _onElapsed?.call(event.message);
    return event;
  }

  Future<Pulse> pulse([int? now]) => _lock(() async {
        final n = nowOf(now);
        await _sync(n);
        return _pulse(n);
      });

  Future<Pulse> _pulse(int now) async => Pulse(
        now: now,
        today: localDay(now),
        session: await pomodoro.view(db),
      );

  // ------------------------------------------------------------------ read

  Future<Workspace> read(Query query, [int? now]) => _lock(() async {
        final n = nowOf(now);
        await _sync(n);
        final pulse = await _pulse(n);
        final selected = query.day ?? pulse.today;
        parseDate(selected);
        final month = parseDate(query.month ?? pulse.today);
        final calendar = <DayRecord>[];
        for (final day in calendarDays(month)) {
          calendar.add(await record(db, day));
        }
        final todayData = await dayData(db, pulse.today);
        final selectedData = selected == pulse.today
            ? todayData
            : await dayData(db, selected);
        return Workspace(
          pulse: pulse,
          todayData: todayData,
          selectedData: selectedData,
          calendar: calendar,
          settings: await readSettings(db),
          dataPath: dataPath,
        );
      });

  // --------------------------------------------------------------- command

  Future<void> run(Command command, [int? now]) =>
      _lock(() => _run(command, nowOf(now)));

  /// 兼容 Rust 侧的命名。
  Future<void> command(Command value, [int? now]) => run(value, now);

  Future<void> _run(Command input, int now) async {
    final command = input.validate();
    await _sync(now);
    final today = localDay(now);
    await db.transaction(() async {
      final active = await pomodoro.activeSession(db);
      if (active != null && command.requiresIdle) {
        throw FocusFlowException('专注期间请先结束当前会话。');
      }
      await _apply(command, active, today, now);
    });
  }

  Future<void> _apply(
    Command command,
    Session? active,
    String today,
    int now,
  ) async {
    switch (command) {
      case SaveTask(:final id, :final task):
        await saveTask(db, id, task, today, now);

      case ToggleTask(:final id):
        final task = await taskOnEditableDay(db, id, today);
        await toggleTask(db, task, now);

      case MoveTask(:final id, :final direction):
        final task = await taskOnEditableDay(db, id, today);
        await moveTask(db, task, direction, now);

      case DeleteTask(:final id):
        final task = await taskOnEditableDay(db, id, today);
        await db.customStatement(
          'UPDATE tasks SET deleted_at=?,updated_at=? WHERE id=?',
          [now, now, task.id],
        );

      case SaveThought(:final id, :final content):
        if (id != null) {
          await checkThought(db, id, today);
          await db.customStatement(
            'UPDATE thought_notes SET content=?,updated_at=? WHERE id=?',
            [content, now, id],
          );
        } else {
          await db.customStatement(
            'INSERT INTO thought_notes VALUES (?,?,?,?,?,?)',
            [const Uuid().v4(), today, active?.id, content, now, now],
          );
        }

      case DeleteThought(:final id):
        await checkThought(db, id, today);
        await db.customStatement(
          'DELETE FROM thought_notes WHERE id=?',
          [id],
        );

      case Start(:final taskId, :final title, :final count):
        final task = taskId == null ? null : await taskById(db, taskId);
        if (task != null &&
            (task.status == 'completed' ||
                task.scheduledDate != today ||
                task.pomodoroEnabled == 0)) {
          throw FocusFlowException(
            '请从今天启用了番茄时钟的待完成任务开始。',
          );
        }
        final focusTitle = task?.title ?? title;
        if (focusTitle == null) {
          throw FocusFlowException('请输入这次想专注做的事。');
        }
        await pomodoro.start(
          db,
          title: focusTitle,
          taskId: taskId,
          plan: count,
          now: now,
          rules: await readSettings(db),
        );

      case Advance(:final id):
        await pomodoro.advance(db, id, now);

      case EndSession(:final id):
        await pomodoro.end(db, id, now);

      case Interrupt(:final id, :final reason):
        await pomodoro.interrupt(db, id, reason, today, now);

      case SaveInterruptedQuick(:final id):
        await pomodoro.saveInterruptedQuick(db, id, today, now);

      case Resolve(:final id, :final completed, :final saveQuick):
        await pomodoro.resolve(
          db,
          id: id,
          completed: completed,
          saveQuick: saveQuick,
          today: today,
          now: now,
        );

      case SettingsCommand(:final settings):
        await writeSettings(db, settings);
    }
  }
}

// ---------------------------------------------------------------- 辅助函数

Future<Task> taskById(DatabaseConnectionUser db, String id) async {
  final rows = await db.customSelect(
    'SELECT * FROM tasks WHERE id=? AND deleted_at IS NULL',
    variables: [Variable.withString(id)],
  ).get();
  if (rows.isEmpty) {
    throw FocusFlowException('这项任务已删除或不存在。');
  }
  return Task.fromRow(rows.single.data);
}

void ensureEditable(String date, String today) {
  if (date.compareTo(today) < 0) {
    throw FocusFlowException('历史日期仅供查看。请选择今天或未来日期。');
  }
}

Future<Task> taskOnEditableDay(
  DatabaseConnectionUser db,
  String id,
  String today,
) async {
  final task = await taskById(db, id);
  ensureEditable(task.scheduledDate, today);
  return task;
}

Future<int> nextOrder(DatabaseConnectionUser db, String date) async {
  final rows = await db.customSelect(
    'SELECT COALESCE(MAX(sort_order),-1)+1 AS next FROM tasks '
    'WHERE scheduled_date=? AND deleted_at IS NULL',
    variables: [Variable.withString(date)],
  ).get();
  return rows.single.read<int>('next');
}

Future<String> insertTask(
  DatabaseConnectionUser db,
  TaskInput task,
  int now,
  int count,
) async {
  final id = const Uuid().v4();
  await db.customStatement(
    'INSERT INTO tasks (id,title,description,scheduled_date,status,'
    'pomodoro_enabled,planned_pomodoros,completed_pomodoros,sort_order,'
    'created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
    [
      id,
      task.title,
      task.description,
      task.scheduledDate,
      count == 0 ? 'todo' : 'in_progress',
      task.pomodoroEnabled ? 1 : 0,
      task.plannedPomodoros,
      count,
      await nextOrder(db, task.scheduledDate),
      now,
      now,
    ],
  );
  return id;
}

Future<void> saveTask(
  DatabaseConnectionUser db,
  String? id,
  TaskInput task,
  String today,
  int now,
) async {
  ensureEditable(task.scheduledDate, today);
  if (id == null) {
    await insertTask(db, task, now, 0);
    return;
  }
  final previous = await taskOnEditableDay(db, id, today);
  final order = previous.scheduledDate == task.scheduledDate
      ? previous.sortOrder
      : await nextOrder(db, task.scheduledDate);
  await db.customStatement(
    'UPDATE tasks SET title=?,description=?,scheduled_date=?,'
    'pomodoro_enabled=?,planned_pomodoros=?,sort_order=?,updated_at=? WHERE id=?',
    [
      task.title,
      task.description,
      task.scheduledDate,
      task.pomodoroEnabled ? 1 : 0,
      task.plannedPomodoros,
      order,
      now,
      id,
    ],
  );
}

Future<void> toggleTask(DatabaseConnectionUser db, Task task, int now) async {
  final String status;
  final int? completedAt;
  if (task.status != 'completed') {
    status = 'completed';
    completedAt = now;
  } else if (task.completedPomodoros > 0) {
    status = 'in_progress';
    completedAt = null;
  } else {
    status = 'todo';
    completedAt = null;
  }
  await db.customStatement(
    'UPDATE tasks SET status=?,completed_at=?,updated_at=? WHERE id=?',
    [status, completedAt, now, task.id],
  );
}

Future<void> moveTask(
  DatabaseConnectionUser db,
  Task task,
  int direction,
  int now,
) async {
  final rows = await db.customSelect(
    'SELECT * FROM tasks WHERE scheduled_date=? AND deleted_at IS NULL '
    "AND (status='completed')=? ORDER BY sort_order,id",
    variables: [
      Variable.withString(task.scheduledDate),
      Variable.withInt(task.status == 'completed' ? 1 : 0),
    ],
  ).get();
  final peers = rows.map((row) => Task.fromRow(row.data)).toList();
  final index = peers.indexWhere((peer) => peer.id == task.id);
  if (index < 0) return;
  final target = index + direction;
  if (target < 0 || target >= peers.length) return;
  final neighbor = peers[target];
  await db.customStatement(
    'UPDATE tasks SET sort_order=?,updated_at=? WHERE id=?',
    [neighbor.sortOrder, now, task.id],
  );
  await db.customStatement(
    'UPDATE tasks SET sort_order=?,updated_at=? WHERE id=?',
    [task.sortOrder, now, neighbor.id],
  );
}

Future<void> checkThought(
  DatabaseConnectionUser db,
  String id,
  String today,
) async {
  final rows = await db.customSelect(
    'SELECT EXISTS(SELECT 1 FROM thought_notes WHERE id=? AND local_date=?) AS ok',
    variables: [Variable.withString(id), Variable.withString(today)],
  ).get();
  if (rows.single.read<int>('ok') != 1) {
    throw FocusFlowException('只能修改当天的番茄想法。');
  }
}

Future<void> _archiveDays(
  DatabaseConnectionUser db,
  String today,
  int now,
) async {
  await db.customStatement(
    "INSERT OR IGNORE INTO app_settings VALUES ('archive_origin',?)",
    [today],
  );
  final firstRows = await db.customSelect(
    'SELECT MIN(day) AS first FROM ('
    'SELECT scheduled_date AS day FROM tasks WHERE deleted_at IS NULL '
    'UNION ALL SELECT local_date FROM thought_notes '
    'UNION ALL SELECT local_date FROM pomodoro_cycles '
    "UNION ALL SELECT value FROM app_settings WHERE key='archive_origin')",
  ).get();
  final first = firstRows.single.read<String>('first');

  final archivedRows = await db.customSelect(
    'SELECT date FROM daily_records WHERE date>=? AND date<?',
    variables: [Variable.withString(first), Variable.withString(today)],
  ).get();
  final archived = archivedRows.map((row) => row.read<String>('date')).toSet();

  await db.customStatement(
    "UPDATE tasks SET status='unfinished',updated_at=? WHERE scheduled_date<? "
    "AND deleted_at IS NULL AND status IN ('todo','in_progress')",
    [now, today],
  );

  var date = first;
  while (date.compareTo(today) < 0) {
    if (!archived.contains(date)) {
      await storeRecord(db, date, now);
    }
    date = shiftDay(date, 1);
  }
}
