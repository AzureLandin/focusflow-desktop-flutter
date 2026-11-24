/// 日历页：42 格、月份切换、选中日详情、历史只读。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:focusflow/shared/dates.dart';

import 'app_test_helpers.dart';
import 'test_desktop_api.dart';

void main() {
  testWidgets('月历渲染 42 格并可切换月份', (tester) async {
    final api = await TestDesktopApi.create();
    await pumpApp(tester, api: api);

    await tester.tap(find.byKey(const Key('nav-calendar')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('calendar-page')), findsOneWidget);
    final cells = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey &&
          (widget.key as ValueKey).value.toString().startsWith('day-cell-'),
    );
    expect(cells, findsNWidgets(42));
    expect(find.text('2026年11月'), findsOneWidget);

    await tester.tap(find.byKey(const Key('prev-month')));
    await tester.pump();
    await tester.pump();
    expect(find.text('2026年10月'), findsOneWidget);

    await tester.tap(find.byKey(const Key('next-month')));
    await tester.pump();
    await tester.pump();
    expect(find.text('2026年11月'), findsOneWidget);
  });

  testWidgets('选中日期显示当天详情，历史日期只读', (tester) async {
    final api = await TestDesktopApi.create();
    await api.seedTask('未来任务', scheduledDate: '2026-11-24');
    await api.seedTask('历史任务', scheduledDate: '2026-11-22');
    await pumpApp(tester, api: api);

    await tester.tap(find.byKey(const Key('nav-calendar')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('day-cell-2026-11-24')));
    await tester.pump();
    await tester.pump();

    expect(find.text('未来计划'), findsOneWidget);
    expect(find.text('未来任务'), findsOneWidget);
    expect(find.byKey(const Key('add-for-day')), findsOneWidget);

    await tester.tap(find.byKey(const Key('day-cell-2026-11-22')));
    await tester.pump();
    await tester.pump();
    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('历史任务'), findsOneWidget);
    expect(find.byKey(const Key('add-for-day')), findsNothing);
  });

  testWidgets('回到今天按钮恢复当天', (tester) async {
    final api = await TestDesktopApi.create();
    await pumpApp(tester, api: api);
    await tester.tap(find.byKey(const Key('nav-calendar')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('day-cell-2026-11-20')));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('回到今天'));
    await tester.pump();
    await tester.pump();
    expect(find.text('今天'), findsWidgets);
    expect(calendarDays(firstOfMonth('2026-11-20')), hasLength(42));
  });
}
