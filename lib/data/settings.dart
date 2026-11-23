import 'dart:convert';

import 'package:drift/drift.dart';

import 'db/database.dart';

/// src/shared/model.ts:20-30 的 theme 枚举，落库为小写字符串。
enum AppTheme { light, dark, system }

extension AppThemeKey on AppTheme {
  String get key => switch (this) {
        AppTheme.light => 'light',
        AppTheme.dark => 'dark',
        AppTheme.system => 'system',
      };

  static AppTheme fromKey(String key) => switch (key) {
        'light' => AppTheme.light,
        'dark' => AppTheme.dark,
        'system' => AppTheme.system,
        _ => throw ArgumentError('输入格式或数值超出允许范围，请检查后重试。'),
      };
}

/// 与 src-tauri/src/model.rs 的 Settings 一一对应，JSON 键为 camelCase。
class Settings {
  const Settings({
    required this.focusMinutes,
    required this.shortMinutes,
    required this.longMinutes,
    required this.longEvery,
    required this.sound,
    required this.notifications,
    required this.finalLongBreak,
    required this.theme,
  });

  static const Settings defaults = Settings(
    focusMinutes: 25,
    shortMinutes: 5,
    longMinutes: 15,
    longEvery: 4,
    sound: true,
    notifications: true,
    finalLongBreak: false,
    theme: AppTheme.system,
  );

  final int focusMinutes;
  final int shortMinutes;
  final int longMinutes;
  final int longEvery;
  final bool sound;
  final bool notifications;
  final bool finalLongBreak;
  final AppTheme theme;

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
        focusMinutes: (json['focusMinutes'] as num?)?.toInt() ??
            defaults.focusMinutes,
        shortMinutes: (json['shortMinutes'] as num?)?.toInt() ??
            defaults.shortMinutes,
        longMinutes:
            (json['longMinutes'] as num?)?.toInt() ?? defaults.longMinutes,
        longEvery: (json['longEvery'] as num?)?.toInt() ?? defaults.longEvery,
        sound: (json['sound'] as bool?) ?? defaults.sound,
        notifications: (json['notifications'] as bool?) ?? defaults.notifications,
        finalLongBreak:
            (json['finalLongBreak'] as bool?) ?? defaults.finalLongBreak,
        theme: AppThemeKey.fromKey((json['theme'] as String?) ?? 'system'),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'focusMinutes': focusMinutes,
        'shortMinutes': shortMinutes,
        'longMinutes': longMinutes,
        'longEvery': longEvery,
        'sound': sound,
        'notifications': notifications,
        'finalLongBreak': finalLongBreak,
        'theme': theme.key,
      };

  Settings copyWith({
    int? focusMinutes,
    int? shortMinutes,
    int? longMinutes,
    int? longEvery,
    bool? sound,
    bool? notifications,
    bool? finalLongBreak,
    AppTheme? theme,
  }) =>
      Settings(
        focusMinutes: focusMinutes ?? this.focusMinutes,
        shortMinutes: shortMinutes ?? this.shortMinutes,
        longMinutes: longMinutes ?? this.longMinutes,
        longEvery: longEvery ?? this.longEvery,
        sound: sound ?? this.sound,
        notifications: notifications ?? this.notifications,
        finalLongBreak: finalLongBreak ?? this.finalLongBreak,
        theme: theme ?? this.theme,
      );

  /// 范围对齐 src-tauri/src/model.rs:108-117 与 model.ts:20-25。
  void validate() {
    if (!(focusMinutes >= 1 && focusMinutes <= 120) ||
        !(shortMinutes >= 1 && shortMinutes <= 60) ||
        !(longMinutes >= 15 && longMinutes <= 30) ||
        !(longEvery >= 1 && longEvery <= 12)) {
      throw ArgumentError('输入格式或数值超出允许范围，请检查后重试。');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.focusMinutes == focusMinutes &&
      other.shortMinutes == shortMinutes &&
      other.longMinutes == longMinutes &&
      other.longEvery == longEvery &&
      other.sound == sound &&
      other.notifications == notifications &&
      other.finalLongBreak == finalLongBreak &&
      other.theme == theme;

  @override
  int get hashCode => Object.hash(
        focusMinutes,
        shortMinutes,
        longMinutes,
        longEvery,
        sound,
        notifications,
        finalLongBreak,
        theme,
      );

  @override
  String toString() => 'Settings(${jsonEncode(toJson())})';
}

const String preferencesKey = 'preferences';

/// 读取 preferences；无记录时返回 [Settings.defaults]。
Future<Settings> readSettings(AppDatabase db) async {
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
Future<void> writeSettings(AppDatabase db, Settings settings) async {
  settings.validate();
  await db.customStatement(
    'INSERT INTO app_settings (key, value) VALUES (?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [preferencesKey, jsonEncode(settings.toJson())],
  );
}
