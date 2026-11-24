/// 今日页：任务渲染、快速添加 Enter、勾选、上下移、删除确认、详情/开始表单。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:focusflow/shared/model.dart';
import 'package:material_ui/material_ui.dart';

import 'app_test_helpers.dart';
import 'test_desktop_api.dart';

void main() {
  testWidgets('今日页渲染任务与完成进度', (tester) async {
    final api = await TestDesktopApi.create();
    await api.seedTask('写方案', sortOrder: 0);
    await api.seedTask('读文档', sortOrder: 1, status: 'completed');

    await pumpApp(tester, api: api);

    expect(find.byKey(const Key('today-page')), findsOneWidget);
    expect(find.text('写方案'), findsOneWidget);
    expect(find.text('读文档'), findsOneWidget);
    expect(find.byKey(const Key('today-progress')), findsOneWidget);
    expect(find.byKey(const Key('focus-card')), findsOneWidget);
    expect(find.byKey(const Key('quick-focus')), findsOneWidget);
  });

  testWidgets('快速添加 Enter 保存任务', (tester) async {
    final api = await TestDesktopApi.create();
    await pumpApp(tester, api: api);

    await tester.enterText(find.byKey(const Key('quick-add-field')), '新任务');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    expect(
      api.commands.whereType<SaveTask>().map((c) => c.task.title),
      contains('新任务'),
    );
    expect(find.text('新任务'), findsWidgets);
    expect(
      find.text('任务已保存'),
      findsOneWidget,
      reason: '成功提示应显示 feedback 文案',
    );
  });

  testWidgets('勾选任务更新完成状态', (tester) async {
    final api = await TestDesktopApi.create();
    final id = await api.seedTask('待办A');
    // bySemanticsLabel 需要 SemanticsHandle（须在测试体内显式释放）。
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, api: api);

    await tester.tap(find.byKey(Key('task-check-$id')));
    await tester.pump();
    await tester.pump();

    expect(api.commands.whereType<ToggleTask>().map((c) => c.id), [id]);
    expect(find.bySemanticsLabel('撤销完成：待办A'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('上下移任务改变顺序', (tester) async {
    final api = await TestDesktopApi.create();
    final first = await api.seedTask('第一项', sortOrder: 0);
    await api.seedTask('第二项', sortOrder: 1);
    await pumpApp(tester, api: api);

    await tester.tap(find.byKey(Key('move-down-$first')));
    await tester.pump();
    await tester.pump();

    final moves = api.commands.whereType<MoveTask>().toList();
    expect(moves, hasLength(1));
    expect(moves.first.direction, 1);
  });

  testWidgets('删除任务需确认弹窗', (tester) async {
    final api = await TestDesktopApi.create();
    final id = await api.seedTask('可删除任务');
    await pumpApp(tester, api: api);

    await tester.tap(find.byKey(Key('delete-$id')));
    await tester.pump();
    expect(find.byKey(const Key('remove-overlay')), findsOneWidget);
    expect(find.text('删除「可删除任务」？已记录的番茄专注历史会保留。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('remove-confirm')));
    await tester.pump();
    await tester.pump();
    expect(api.commands.whereType<DeleteTask>().map((c) => c.id), [id]);
    expect(find.byKey(const Key('remove-overlay')), findsNothing);
  });

  testWidgets('详细添加与开始专注表单均可打开', (tester) async {
    final api = await TestDesktopApi.create();
    await pumpApp(tester, api: api);

    await tester.tap(find.text('详细添加'));
    await tester.pump();
    expect(find.byKey(const Key('task-overlay')), findsOneWidget);
    // React 版关闭按钮是 aria-label+title=“关闭”；Flutter 侧 Tooltip 承担 title 角色。
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('quick-focus')));
    await tester.pump();
    expect(find.byKey(const Key('focus-overlay')), findsOneWidget);
  });
}
