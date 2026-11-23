import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'migrations.dart';

part 'database.g.dart';

/// drift 数据库。表结构完全由 [migrationSql] 原文创建，不用 drift 注解。
@DriftDatabase()
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.e, {this.snapshotPath});

  /// 本次打开为老库生成的快照路径；新建库时为 null。
  final String? snapshotPath;

  /// 打开数据库。老库在交给 drift 之前先做 before-flutter 快照 + quick_check。
  static Future<AppDatabase> open(File file) async {
    final snapshotPath = await prepareExistingDatabase(file);
    final executor = NativeDatabase(file, setup: applyPragmas);
    return AppDatabase._(executor, snapshotPath: snapshotPath);
  }

  @override
  int get schemaVersion => kSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (_) async {
          for (final statement in migrationStatements) {
            await customStatement(statement);
          }
        },
        beforeOpen: (details) async {
          final rows = await customSelect('PRAGMA journal_mode').get();
          if (rows.isEmpty || rows.first.read<String>('journal_mode') != 'wal') {
            throw StateError('无法启用数据库日志，请检查数据目录。');
          }
        },
      );
}

/// PRAGMA 对齐 src-tauri/src/db/mod.rs:16-30。
/// 在 NativeDatabase 的 setup 中执行，保证建表前连接已处于目标模式。
void applyPragmas(Database db) {
  db.execute('PRAGMA busy_timeout = 3000');
  db.execute('PRAGMA locking_mode = EXCLUSIVE');
  db.execute('PRAGMA foreign_keys = ON');
  db.execute('PRAGMA synchronous = FULL');
  // 与 Rust 版一致：用一次独占事务确认拿得到写锁。
  db.execute('BEGIN EXCLUSIVE');
  db.execute('COMMIT');
  final mode = db.select('PRAGMA journal_mode=WAL').first.columnAt(0);
  if (mode != 'wal') {
    throw StateError('无法启用数据库日志，请检查数据目录。');
  }
}

/// 首次用 Flutter 打开一个已存在的库时，先 VACUUM INTO 生成快照并验证，
/// 对齐 src-tauri/src/db/mod.rs 的 before-tauri 机制。
/// 返回快照路径；文件是新建库或快照已做过时返回 null。
Future<String?> prepareExistingDatabase(
  File file, {
  String markerName = 'flutter-migration-v1.done',
}) async {
  if (!file.existsSync()) return null;
  final parent = file.parent;
  final marker = File(p.join(parent.path, markerName));

  final db = sqlite3.open(file.path);
  try {
    // 与 db/mod.rs 一致：版本/完整性检查必须先于标记文件判断，
    // 否则同目录下的新版库或坏库会被错误放行。
    final check = db.select('PRAGMA quick_check').first.columnAt(0);
    if (check != 'ok') {
      throw StateError('旧数据库完整性检查失败，请保留原数据库文件。');
    }

    final version = (db.select('PRAGMA user_version').first.columnAt(0) as num)
        .toInt();
    if (version > 1) {
      throw StateError('数据库来自较新版本，请使用新版 FocusFlow 打开。');
    }
    if (version < 0) {
      throw StateError('无法识别数据库版本。');
    }
    if (marker.existsSync()) return null;

    final name =
        'before-flutter-${DateTime.now().millisecondsSinceEpoch}-${const Uuid().v4()}.sqlite3';
    final snapshotPath = p.join(parent.path, name);
    // 路径中的单引号按 SQL 规则转义。
    final escaped = snapshotPath.replaceAll("'", "''");
    db.execute("VACUUM INTO '$escaped'");

    final snapshot = sqlite3.open(snapshotPath);
    try {
      final snapshotCheck =
          snapshot.select('PRAGMA quick_check').first.columnAt(0);
      final mode = snapshot.select('PRAGMA journal_mode=DELETE').first.columnAt(0);
      if (snapshotCheck != 'ok' || mode != 'delete') {
        throw StateError('无法验证旧数据库的备份。请保留原数据库。');
      }
    } finally {
      snapshot.close();
    }

    await marker.writeAsString('FocusFlow Flutter schema 1\n');
    return snapshotPath;
  } finally {
    db.close();
  }
}
