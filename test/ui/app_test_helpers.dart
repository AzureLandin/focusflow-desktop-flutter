/// widget 测试公共装配：注入内存 DesktopApi 替身。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:focusflow/main.dart';
import 'package:focusflow/state/providers.dart';

import 'test_desktop_api.dart';

Future<TestDesktopApi> pumpApp(
  WidgetTester tester, {
  TestDesktopApi? api,
}) async {
  final desktop = api ?? await TestDesktopApi.create();
  tester.view.physicalSize = const Size(1240, 840);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        desktopApiProvider.overrideWith((ref) async => desktop),
      ],
      child: const FocusFlowApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  return desktop;
}
