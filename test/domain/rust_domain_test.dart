/// src-tauri/tests/domain.rs 的 7 个用例逐条移植（文件:行号见每个 test 注释）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:focusflow/data/backup.dart';
import 'package:focusflow/data/db/database.dart';
import 'package:focusflow/data/db/migrations.dart';
import 'package:focusflow/shared/dates.dart';
import 'package:focusflow/shared/errors.dart';
import 'package:focusflow/shared/model.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'harness.dart';

void main() {
  /// domain.rs:78 sqlite_schema_pragmas_and_exclusive_locking
  test('R1 sqlite schema / pragmas / exclusive locking', () async {
    final dir = Directory.systemTemp.createTempSync('focusflow-lock-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final file = File(p.join(dir.path, 'lock.sqlite3'));
    final db = await AppDatabase.open(file);
    addTearDown(db.close);

    Future<int> ipragma(String name) async {
      final rows = await db.customSelect('PRAGMA $name').get();
      return rows.single.read<int>(rows.single.data.keys.first);
    }

    expect(await ipragma('user_version'), 1);
    expect(await ipragma('foreign_keys'), 1);
    expect(await ipragma('synchronous'), 2);
    expect(await ipragma('busy_timeout'), 3000);
    final journal = await db.customSelect('PRAGMA journal_mode').get();
    expect(journal.single.read<String>('journal_mode'), 'wal');

    expect(
      () => db.customStatement(
        "INSERT INTO thought_notes VALUES ('note','2026-11-23','unknown','测试',1,1)",
      ),
      throwsA(isA<Exception>()),
    );

    final second = sqlite3.open(file.path);
    second.execute('PRAGMA busy_timeout = 25');
    expect(
      () => second.execute(
        "BEGIN IMMEDIATE; UPDATE app_settings SET value='changed'; COMMIT;",
      ),
      throwsA(isA<Exception>()),
    );
    await db.close();
    second.execute(
      "BEGIN; INSERT INTO app_settings VALUES ('rollback-test','1'); ROLLBACK;",
    );
    expect(
      second.select(
        "SELECT COUNT(*) FROM app_settings WHERE key='rollback-test'",
      ).first.columnAt(0),
      0,
    );
    second.close();
  });

  /// domain.rs:130 existing_database_is_snapshotted_and_newer_or_corrupt_databases_are_preserved
  test('R2 老库快照与新版/损坏库保护', () async {
    final dir = Directory.systemTemp.createTempSync('focusflow-legacy-');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final file = File(p.join(dir.path, 'electron-v1.sqlite3'));
    final source = sqlite3.open(file.path);
    for (final statement in migrationStatements) {
      source.execute(statement);
    }
    source.execute('PRAGMA journal_mode=WAL');
    source.execute('PRAGMA user_version=1');
    source.execute(
      "INSERT INTO app_settings VALUES ('archive_origin','2026-11-23')",
    );
    source.close();

    final upgraded = await AppDatabase.open(file);
    await upgraded.close();
    File snapshotOf(Directory d) => d
        .listSync()
        .whereType<File>()
        .firstWhere((f) => p.basename(f.path).startsWith('before-flutter-'));
    final snapshot = sqlite3.open(snapshotOf(dir).path);
    expect(
      snapshot
          .select("SELECT value FROM app_settings WHERE key='archive_origin'")
          .first
          .columnAt(0),
      '2026-11-23',
    );
    snapshot.close();
    await AppDatabase.open(file).then((db) => db.close());
    expect(
      dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('before-flutter-'))
          .length,
      1,
    );

    final high = File(p.join(dir.path, 'newer.sqlite3'));
    final highDb = sqlite3.open(high.path);
    highDb.execute('PRAGMA user_version=2');
    highDb.close();
    final original = high.readAsBytesSync();
    expect(() => AppDatabase.open(high), throwsA(anything));
    expect(high.readAsBytesSync(), original);

    final damaged = File(p.join(dir.path, 'corrupt.sqlite3'));
    damaged.writeAsBytesSync(utf8.encode('not sqlite'));
    final damagedBytes = damaged.readAsBytesSync();
    expect(() => AppDatabase.open(damaged), throwsA(anything));
    expect(damaged.readAsBytesSync(), damagedBytes);
  });

  /// domain.rs:183 task_mutations_calendar_and_archive_keep_dates_and_order
  test('R3 任务变更、日历与跨日归档', () async {
    final h = Harness();
    await h.init();
    final originalPath = h.path;
    final today = h.day;
    final first = await h.task('先做', day: today, count: 1);
    final second = await h.task('后做', day: today, count: 1);
    final future = await h.task('未来', day: '2026-11-26', count: 1);
    expect((await h.read()).todayData.tasks.length, 2);

    await h.cmd(MoveTask(id: second, direction: -1));
    expect((await h.read()).todayData.tasks[0].id, second);

    await h.cmd(
      SaveTask(
        id: first,
        task: TaskInput(
          title: '编辑后',
          description: '任务描述',
          scheduledDate: today,
          pomodoroEnabled: false,
          plannedPomodoros: 2,
        ),
      ),
    );
    await h.cmd(ToggleTask(id: first));
    expect((await h.read()).todayData.record.completedTasks, 1);
    await h.cmd(ToggleTask(id: first));
    expect((await h.read()).todayData.record.completedTasks, 0);
    await h.cmd(DeleteTask(id: second));

    h.elapse(3 * 1440);
    await h.close();
    h.path = h.newPath('reopened.sqlite3');
    await h.open();
    await h.close();
    h.path = originalPath;
    await h.open();
    await h.sync();
    await h.sync();

    final archive = await h.read(today);
    expect(archive.todayData.tasks[0].id, future);
    expect(archive.selectedData.tasks[0].title, '编辑后');
    expect(archive.selectedData.tasks[0].status, 'unfinished');
    expect(archive.selectedData.record.unfinishedTasks, 1);
    expect(
      () => h.cmd(ToggleTask(id: first)),
      throwsA(isA<FocusFlowException>()),
    );
    expect(
      (await h.read('2026-11-24')).selectedData.record.finalizedAt,
      isNotNull,
    );
  });

  /// domain.rs:230 timer_deadlines_are_idempotent_short_long_breaks_and_confirmation
  test('R4 到期幂等、长短休交替与完成确认', () async {
    final h = Harness();
    await h.init();
    final today = h.day;
    final task = await h.task('专注内容', day: today, count: 2);
    await h.cmd(
      SettingsCommand(
        settings: Settings.defaults.copyWith(
          focusMinutes: 1,
          shortMinutes: 1,
          longEvery: 2,
          finalLongBreak: true,
        ),
      ),
    );
    await h.cmd(Start(taskId: task, count: 2));
    final id = (await h.active()).id;

    h.elapse();
    expect(await h.sync(), isTrue);
    expect(await h.sync(), isFalse);
    expect((await h.active()).nextBreak, 'short_break');
    await h.cmd(Advance(id: id));

    h.elapse();
    expect(await h.sync(), isTrue);
    expect((await h.active()).status, 'break_elapsed');
    await h.cmd(Advance(id: id));

    h.elapse(55);
    expect(await h.sync(), isTrue);
    expect((await h.active()).nextBreak, 'long_break');
    expect((await h.read()).todayData.record.totalFocusSeconds, 120);
    await h.cmd(Advance(id: id));
    expect((await h.active()).status, 'long_break_running');

    h.elapse(15);
    expect(await h.sync(), isTrue);
    await h.cmd(Advance(id: id));
    expect((await h.active()).status, 'session_completed');
    await h.cmd(Resolve(id: id, completed: true));
    expect((await h.read()).todayData.tasks[0].status, 'completed');
  });

  /// domain.rs:271 interruption_thoughts_and_quick_save_keep_history
  test('R5 打断、想法与快速保存保留历史', () async {
    final h = Harness();
    await h.init();
    await h.cmd(Start(title: '自由专注', count: 1));
    final id = (await h.active()).id;
    await h.cmd(const SaveThought(content: '  想法  '));
    final thoughts = (await h.read()).todayData.thoughts;
    final note = thoughts.removeAt(0);
    expect(note.content, '想法');
    expect(note.sessionId, id);
    expect(
      () => h.cmd(SaveThought(id: note.id, content: '🙂' * 1001)),
      throwsA(isA<FocusFlowException>()),
    );
    await h.cmd(SaveThought(id: note.id, content: '编辑想法'));
    await h.cmd(Interrupt(id: id, reason: '电话'));
    await h.cmd(SaveInterruptedQuick(id: id));
    expect(
      () => h.cmd(SaveInterruptedQuick(id: id)),
      throwsA(isA<FocusFlowException>()),
    );

    final data = (await h.read()).todayData;
    expect(data.activity[0].reason, '电话');
    expect(data.record.totalCompletedPomodoros, 0);
    await h.cmd(DeleteTask(id: data.tasks[0].id));
    expect((await h.read()).todayData.activity.length, 1);
    await h.cmd(DeleteThought(id: note.id));
    expect((await h.read()).todayData.thoughts.length, 0);
  });

  /// domain.rs:305 backup_format_validation_and_transaction_rollback
  test('R6 备份格式校验与事务回滚', () async {
    final h = Harness();
    await h.init();
    final day = h.day;
    await h.task('备份前任务', day: day);

    // 空库（无表）生成快照应失败。
    final emptyDir = Directory.systemTemp.createTempSync('focusflow-empty-');
    addTearDown(() {
      if (emptyDir.existsSync()) emptyDir.deleteSync(recursive: true);
    });
    final empty = await AppDatabase.open(File(p.join(emptyDir.path, 'e.sqlite3')));
    // 模拟 Rust 的 Connection::open_in_memory()——没有任何表。
    for (final table in kBackupTables.reversed) {
      await empty.customStatement('DROP TABLE $table');
    }
    expect(backupSnapshotOrThrow(empty), throwsA(anything));
    await empty.close();

    final fixture = await _fixture(h, day);
    final path = File(h.newPath('跨平台 备份.json'));
    await writeBackupFile(path, fixture);
    expect(await readBackupFile(path), fixture);

    final bad = <Map<String, dynamic>>[];
    bad.add(<String, dynamic>{'version': 2});
    final missingTitle = deepCopy(fixture);
    (missingTitle['data']['tasks'] as List).first.remove('title');
    bad.add(missingTitle);
    final invalidPlan = deepCopy(fixture);
    (invalidPlan['data']['tasks'] as List).first['planned_pomodoros'] = 99;
    bad.add(invalidPlan);
    final missingSession = deepCopy(fixture);
    missingSession['data']['thought_notes'] = [
      {
        'id': 'd6742157-dc01-42bf-a2a7-6b886becf2b2',
        'local_date': day,
        'session_id': '23028104-d38c-4ebc-8a7b-f4d8ef6029f1',
        'content': '无对应会话',
        'created_at': h.now,
        'updated_at': h.now,
      }
    ];
    bad.add(missingSession);

    for (final value in bad) {
      await expectLater(
        restoreBackup(h.repo, value, h.now),
        throwsA(isA<Exception>()),
      );
      expect((await h.read()).todayData.tasks[0].title, '备份前任务');
    }
    await restoreBackup(h.repo, fixture, h.now);
    expect((await h.read()).todayData.tasks[0].title, '恢复后任务');
    expect(
      Directory(h.dirPath)
          .listSync()
          .any((f) => p.basename(f.path).startsWith('before-restore-')),
      isTrue,
    );
  });

  /// domain.rs:369 calendar_and_date_contract_cover_dst_and_field_casing
  test('R7 DST、日期契约与字段命名', () async {
    tzdata.initializeTimeZones();
    final zone = tz.getLocation('America/New_York');
    final instant = DateTime.utc(2026, 3, 8, 4, 59).millisecondsSinceEpoch;
    expect(dateInZone(instant, zone), '2026-03-07');
    expect(dateInZone(instant + 3 * 3600 * 1000, zone), '2026-03-08');

    final days = calendarDays('2026-03-08');
    expect(days.length, 42);
    expect(days[0], '2026-02-23');
    expect(() => parseDate('2026-02-30'), throwsA(isA<FocusFlowException>()));
    expect(() => parseDate('2026-2-03'), throwsA(isA<FocusFlowException>()));

    final json = Settings.defaults.toJson();
    expect(json['focusMinutes'], 25);
    expect(json['theme'], 'system');
    expect(Settings.fromJson(json), Settings.defaults);

    final h = Harness();
    await h.init();
    final wire = await h.read();
    expect(wire.todayData.record.totalFocusSeconds, isA<int>());
    expect(wire.dataPath, isA<String>());
    expect(wire.pulse.session, isNull);
  });
}

// ------------------------------------------------------------ 备份测试辅助

Future<Map<String, dynamic>> _fixture(Harness h, String day) async {
  final dir = Directory.systemTemp.createTempSync('focusflow-fixture-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final file = File(p.join(dir.path, 'fixture.sqlite3'));
  final db = await AppDatabase.open(file);
  await db.customStatement(
    "INSERT INTO tasks (id,title,description,scheduled_date,status,pomodoro_enabled,"
    'planned_pomodoros,completed_pomodoros,sort_order,created_at,updated_at) '
    'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
    [
      '81cf9968-d779-4914-923e-1c6f8d26d372',
      '恢复后任务',
      '',
      day,
      'todo',
      1,
      1,
      0,
      0,
      h.now,
      h.now,
    ],
  );
  final result = await backupSnapshot(db);
  await db.close();
  return result;
}

Map<String, dynamic> deepCopy(Map<String, dynamic> source) =>
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
