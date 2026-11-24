/// widget 测试用的 DesktopApi 替身：真实 Repository + 临时目录数据库，
/// 额外提供命令记录、失败注入与会话/记录种子数据。
library;

import 'dart:io';

import 'package:focusflow/data/db/database.dart';
import 'package:focusflow/data/repository.dart';
import 'package:focusflow/shared/model.dart';
import 'package:focusflow/state/desktop_api.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

class TestDesktopApi implements DesktopApi {
  TestDesktopApi._(this._dir);

  late final Repository _repository;
  final Directory _dir;

  final List<Command> commands = <Command>[];
  final Set<Type> failOn = <Type>{};
  int _now = DateTime(2026, 11, 23, 10).millisecondsSinceEpoch;

  AppDatabase get db => _repository.db;
  String get dataPath => _repository.dataPath;
  int get now => _now;

  static Future<TestDesktopApi> create() async {
    final dir = Directory.systemTemp.createTempSync('focusflow-ui-');
    final file = File(p.join(dir.path, 'focusflow.sqlite3'));
    final api = TestDesktopApi._(dir);
    api._repository = await Repository.open(file, clock: () => api._now);
    addTearDown(api.dispose);
    return api;
  }

  void advance(int minutes) => _now += minutes * 60_000;

  @override
  Future<void> dispose() async {
    await _repository.close();
    if (_dir.existsSync()) _dir.deleteSync(recursive: true);
  }

  @override
  Future<Workspace> read(Query query) => _repository.read(query, _now);

  @override
  Future<PulseResult> pulse() async {
    final event = await _repository.sync(_now);
    return PulseResult(pulse: await _repository.pulse(_now), event: event);
  }

  @override
  Future<void> run(Command command) async {
    commands.add(command);
    if (failOn.contains(command.runtimeType)) {
      throw StateError('FF:模拟命令失败');
    }
    await _repository.run(command, _now);
  }

  @override
  Future<bool> backup(String action) async => false;

  Future<String> seedTask(
    String title, {
    String? scheduledDate,
    String status = 'todo',
    int pomodoroEnabled = 0,
    int planned = 1,
    int completedPomodoros = 0,
    int sortOrder = 0,
  }) async {
    // 命令校验要求 UUID（对齐 zod 的 z.uuid()），种子数据也必须用真 UUID。
    final id = const Uuid().v4();
    await db.customStatement(
      'INSERT INTO tasks (id,title,description,scheduled_date,status,'
      'pomodoro_enabled,planned_pomodoros,completed_pomodoros,sort_order,'
      'created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        title,
        '',
        scheduledDate ?? '2026-11-23',
        status,
        pomodoroEnabled,
        planned,
        completedPomodoros,
        sortOrder,
        _now,
        _now,
      ],
    );
    return id;
  }

  Future<void> seedThought(String content) async {
    await db.customStatement(
      'INSERT INTO thought_notes VALUES (?,?,?,?,?,?)',
      [
        const Uuid().v4(),
        '2026-11-23',
        null,
        content,
        _now,
        _now,
      ],
    );
  }

  Future<String> seedSession({
    required String status,
    String phase = 'focus',
    int cycle = 1,
    int completed = 0,
    int planned = 1,
    String? taskId,
    String title = '专注任务',
    bool endingBreak = false,
    int focusMinutes = 25,
  }) async {
    final id = const Uuid().v4();
    await db.customStatement(
      'INSERT INTO pomodoro_sessions (id,task_id,task_title_snapshot,'
      'planned_pomodoros,completed_pomodoros,current_cycle,current_phase,status,'
      'phase_started_at,phase_ends_at,started_at,rules,ending_break) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        taskId,
        title,
        planned,
        completed,
        cycle,
        phase,
        status,
        _now,
        _now + focusMinutes * 60_000,
        _now,
        '{"focusMinutes":$focusMinutes,"shortMinutes":5,"longMinutes":15,'
        '"longEvery":4,"sound":true,"notifications":true,'
        '"finalLongBreak":false,"theme":"system"}',
        endingBreak ? 1 : 0,
      ],
    );
    return id;
  }
}
