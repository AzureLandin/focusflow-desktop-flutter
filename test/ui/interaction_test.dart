/// 键盘细节与错误路径：Ctrl/Cmd+Enter 保存想法、Esc 关弹窗、命令失败 notice。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:focusflow/shared/model.dart';

import 'app_test_helpers.dart';
import 'test_desktop_api.dart';

void main() {
  testWidgets('Ctrl+Enter 保存想法（macOS Cmd 等价）', (tester) async {
    final api = await TestDesktopApi.create();
    await pumpApp(tester, api: api);

    await tester.tap(find.byKey(const Key('thought-entry')));
    await tester.pump();
    expect(find.byKey(const Key('notes-overlay')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('thought-field')), '  刚想到的点子  ');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    final thoughts = api.commands.whereType<SaveThought>().toList();
    expect(thoughts, hasLength(1));
    expect(thoughts.first.content, '  刚想到的点子  ');
  });

  testWidgets('Esc 关闭弹窗', (tester) async {
    final api = await TestDesktopApi.create();
    await pumpApp(tester, api: api);
    await tester.tap(find.byKey(const Key('thought-entry')));
    await tester.pump();
    expect(find.byKey(const Key('notes-overlay')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('notes-overlay')), findsNothing);
  });

  testWidgets('命令失败显示错误 notice', (tester) async {
    final api = await TestDesktopApi.create();
    api.failOn.add(SaveTask);
    await pumpApp(tester, api: api);

    await tester.enterText(find.byKey(const Key('quick-add-field')), '失败任务');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('notice-error')), findsOneWidget);
    expect(find.text('FF:模拟命令失败'), findsOneWidget);
  });

  testWidgets('成功后显示反馈 toast 且 3 秒后自动消失', (tester) async {
    final api = await TestDesktopApi.create();
    await pumpApp(tester, api: api);

    await tester.enterText(find.byKey(const Key('quick-add-field')), '成功任务');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byKey(const Key('notice')), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const Key('notice')), findsNothing);
  });
}
