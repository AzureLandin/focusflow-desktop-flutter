/// 设置页：表单编辑 → settings 命令、主题三态、备份按钮。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:focusflow/shared/model.dart';
import 'package:focusflow/ui/widgets.dart';

import 'app_test_helpers.dart';
import 'test_desktop_api.dart';

void main() {
  testWidgets('设置表单编辑后保存发出 settings 命令', (tester) async {
    final api = await TestDesktopApi.create();
    await pumpApp(tester, api: api);

    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('settings-page')), findsOneWidget);
    expect(find.byKey(const Key('backup-export')), findsOneWidget);
    expect(find.byKey(const Key('backup-import')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('setting-focusMinutes')), '40');
    await tester.pump();
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pump();
    await tester.pump();

    final commands = api.commands.whereType<SettingsCommand>().toList();
    expect(commands, hasLength(1));
    expect(commands.first.settings.focusMinutes, 40);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });

  testWidgets('主题三态切换即时生效并随设置保存', (tester) async {
    final api = await TestDesktopApi.create();
    await pumpApp(tester, api: api);
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    await tester.tap(find.byKey(const Key('setting-theme')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('深色').last);
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pump();
    await tester.pump();
    final settings = api.commands.whereType<SettingsCommand>().single.settings;
    expect(settings.theme, AppTheme.dark);
  });

  testWidgets('未修改时保存按钮禁用', (tester) async {
    final api = await TestDesktopApi.create();
    await pumpApp(tester, api: api);
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pump();
    await tester.pump();

    final button = tester.widget<FfButton>(
      find.byKey(const Key('settings-save')),
    );
    expect(button.onPressed, isNull);
  });
}
