/// focusflow-backup v1 的 Dart 对应实现（src-tauri/src/backup.rs）。
/// 步骤 3 的领域测试需要“备份回滚”断言，因此先落地完整语义，步骤 4 可继续打磨文件对话框接入。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:focusflow/domain/pomodoro.dart' as pomodoro;
import 'package:focusflow/shared/dates.dart';
import 'package:focusflow/shared/errors.dart';
import 'package:focusflow/shared/model.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'repository.dart';

const List<String> kBackupTables = <String>[
  'tasks',
  'daily_records',
  'pomodoro_sessions',
  'pomodoro_cycles',
  'pomodoro_interruptions',
  'thought_notes',
  'app_settings',
];

const int kMaxBackupBytes = 100 * 1024 * 1024;

Future<List<({String name, String type, bool required})>> _columns(
  DatabaseConnectionUser db,
  String table,
) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows
      .map(
        (row) => (
          name: row.read<String>('name'),
          type: row.read<String>('type'),
          required: row.read<int>('notnull') == 1,
        ),
      )
      .toList();
}

Future<Map<String, dynamic>> snapshot(DatabaseConnectionUser db) async {
  final data = <String, dynamic>{};
  for (final table in kBackupTables) {
    final columns = await _columns(db, table);
    if (columns.isEmpty) throw FocusFlowException(invalidBackup);
    final rows = await db.customSelect('SELECT * FROM $table').get();
    data[table] = rows
        .map((row) => <String, dynamic>{
              for (final column in columns) column.name: row.data[column.name],
            })
        .toList();
  }
  return <String, dynamic>{
    'format': 'focusflow-backup',
    'version': 1,
    'data': data,
  };
}

Future<String> exportBackup(DatabaseConnectionUser db) async =>
    const JsonEncoder.withIndent('  ').convert(await snapshot(db));

Map<String, dynamic> decodeBackup(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) throw FocusFlowException(invalidBackup);
    return decoded;
  } on FocusFlowException {
    rethrow;
  } on Object {
    throw FocusFlowException(invalidBackup);
  }
}

void _assertJsonFile(File file) {
  if (p.extension(file.path).toLowerCase() != '.json') {
    throw FocusFlowException('请选择扩展名为 .json 的备份文件。');
  }
}

Future<Map<String, dynamic>> readFile(File file) async {
  _assertJsonFile(file);
  final length = await file.length();
  if (length > kMaxBackupBytes) {
    throw FocusFlowException('备份文件超过 100 MB。');
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > kMaxBackupBytes) {
    throw FocusFlowException('备份文件超过 100 MB。');
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return decodeBackup(utf8.decode(bytes.sublist(3)));
  }
  return decodeBackup(utf8.decode(bytes));
}

Future<void> writeFile(
  File file,
  Map<String, dynamic> value, {
  bool replace = false,
}) async {
  _assertJsonFile(file);
  final parent = file.parent;
  if (!parent.existsSync()) {
    throw FocusFlowException('请选择有效的备份位置。');
  }
  final temp = File(p.join(parent.path, '.${p.basename(file.path)}.${const Uuid().v4()}.tmp'));
  await temp.writeAsString('${const JsonEncoder.withIndent('  ').convert(value)}\n');
  if (replace) {
    await temp.rename(file.path);
  } else {
    if (file.existsSync()) {
      await temp.delete();
      throw FocusFlowException('备份文件已存在。');
    }
    await temp.rename(file.path);
  }
}

Object? _cell(dynamic value, ({String name, String type, bool required}) column) {
  if (value == null && !column.required) return null;
  switch (column.type) {
    case 'TEXT':
      if (value is! String || value.contains(String.fromCharCode(0))) {
        throw FocusFlowException(invalidBackup);
      }
      return value;
    case 'INTEGER':
      if (value is! int || value.abs() > 9007199254740991) {
        throw FocusFlowException(invalidBackup);
      }
      return value;
    default:
      throw FocusFlowException(invalidBackup);
  }
}

List<Object?> _validateRow(
  String table,
  dynamic raw,
  List<({String name, String type, bool required})> columns,
) {
  if (raw is! Map<String, dynamic> || raw.length != columns.length) {
    throw FocusFlowException(invalidBackup);
  }
  for (final key in const ['date', 'scheduled_date', 'local_date']) {
    final value = raw[key];
    if (value != null) {
      if (value is! String || !isValidDateKey(value)) {
        throw FocusFlowException(invalidBackup);
      }
    }
  }
  for (final key in const ['id', 'task_id', 'session_id', 'cycle_id']) {
    final value = raw[key];
    if (value != null) {
      if (value is! String || value.length != 36 || !_uuidValid(value)) {
        throw FocusFlowException(invalidBackup);
      }
    }
  }
  for (final entry in const {
    'title': [1, 200],
    'task_title_snapshot': [1, 200],
    'description': [0, 2000],
    'reason': [1, 500],
    'content': [1, 2000],
  }.entries) {
    final value = raw[entry.key];
    if (value != null) {
      if (value is! String ||
          !validText(value.trim(), entry.value[0], entry.value[1])) {
        throw FocusFlowException(invalidBackup);
      }
    }
  }
  Object? preferences;
  final key = raw['key'];
  if (table == 'app_settings' && key == 'archive_origin') {
    final value = raw['value'];
    if (value is! String || !isValidDateKey(value)) {
      throw FocusFlowException(invalidBackup);
    }
  } else if (table == 'app_settings' && key == 'preferences') {
    preferences = raw['value'];
  } else if (table == 'pomodoro_sessions') {
    preferences = raw['rules'];
  }
  if (preferences != null) {
    if (preferences is! String) throw FocusFlowException(invalidBackup);
    try {
      final settings = Settings.fromJson(jsonDecode(preferences) as Map<String, dynamic>);
      settings.validate();
    } on Object {
      throw FocusFlowException(invalidBackup);
    }
  }
  return [
    for (final column in columns)
      _cell(raw[column.name], column),
  ];
}

bool _uuidValid(String value) {
  // 与 backup.rs 的 valid_id 等价：标准 36 字符 UUID。
  final pattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  return pattern.hasMatch(value);
}

Future<void> restore(Repository repo, Object backup, int now) async {
  final active = await pomodoro.activeSession(repo.db);
  if (active != null) {
    throw FocusFlowException('请在专注会话结束后管理备份。');
  }
  final parsed = backup is String ? decodeBackup(backup) : backup;
  if (parsed is! Map<String, dynamic> ||
      parsed['format'] != 'focusflow-backup' ||
      parsed['version'] != 1 ||
      parsed['data'] is! Map<String, dynamic>) {
    throw FocusFlowException(invalidBackup);
  }
  final data = parsed['data'] as Map<String, dynamic>;
  final entries = <({String table, List<({String name, String type, bool required})> columns, List<List<Object?>> rows})>[];
  for (final table in kBackupTables) {
    final columns = await _columns(repo.db, table);
    final rawRows = data[table];
    if (rawRows is! List) throw FocusFlowException(invalidBackup);
    entries.add(
      (
        table: table,
        columns: columns,
        rows: rawRows.map((row) => _validateRow(table, row, columns)).toList(),
      ),
    );
  }

  final parent = p.dirname(repo.dataPath);
  var rollbackPath = p.join(parent, 'before-restore-$now.json');
  if (File(rollbackPath).existsSync()) {
    rollbackPath = p.join(parent, 'before-restore-$now-${const Uuid().v4()}.json');
  }
  await writeFile(File(rollbackPath), await snapshot(repo.db));

  try {
    await repo.db.transaction(() async {
      for (final table in kBackupTables.reversed) {
        await repo.db.customStatement('DELETE FROM $table');
      }
      for (final entry in entries) {
        final names = entry.columns.map((c) => c.name).join(',');
        final markers = entry.columns.map((_) => '?').join(',');
        for (final row in entry.rows) {
          await repo.db.customStatement(
            'INSERT INTO ${entry.table} ($names) VALUES ($markers)',
            row,
          );
        }
      }
      final rows = await repo.db.customSelect(
        'SELECT EXISTS(SELECT 1 FROM pomodoro_sessions s WHERE '
        's.completed_pomodoros <> (SELECT COUNT(*) FROM pomodoro_cycles c '
        "WHERE c.session_id=s.id AND c.status='completed') OR "
        "(s.status='focus_running' AND EXISTS (SELECT 1 FROM pomodoro_cycles c "
        'WHERE c.session_id=s.id AND c.cycle_index=s.current_cycle))) AS bad',
      ).get();
      if (rows.single.read<int>('bad') == 1) {
        throw FocusFlowException(invalidBackup);
      }
    });
  } on Object {
    throw FocusFlowException(invalidBackup);
  }
  repo.lastDay = null;
}

// TS 版命名的薄封装，方便测试与步骤 4 的 UI 层直接调用。
Future<Map<String, dynamic>> backupSnapshot(DatabaseConnectionUser db) =>
    snapshot(db);

Future<Map<String, dynamic>> backupSnapshotOrThrow(DatabaseConnectionUser db) =>
    snapshot(db);

Future<Map<String, dynamic>> readBackupFile(File file) => readFile(file);

Future<void> writeBackupFile(File file, Map<String, dynamic> value) =>
    writeFile(file, value);

Future<void> restoreBackup(Repository repo, Object backup, int now) =>
    restore(repo, backup, now);

