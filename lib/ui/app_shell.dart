/// src/renderer/index.tsx 的 App 根组件：页面切换、整屏专注、overlay 弹窗栈、notice。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../shared/dates.dart';
import '../shared/model.dart';
import '../state/providers.dart';
import 'calendar_page.dart';
import 'focus_page.dart';
import 'settings_page.dart';
import 'thoughts.dart';
import 'tasks.dart';
import 'today_page.dart';
import 'widgets.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 对应 index.tsx:97-100 的 focus / visibilitychange 触发。
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(uiControllerProvider.notifier).tick());
    }
  }

  @override
  Widget build(BuildContext context) {
    // 启动心跳（750ms）。
    ref.watch(heartbeatProvider);
    final asyncState = ref.watch(uiControllerProvider);
    final controller = ref.read(uiControllerProvider.notifier);
    final state = asyncState.value;

    if (asyncState.isLoading && state == null) {
      return const _Startup(message: '正在读取本地数据…');
    }
    if (asyncState.hasError || state == null) {
      return _Startup(
        message: state?.notice?.message ?? '操作失败，请重试。',
        error: true,
        onRetry: () => controller.refresh(),
      );
    }
    final notice = state.notice;
    final toast = notice == null
        ? null
        : _Toast(
            key: ValueKey('toast-${notice.message}'),
            notice: notice,
            onClose: controller.clearNotice,
          );

    final session = state.workspace?.pulse.session;
    if (session != null) {
      return Stack(
        children: [
          FocusPage(
            key: ValueKey('focus-${session.id}'),
            session: session,
            serverNow: state.workspace!.pulse.now,
            notes: state.workspace!.todayData.thoughts,
            run: controller.run,
            recovered: state.restoredSessionId == session.id,
          ),
          ?toast,
        ],
      );
    }

    final workspace = state.workspace!;
    final page = state.page;
    final date = page == UiPage.calendar
        ? (state.day ?? workspace.pulse.today)
        : workspace.pulse.today;
    final selectedData = page == UiPage.calendar &&
            state.day != null &&
            state.day != workspace.pulse.today
        ? workspace.selectedData
        : workspace.todayData;
    final actions = TaskActions(
      run: controller.run,
      busy: state.busy,
      add: (title) => controller.openOverlay(
        UiOverlay(kind: OverlayKind.task, title: title),
      ),
      edit: (task) => controller.openOverlay(
        UiOverlay(kind: OverlayKind.task, task: task),
      ),
      remove: (task) => controller.openOverlay(
        UiOverlay(kind: OverlayKind.remove, task: task),
      ),
      start: (task) => controller.openOverlay(
        UiOverlay(kind: OverlayKind.focus, task: task),
      ),
      notes: () => controller.openOverlay(
        const UiOverlay(kind: OverlayKind.notes),
      ),
    );

    final body = switch (page) {
      UiPage.today => TodayPage(workspace: workspace, actions: actions),
      UiPage.calendar => CalendarPage(
          workspace: workspace,
          month: state.month ?? firstOfMonth(workspace.pulse.today),
          date: date,
          onMonthChanged: controller.setMonth,
          onSelect: controller.select,
          onReset: () => controller.select(workspace.pulse.today),
          actions: actions,
        ),
      UiPage.settings => SettingsPage(
          settings: workspace.settings,
          dataPath: workspace.dataPath,
          run: controller.run,
          backup: controller.backup,
          onThemePreview: controller.setThemePreview,
        ),
    };

    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Sidebar(page: page, onNavigate: controller.navigate),
            Expanded(
              child: Material(type: MaterialType.transparency, child: body),
            ),
          ],
        ),
        if (state.overlay.kind != OverlayKind.none)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0x6614241B),
              child: _Overlay(
                state: state,
                controller: controller,
                date: date,
                today: workspace.pulse.today,
                selectedThoughts: selectedData.thoughts,
              ),
            ),
          ),
        ?toast,
      ],
    );
  }
}

class _Startup extends StatelessWidget {
  const _Startup({
    required this.message,
    this.error = false,
    this.onRetry,
  });

  final String message;
  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Logo(),
            const SizedBox(height: 20),
            Text(
              message,
              key: Key(error ? 'startup-error' : 'startup-loading'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: error ? t.warn : t.muted,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FfButton(label: '重试', onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.page, required this.onNavigate});

  final UiPage page;
  final void Function(UiPage page) onNavigate;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final collapsed = constraints.maxHeight < 10000 &&
            MediaQuery.sizeOf(context).width < 1070;
        final entries = [
          (UiPage.today, '今日待办', Icons.check_circle_outline),
          (UiPage.calendar, '日历', Icons.calendar_month),
          (UiPage.settings, '设置', Icons.tune),
        ];
        return Container(
          key: const Key('sidebar'),
          width: collapsed ? 70 : 196,
          color: t.side,
          padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 10 : 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.only(left: collapsed ? 7 : 8),
                child: collapsed
                    ? Icon(Icons.menu, color: t.ink)
                    : const Logo(),
              ),
              const SizedBox(height: 37),
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: TextButton(
                    key: Key('nav-${entry.$1.name}'),
                    onPressed: () => onNavigate(entry.$1),
                    style: TextButton.styleFrom(
                      alignment: collapsed
                          ? Alignment.center
                          : Alignment.centerLeft,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      backgroundColor: page == entry.$1 ? t.wash : null,
                      foregroundColor:
                          page == entry.$1 ? t.accentText : t.muted,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      textStyle: TextStyle(
                        fontSize: 14,
                        fontWeight: page == entry.$1
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                    child: Row(
                      mainAxisSize:
                          collapsed ? MainAxisSize.min : MainAxisSize.max,
                      children: [
                        Icon(entry.$3, size: 20),
                        if (!collapsed) ...[
                          const SizedBox(width: 11),
                          Text(entry.$2),
                        ],
                      ],
                    ),
                  ),
                ),
              const Spacer(),
              if (!collapsed)
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: t.accent, borderRadius: BorderRadius.circular(4)),
                    ),
                    const SizedBox(width: 8),
                    Text('本地工作区',
                        style: TextStyle(fontSize: 12, color: t.quiet)),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.state,
    required this.controller,
    required this.date,
    required this.today,
    required this.selectedThoughts,
  });

  final UiState state;
  final UiController controller;
  final String date;
  final String today;
  final List<Thought> selectedThoughts;

  @override
  Widget build(BuildContext context) {
    final overlay = state.overlay;
    switch (overlay.kind) {
      case OverlayKind.task:
        return TaskForm(
          key: const Key('task-overlay'),
          task: overlay.task,
          title: overlay.title,
          date: date,
          minimum: today,
          onSave: (input) => controller.run(
            SaveTask(id: overlay.task?.id, task: input),
          ),
          onClose: controller.closeOverlay,
        );
      case OverlayKind.remove:
        final task = overlay.task;
        if (task == null) return const SizedBox.shrink();
        return FfModal(
          key: const Key('remove-overlay'),
          title: '删除任务',
          onClose: controller.closeOverlay,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('删除「${task.title}」？已记录的番茄专注历史会保留。'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FfButton(label: '取消', onPressed: controller.closeOverlay),
                  const SizedBox(width: 8),
                  FfButton(
                    key: const Key('remove-confirm'),
                    label: '确认删除',
                    variant: FfButtonVariant.danger,
                    onPressed: state.busy
                        ? null
                        : () async {
                            if (await controller.run(DeleteTask(id: task.id))) {
                              controller.closeOverlay();
                            }
                          },
                  ),
                ],
              ),
            ],
          ),
        );
      case OverlayKind.focus:
        return FocusForm(
          key: const Key('focus-overlay'),
          task: overlay.task,
          run: controller.run,
          onClose: controller.closeOverlay,
        );
      case OverlayKind.notes:
        return FfModal(
          key: const Key('notes-overlay'),
          title: date == today ? '今日番茄想法' : '番茄想法',
          onClose: controller.closeOverlay,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(fullDate(date),
                  style: TextStyle(color: tokens(context).muted)),
              const SizedBox(height: 13),
              Thoughts(
                notes: selectedThoughts,
                editable: date == today,
                run: controller.run,
              ),
            ],
          ),
        );
      case OverlayKind.interruptedQuick:
        final session = overlay.session;
        if (session == null) return const SizedBox.shrink();
        return FfModal(
          key: const Key('interrupted-quick-overlay'),
          title: '将专注事项加入今日待办？',
          onClose: controller.closeOverlay,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '「${session.session.taskTitleSnapshot}」本次完成了 '
                '${session.completedPomodoros} 个番茄。打断记录已保存。',
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FfButton(label: '暂不加入', onPressed: controller.closeOverlay),
                  const SizedBox(width: 8),
                  FfButton(
                    key: const Key('interrupted-quick-confirm'),
                    label: '加入今日待办',
                    variant: FfButtonVariant.primary,
                    onPressed: state.busy
                        ? null
                        : () async {
                            if (await controller.run(
                              SaveInterruptedQuick(id: session.id),
                            )) {
                              controller.closeOverlay();
                            }
                          },
                  ),
                ],
              ),
            ],
          ),
        );
      case OverlayKind.none:
        return const SizedBox.shrink();
    }
  }
}

class _Toast extends StatefulWidget {
  const _Toast({required this.notice, required this.onClose, super.key});

  final Notice notice;
  final VoidCallback onClose;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.notice.isError) {
      _timer = Timer(const Duration(seconds: 3), widget.onClose);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return Positioned(
      right: 19,
      bottom: 19,
      child: Material(
        // 无 Material 祖先时 Text 会落入 48px 的框架 fallback 样式。
        type: MaterialType.transparency,
        child: Container(
          key: Key(widget.notice.isError ? 'notice-error' : 'notice'),
          constraints: const BoxConstraints(maxWidth: 415),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.line),
            borderRadius: t.mediumBorder,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.notice.isError ? Icons.error_outline : Icons.check,
                size: 17,
                color: widget.notice.isError ? t.warn : t.accentText,
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(widget.notice.message,
                  style: TextStyle(
                      color: widget.notice.isError ? t.warn : t.accentText))),
              if (widget.notice.isError)
                FfButton(
                  label: '关闭',
                  variant: FfButtonVariant.ghost,
                  onPressed: widget.onClose,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
