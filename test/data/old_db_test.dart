import 'package:focusflow/data/db/database.dart';
import 'package:focusflow/data/settings.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  test('打开 001_init.sql 手工建好的模拟老库能读出任务与设置', () async {
    final dir = tempDataDir();
    final file = dbFileIn(dir);
    createLegacyDb(file);

    final db = await AppDatabase.open(file);
    addTearDown(db.close);

    final tasks = await db.customSelect('SELECT id, title FROM tasks').get();
    expect(tasks, hasLength(1));
    expect(tasks.single.read<String>('title'), '旧任务');

    final sessions =
        await db.customSelect('SELECT COUNT(*) AS n FROM pomodoro_sessions').get();
    expect(sessions.single.read<int>('n'), 0);

    final settings = await readSettings(db);
    expect(settings.focusMinutes, 30);
    expect(settings.shortMinutes, 6);
    expect(settings.longMinutes, 20);
    expect(settings.longEvery, 3);
    expect(settings.sound, isFalse);
    expect(settings.finalLongBreak, isTrue);
    expect(settings.theme, AppTheme.dark);

    // 老库打开不应触发建表，DDL 仍是原文。
    final schema = await db.customSelect(
      "SELECT sql FROM sqlite_master WHERE name = 'one_active_session'",
    ).get();
    expect(
      schema.single.read<String>('sql'),
      contains("WHERE status NOT IN ('interrupted','completed')"),
    );
  });
}
