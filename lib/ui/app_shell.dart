import 'package:material_ui/material_ui.dart';

/// 页面切换与 overlay 管理的占位骨架。第 5 步填充今日/专注/日历/设置/想法页。
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'FocusFlow',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
