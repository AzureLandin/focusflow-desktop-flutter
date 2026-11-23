import 'dart:convert';

import 'package:focusflow/data/db/database.dart';
import 'package:focusflow/data/settings.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Settings', () {
    test('默认值对齐 src/shared/model.ts', () {
      final s = Settings.defaults;
      expect(s.focusMinutes, 25);
      expect(s.shortMinutes, 5);
      expect(s.longMinutes, 15);
      expect(s.longEvery, 4);
      expect(s.sound, isTrue);
      expect(s.notifications, isTrue);
      expect(s.finalLongBreak, isFalse);
      expect(s.theme, AppTheme.system);
      expect(s.toJson(), {
        'focusMinutes': 25,
        'shortMinutes': 5,
        'longMinutes': 15,
        'longEvery': 4,
        'sound': true,
        'notifications': true,
        'finalLongBreak': false,
        'theme': 'system',
      });
    });

    test('校验范围 1-120 / 1-60 / 15-30 / 1-12', () {
      Settings.defaults.validate();
      for (final invalid in [
        Settings.defaults.copyWith(focusMinutes: 0),
        Settings.defaults.copyWith(focusMinutes: 121),
        Settings.defaults.copyWith(shortMinutes: 0),
        Settings.defaults.copyWith(shortMinutes: 61),
        Settings.defaults.copyWith(longMinutes: 14),
        Settings.defaults.copyWith(longMinutes: 31),
        Settings.defaults.copyWith(longEvery: 0),
        Settings.defaults.copyWith(longEvery: 13),
      ]) {
        expect(invalid.validate, throwsArgumentError);
      }
      Settings.defaults.copyWith(focusMinutes: 1, longEvery: 12).validate();
      expect(AppThemeKey.fromKey('light'), AppTheme.light);
      expect(AppThemeKey.fromKey('dark'), AppTheme.dark);
      expect(AppThemeKey.fromKey('system'), AppTheme.system);
      expect(() => AppThemeKey.fromKey('auto'), throwsArgumentError);
    });

    test('JSON 往返保留全部字段', () {
      final original = Settings.defaults.copyWith(
        focusMinutes: 50,
        sound: false,
        theme: AppTheme.dark,
      );
      expect(Settings.fromJson(original.toJson()), original);
      expect(
        Settings.fromJson(jsonDecode('{"focusMinutes":45}')).focusMinutes,
        45,
      );
    });

    test('空库读默认值，写入后可读出', () async {
      final dir = tempDataDir();
      final db = await AppDatabase.open(dbFileIn(dir));
      addTearDown(db.close);

      expect(await readSettings(db), Settings.defaults);

      final changed = Settings.defaults.copyWith(
        focusMinutes: 40,
        shortMinutes: 8,
        longMinutes: 25,
        longEvery: 6,
        sound: false,
        notifications: false,
        finalLongBreak: true,
        theme: AppTheme.light,
      );
      await writeSettings(db, changed);
      expect(await readSettings(db), changed);

      // 再写一次覆盖同一行，app_settings 里只有一条 preferences。
      await writeSettings(db, changed.copyWith(focusMinutes: 41));
      final rows = await db.customSelect(
        "SELECT COUNT(*) AS n FROM app_settings WHERE key = 'preferences'",
      ).get();
      expect(rows.single.read<int>('n'), 1);
      expect((await readSettings(db)).focusMinutes, 41);
    });
  });
}
