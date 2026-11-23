import 'dart:io';

import 'package:focusflow/data/db/migrations.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// 在临时目录里创建一个全新数据库文件（不碰真实数据目录）。
Directory tempDataDir() {
  final dir = Directory.systemTemp.createTempSync('focusflow-test-');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

File dbFileIn(Directory dir) => File(p.join(dir.path, 'focusflow.sqlite3'));

/// 用 001_init.sql 原文手工建一个“模拟老库”，带一行任务与 preferences。
void createLegacyDb(File file) {
  final db = sqlite3.open(file.path);
  try {
    for (final statement in migrationStatements) {
      db.execute(statement);
    }
    db.execute('PRAGMA user_version = 1');
    db.execute(
      "INSERT INTO tasks (id, title, description, scheduled_date, status, "
      'pomodoro_enabled, planned_pomodoros, completed_pomodoros, sort_order, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        '旧任务',
        '来自 0.11',
        '2026-11-23',
        'todo',
        1,
        4,
        1,
        0,
        1763900000000,
        1763900000000,
      ],
    );
    db.execute(
      "INSERT INTO app_settings (key, value) VALUES ('preferences', ?)",
      [
        '{"focusMinutes":30,"shortMinutes":6,"longMinutes":20,"longEvery":3,'
            '"sound":false,"notifications":true,"finalLongBreak":true,'
            '"theme":"dark"}'
      ],
    );
  } finally {
    db.close();
  }
}

List<File> flutterSnapshots(Directory dir) => dir
    .listSync()
    .whereType<File>()
    .where((f) => p.basename(f.path).startsWith('before-flutter-'))
    .toList();
