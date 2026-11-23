import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'state/providers.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureWindow();
  runApp(const ProviderScope(child: FocusFlowApp()));
}

/// 窗口默认值对齐 src-tauri/tauri.conf.json:13-16。
Future<void> configureWindow() async {
  final window = WindowManager.instance.getCurrent();
  if (window == null) return;
  window
    ..title = 'FocusFlow'
    ..minimumSize = const Size(800, 590).toNative()
    ..setSize(const Size(1240, 840).toNative(), false)
    ..center()
    ..show();
}

/// 应用根组件。窗口初始化成功后才运行，因此测试可独立构建它。
class FocusFlowApp extends ConsumerWidget {
  const FocusFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'FocusFlow',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      home: const AppShell(),
    );
  }
}
