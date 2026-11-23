import 'dart:convert';

import 'package:drift/drift.dart';

import '../shared/model.dart';

export '../shared/model.dart' show AppTheme, AppThemeKey, Settings;

const String preferencesKey = 'preferences';

/// 读取 preferences；无记录时返回 [Settings.defaults]。
Future<Settings> readSettings(DatabaseConnectionUser db) async {
  final rows = await db.customSelect(
    'SELECT value FROM app_settings WHERE key = ?',
    variables: [Variable.withString(preferencesKey)],
  ).get();
  if (rows.isEmpty) return Settings.defaults;
  final decoded = jsonDecode(rows.single.read<String>('value'));
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('设置数据格式无效。');
  }
  final settings = Settings.fromJson(decoded);
  settings.validate();
  return settings;
}

/// 写入 preferences（UPSERT，与 repository.rs:183 同语义）。
Future<void> writeSettings(DatabaseConnectionUser db, Settings settings) async {
  settings.validate();
  await db.customStatement(
    'INSERT INTO app_settings (key, value) VALUES (?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [preferencesKey, jsonEncode(settings.toJson())],
  );
}
