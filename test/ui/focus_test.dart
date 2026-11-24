/// 专注页：整屏切换、Ticker 倒计时、阶段文案、打断、总结 resolve。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:focusflow/shared/model.dart';

import 'app_test_helpers.dart';
import 'test_desktop_api.dart';

void main() {
  testWidgets('无会话时不显示专注页，有活动会话时整屏切换', (tester) async {
    final api = await TestDesktopApi.create();
    await pumpApp(tester, api: api);
    expect(find.byKey(const Key('focus-page')), findsNothing);
    expect(find.byKey(const Key('today-page')), findsOneWidget);

    await api.seedSession(status: 'focus_running', planned: 4, title: '深度工作');
    // 种入后靠 750ms 心跳发现会话：推进假时钟让 Timer 触发。
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();

    expect(find.byKey(const Key('focus-page')), findsOneWidget);
    expect(find.byKey(const Key('today-page')), findsNothing);
    expect(find.byKey(const Key('focus-title')), findsOneWidget);
    expect(find.text('深度工作'), findsOneWidget);
  });

  testWidgets('倒计时随 Ticker 推进且阶段文案正确', (tester) async {
    final api = await TestDesktopApi.create();
    await api.seedSession(
      status: 'focus_running',
      planned: 4,
      title: '计时任务',
      focusMinutes: 25,
    );
    await pumpApp(tester, api: api);

    expect(find.text('专注'), findsOneWidget);
    expect(find.text('专注计时中'), findsOneWidget);
    expect(find.text('下一阶段：短休息'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('24:57'), findsOneWidget, reason: 'Ticker 应按本地插值推进');
  });

  testWidgets('恢复横幅在首次读到活动会话时出现', (tester) async {
    final api = await TestDesktopApi.create();
    await api.seedSession(status: 'focus_running', title: '恢复任务');
    await pumpApp(tester, api: api);

    expect(find.byKey(const Key('recovered-banner')), findsOneWidget);
    expect(find.text('已恢复上次的专注会话'), findsOneWidget);
  });

  testWidgets('打断弹窗 → 快速任务加入提示', (tester) async {
    final api = await TestDesktopApi.create();
    await api.seedSession(status: 'focus_running', title: '自由专注', planned: 1);
    await pumpApp(tester, api: api);

    await tester.tap(find.byKey(const Key('interrupt-button')));
    await tester.pump();
    expect(find.byKey(const Key('interrupt-modal')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('interrupt-reason')), '紧急电话');
    await tester.pump();
    await tester.tap(find.byKey(const Key('interrupt-confirm')));
    await tester.pump();
    await tester.pump();

    expect(api.commands.whereType<Interrupt>(), hasLength(1));
    expect(
      api.commands.whereType<Interrupt>().first.reason,
      '紧急电话',
    );
    expect(find.byKey(const Key('interrupted-quick-overlay')), findsOneWidget);

    await tester.tap(find.byKey(const Key('interrupted-quick-confirm')));
    await tester.pump();
    await tester.pump();
    expect(api.commands.whereType<SaveInterruptedQuick>(), hasLength(1));
  });

  testWidgets('总结页可选择保存为任务并 resolve', (tester) async {
    final api = await TestDesktopApi.create();
    await api.seedSession(
      status: 'session_completed',
      title: '总结任务',
      planned: 1,
      completed: 1,
    );
    await pumpApp(tester, api: api);

    expect(find.byKey(const Key('focus-page')), findsOneWidget);
    expect(find.text('专注总结'), findsOneWidget);
    expect(find.byKey(const Key('summary-back')), findsOneWidget);

    // 勾选“加入今日待办”后出现完成按钮。
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.byKey(const Key('summary-complete')), findsOneWidget);

    await tester.tap(find.byKey(const Key('summary-complete')));
    await tester.pump();
    await tester.pump();
    final resolves = api.commands.whereType<Resolve>().toList();
    expect(resolves, hasLength(1));
    expect(resolves.first.completed, isTrue);
    expect(resolves.first.saveQuick, isTrue);
  });
}
