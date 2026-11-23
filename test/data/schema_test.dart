import 'package:focusflow/data/db/database.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('新建库 schema', () {
    test('7 张 STRICT 表与全部索引都由 001_init.sql 原文创建', () async {
      final dir = tempDataDir();
      final db = await AppDatabase.open(dbFileIn(dir));
      addTearDown(db.close);

      final rows = await db.customSelect(
        'SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT NULL',
      ).get();
      final byName = <String, String>{
        for (final row in rows)
          row.read<String>('name'): row.read<String>('sql'),
      };

      for (final table in const [
        'tasks',
        'daily_records',
        'pomodoro_sessions',
        'pomodoro_cycles',
        'pomodoro_interruptions',
        'thought_notes',
        'app_settings',
      ]) {
        expect(byName, containsPair(table, isA<String>()));
        expect(byName[table], contains('STRICT'), reason: '$table 必须是 STRICT 表');
      }

      expect(byName['tasks'], contains('CHECK(length(title) BETWEEN 1 AND 200)'));
      expect(byName['tasks_by_date'], contains('WHERE deleted_at IS NULL'));
      expect(
        byName['one_active_session'],
        contains("WHERE status NOT IN ('interrupted','completed')"),
      );
      expect(byName['cycles_by_date'], contains('(local_date, status)'));
      expect(byName['thoughts_by_date'], contains('(local_date, created_at)'));
      expect(byName['thoughts_by_session'], contains('(session_id)'));
      expect(byName['app_settings'], contains('key TEXT PRIMARY KEY NOT NULL'));
      expect(
        byName['pomodoro_interruptions'],
        contains('FOREIGN KEY (cycle_id, session_id)'),
      );
    });

    test('列集合与 CHECK 约束真正生效', () async {
      final dir = tempDataDir();
      final db = await AppDatabase.open(dbFileIn(dir));
      addTearDown(db.close);

      final columns = await db.customSelect('PRAGMA table_info(tasks)').get();
      expect(
        columns.map((row) => row.read<String>('name')).toList(),
        containsAll(<String>[
          'id',
          'title',
          'description',
          'scheduled_date',
          'status',
          'pomodoro_enabled',
          'planned_pomodoros',
          'completed_pomodoros',
          'sort_order',
          'created_at',
          'updated_at',
          'completed_at',
          'deleted_at',
        ]),
      );

      // STRICT + CHECK：空标题被拒绝。
      expect(
        () => db.customStatement(
          "INSERT INTO tasks (id, title, description, scheduled_date, status, "
          'pomodoro_enabled, planned_pomodoros, sort_order, created_at, updated_at) '
          "VALUES ('x', '', '', '2026-11-23', 'todo', 1, 1, 0, 0, 0)",
        ),
        throwsA(isA<Exception>()),
      );
      // CHECK：计划番茄数上限 12。
      expect(
        () => db.customStatement(
          "INSERT INTO tasks (id, title, description, scheduled_date, status, "
          'pomodoro_enabled, planned_pomodoros, sort_order, created_at, updated_at) '
          "VALUES ('y', 'ok', '', '2026-11-23', 'todo', 1, 13, 0, 0, 0)",
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('使用支持 STRICT 表的 SQLite（>= 3.37）', () async {
      final dir = tempDataDir();
      final db = await AppDatabase.open(dbFileIn(dir));
      addTearDown(db.close);
      final rows = await db.customSelect('SELECT sqlite_version() AS v').get();
      final parts = rows.single.read<String>('v').split('.').map(int.parse).toList();
      expect(parts[0] * 1000 + parts[1] * 10 + parts[2], greaterThanOrEqualTo(3037));
    });

    test('PRAGMA 与 user_version 对齐 Rust 版', () async {
      final dir = tempDataDir();
      final db = await AppDatabase.open(dbFileIn(dir));
      addTearDown(db.close);

      Future<String> pragma(String name) async {
        final rows = await db.customSelect('PRAGMA $name').get();
        return rows.first.read<String>(rows.first.data.keys.first);
      }

      expect(await pragma('journal_mode'), 'wal');
      expect(await pragma('locking_mode'), 'exclusive');
      expect(await pragma('foreign_keys'), '1');
      expect(await pragma('busy_timeout'), '3000');
      expect(await pragma('synchronous'), '2'); // FULL

      final version = await db.customSelect('PRAGMA user_version').get();
      expect(version.single.read<int>('user_version'), 1);
    });
  });
}
