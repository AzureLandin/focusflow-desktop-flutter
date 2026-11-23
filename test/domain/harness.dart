import 'dart:io';

import 'package:focusflow/data/repository.dart';
import 'package:focusflow/shared/dates.dart';
import 'package:focusflow/shared/model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// 对应 Rust tests/domain.rs 的 Harness 与 TS tests/domain.test.ts 的 setup：
/// 临时目录数据库 + 可推进的假时钟 + 到期事件记录。
class Harness {
  Harness({String fileName = '专注 测试.sqlite3', int hour = 10})
      : _dir = Directory.systemTemp.createTempSync('focusflow-domain-'),
        now = DateTime(2026, 11, 23, hour).millisecondsSinceEpoch {
    path = p.join(_dir.path, fileName);
    addTearDown(() {
      if (_dir.existsSync()) _dir.deleteSync(recursive: true);
    });
  }

  final Directory _dir;
  late String path;
  int now;
  late Repository repo;
  final List<String> notifications = [];

  Future<void> init() async {
    await open();
    await sync();
  }

  Future<void> open() async {
    repo = await Repository.open(
      File(path),
      clock: () => now,
      onElapsed: notifications.add,
    );
    addTearDown(() async {
      try {
        await repo.close();
      } on Object {
        // 已关闭的库重复关闭无需处理。
      }
    });
  }

  String get day => localDay(now);
  String get dirPath => _dir.path;

  Future<void> close() => repo.close();

  Future<void> reopen() async {
    await repo.close();
    await open();
  }

  Future<bool> sync() async => (await repo.sync(now)) != null;

  void elapse([int minutes = 1]) => now += minutes * 60_000;
  void setTime(String date) => now = DateTime.parse('${date}T12:00:00').millisecondsSinceEpoch;

  Future<void> cmd(Command command) => repo.run(command, now);

  Future<Workspace> read([String? day]) =>
      repo.read(Query(day: day), now);

  Future<ActiveSession> active() async {
    final session = (await repo.pulse(now)).session;
    if (session == null) throw StateError('期望存在活动会话');
    return session;
  }

  Future<String> task(
    String title, {
    String? day,
    int count = 1,
    bool pomodoroEnabled = true,
  }) async {
    final target = day ?? this.day;
    final input = TaskInput(
      title: title,
      description: '',
      scheduledDate: target,
      pomodoroEnabled: pomodoroEnabled,
      plannedPomodoros: count,
    );
    await cmd(SaveTask(task: input));
    // 与 TS 版 task() 一致：取最后插入的任务，允许重名。
    final rows = await repo.db.customSelect(
      'SELECT id FROM tasks ORDER BY rowid DESC LIMIT 1',
    ).get();
    return rows.single.read<String>('id');
  }

  String newPath(String name) => p.join(_dir.path, name);
}
