import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusflow/main.dart';
import 'package:focusflow/ui/theme.dart';

void main() {
  testWidgets('应用骨架启动并显示品牌名', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FocusFlowApp()));
    expect(find.text('FocusFlow'), findsOneWidget);
  });

  test('浅色 / 深色主题令牌来自 styles.css', () {
    final light = buildTheme(Brightness.light);
    final dark = buildTheme(Brightness.dark);
    expect(light.colorScheme.primary, const Color(0xFF315F4B));
    expect(dark.colorScheme.primary, const Color(0xFF9BCCAD));
    expect(light.scaffoldBackgroundColor, const Color(0xFFF8F7F2));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF212723));
  });
}
