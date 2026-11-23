import 'package:focusflow/data/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  test('首次打开已存在库生成 before-flutter 快照，再次打开不重复生成', () async {
    final dir = tempDataDir();
    final file = dbFileIn(dir);
    createLegacyDb(file);
    expect(flutterSnapshots(dir), isEmpty);

    final db = await AppDatabase.open(file);
    addTearDown(db.close);

    final snapshots = flutterSnapshots(dir);
    expect(snapshots, hasLength(1));
    expect(p.basename(snapshots.single.path), startsWith('before-flutter-'));
    expect(p.extension(snapshots.single.path), '.sqlite3');
    expect(db.snapshotPath, snapshots.single.path);

    // 快照本身可独立打开、数据完整。
    final snapshot = sqlite3.open(snapshots.single.path);
    try {
      final rows = snapshot.select('SELECT title FROM tasks');
      expect(rows, hasLength(1));
      expect(rows.first.columnAt(0), '旧任务');
      final check = snapshot.select('PRAGMA quick_check').first.columnAt(0);
      expect(check, 'ok');
    } finally {
      snapshot.close();
    }

    await db.close();
    final db2 = await AppDatabase.open(file);
    addTearDown(db2.close);
    expect(flutterSnapshots(dir), hasLength(1));
    expect(db2.snapshotPath, isNull);
  });

  test('新建库不生成快照', () async {
    final dir = tempDataDir();
    final db = await AppDatabase.open(dbFileIn(dir));
    addTearDown(db.close);
    expect(flutterSnapshots(dir), isEmpty);
    expect(db.snapshotPath, isNull);
  });
}
