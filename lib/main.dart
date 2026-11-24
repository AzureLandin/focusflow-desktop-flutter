import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'data/db/data_dir.dart';
import 'platform/platform_hooks.dart';
import 'platform/single_instance.dart';
import 'state/providers.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

/// 引擎发起退出时释放单实例锁（窗口直接关闭等路径由启动时的 pid 检测兜底）。
// ignore: unused_element
AppLifecycleListener? _exitHook;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 对齐 tauri-plugin-single-instance：已有实例时直接退出。
  final lockFile = File(p.join(resolveDataDir().path, 'focusflow.lock'));
  if (!SingleInstanceLock.acquire(lockFile)) {
    // ignore: avoid_print
    print('FocusFlow 已在运行，退出当前实例。');
    return;
  }
  _exitHook = AppLifecycleListener(
    onExitRequested: () async {
      SingleInstanceLock.release();
      return AppExitResponse.exit;
    },
  );

  // 提前预热插件，失败由各 hook 内部静默降级。
  await ChimePlayer.prime();
  await SystemNotifier.prime();

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
