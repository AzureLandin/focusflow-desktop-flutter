/// Riverpod 状态层：对应 src/renderer/index.tsx 的 App 组件状态机。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/db/data_dir.dart';
import '../data/repository.dart';
import '../shared/dates.dart';
import '../shared/model.dart';
import 'desktop_api.dart';

export 'desktop_api.dart' show DesktopApi, PulseResult, RepositoryDesktopApi;

// ---------------------------------------------------------------- 基础设施

final databaseFileProvider = Provider<File>((ref) => resolveDatabaseFile());

final desktopApiProvider = FutureProvider<DesktopApi>((ref) async {
  final repository = await Repository.open(ref.watch(databaseFileProvider));
  ref.onDispose(() => unawaited(repository.close()));
  return RepositoryDesktopApi(repository);
});

/// 步骤 6 接 audioplayers / local_notifier 时替换这两个 hook。
final chimeHookProvider = Provider<void Function()>((ref) => () {});
final notifyHookProvider = Provider<void Function(String)>((ref) => (_) {});

// ------------------------------------------------------------------ 主题

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;

  void setFromSettings(AppTheme theme) => set(switch (theme) {
        AppTheme.light => ThemeMode.light,
        AppTheme.dark => ThemeMode.dark,
        AppTheme.system => ThemeMode.system,
      });

  void toggle() => state = switch (state) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      };
}

// -------------------------------------------------------------- UI 状态模型

enum UiPage { today, calendar, settings }

enum OverlayKind { none, task, remove, focus, notes, interruptedQuick }

class UiOverlay {
  const UiOverlay({
    this.kind = OverlayKind.none,
    this.task,
    this.title,
    this.session,
  });

  final OverlayKind kind;
  final Task? task;
  final String? title;
  final ActiveSession? session;

  UiOverlay copyWith({
    OverlayKind? kind,
    Task? task,
    String? title,
    ActiveSession? session,
    bool clearSession = false,
  }) =>
      UiOverlay(
        kind: kind ?? this.kind,
        task: task ?? this.task,
        title: title ?? this.title,
        session: clearSession ? null : (session ?? this.session),
      );
}

class Notice {
  const Notice(this.message, this.isError);

  final String message;
  final bool isError;
}

class UiState {
  const UiState({
    this.workspace,
    this.page = UiPage.today,
    this.day,
    this.month,
    this.overlay = const UiOverlay(),
    this.busy = false,
    this.notice,
    this.restoredSessionId,
  });

  final Workspace? workspace;
  final UiPage page;
  final String? day;
  final String? month;
  final UiOverlay overlay;
  final bool busy;
  final Notice? notice;
  final String? restoredSessionId;

  Query get query => Query(day: day, month: month);

  UiState copyWith({
    Workspace? workspace,
    UiPage? page,
    String? day,
    String? month,
    UiOverlay? overlay,
    bool? busy,
    Notice? notice,
    bool clearNotice = false,
    String? restoredSessionId,
  }) =>
      UiState(
        workspace: workspace ?? this.workspace,
        page: page ?? this.page,
        day: day ?? this.day,
        month: month ?? this.month,
        overlay: overlay ?? this.overlay,
        busy: busy ?? this.busy,
        notice: clearNotice ? null : (notice ?? this.notice),
        restoredSessionId: restoredSessionId ?? this.restoredSessionId,
      );
}

const Map<Type, String> commandFeedback = <Type, String>{
  SaveTask: '任务已保存',
  DeleteTask: '任务已删除',
  Interrupt: '已保存打断记录',
  SettingsCommand: '设置已保存',
  Resolve: '专注记录已保存',
  SaveInterruptedQuick: '任务已加入今日待办',
};

// ------------------------------------------------------------------ 控制器

final uiControllerProvider =
    AsyncNotifierProvider<UiController, UiState>(UiController.new);

class UiController extends AsyncNotifier<UiState> {
  DesktopApi? _api;
  int _generation = 0;

  @override
  Future<UiState> build() async {
    final api = await ref.watch(desktopApiProvider.future);
    _api = api;
    final workspace = await api.read(const Query());
    ref.read(themeModeProvider.notifier).setFromSettings(workspace.settings.theme);
    // index.tsx:68：首次读到活动会话即视为“重启后恢复”。
    return UiState(
      workspace: workspace,
      restoredSessionId: workspace.pulse.session?.id,
    );
  }

  void _update(UiState Function(UiState previous) mutate) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(mutate(current));
  }

  void _report(Object error) {
    // React 版直接展示后端 IPC 消息（error.rs ipc() 的 `FF:<文案>`）。
    final raw = error.toString();
    final index = raw.indexOf('FF:');
    final message = index >= 0 ? raw.substring(index) : '操作失败，请重试。';
    _update((s) => s.copyWith(notice: Notice(message, true)));
  }

  void clearNotice() => _update((s) => s.copyWith(clearNotice: true));

  Future<void> refresh() async {
    final api = _api;
    if (api == null) return;
    final generation = ++_generation;
    try {
      final snapshot = await api.read(state.value?.query ?? const Query());
      if (generation != _generation) return;
      if (state.value?.workspace == null && snapshot.pulse.session != null) {
        _update(
          (s) => s.copyWith(restoredSessionId: snapshot.pulse.session!.id),
        );
      }
      ref
          .read(themeModeProvider.notifier)
          .setFromSettings(snapshot.settings.theme);
      _update((s) => s.copyWith(workspace: snapshot));
    } on Object catch (error) {
      if (generation == _generation) _report(error);
    }
  }

  /// index.tsx:75-109 的 900ms 轮询 + 前后台触发（这里由 750ms Timer 驱动）。
  Future<void> tick() async {
    final api = _api;
    final current = state.value;
    if (api == null || current == null || current.busy || current.workspace == null) {
      return;
    }
    try {
      final result = await api.pulse();
      final event = result.event;
      final settings = current.workspace!.settings;
      if (event != null) {
        if (settings.sound) ref.read(chimeHookProvider)();
        if (settings.notifications) {
          ref.read(notifyHookProvider)(event.message);
        }
      }
      final previous = current.workspace!;
      if (previous.pulse.today != result.pulse.today ||
          previous.pulse.session?.status != result.pulse.session?.status) {
        await refresh();
      } else {
        _update((s) => s.copyWith(workspace: previous.copyWith(pulse: result.pulse)));
      }
    } on Object catch (error) {
      _report(error);
    }
  }

  /// index.tsx:117-132 的 run()：防重入、成功后 refresh、反馈文案。
  Future<bool> run(Command command) async {
    final current = state.value;
    if (current == null || current.busy || _api == null) return false;
    _update((s) => s.copyWith(busy: true, clearNotice: true));
    try {
      final interrupted = command is Interrupt
          ? current.workspace?.pulse.session
          : null;
      await _api!.run(command);
      await refresh();
      if (command is Resolve || command is Interrupt) {
        _update((s) => s.copyWith(page: UiPage.today));
      }
      if (interrupted != null && interrupted.taskId == null) {
        _update(
          (s) => s.copyWith(
            overlay: UiOverlay(
              kind: OverlayKind.interruptedQuick,
              session: interrupted,
            ),
          ),
        );
      }
      final message = commandFeedback[command.runtimeType];
      if (message != null) {
        _update((s) => s.copyWith(notice: Notice(message, false)));
      }
      return true;
    } on Object catch (error) {
      _report(error);
      return false;
    } finally {
      _update((s) => s.copyWith(busy: false));
    }
  }

  Future<void> backup(String action) async {
    final current = state.value;
    if (current == null || current.busy || _api == null) return;
    _update((s) => s.copyWith(busy: true, clearNotice: true));
    try {
      if (await _api!.backup(action)) {
        await refresh();
        if (action == 'import') {
          _update((s) => s.copyWith(page: UiPage.today));
        }
        _update(
          (s) => s.copyWith(
            notice: Notice(
              action == 'export' ? '备份已导出' : '备份已恢复',
              false,
            ),
          ),
        );
      }
    } on Object catch (error) {
      _report(error);
    } finally {
      _update((s) => s.copyWith(busy: false));
    }
  }

  void navigate(UiPage next) {
    var shouldRefresh = false;
    _update((s) {
      var updated = s.copyWith(page: next, overlay: const UiOverlay());
      if (next == UiPage.calendar && updated.day == null && updated.workspace != null) {
        updated = updated.copyWith(
          day: updated.workspace!.pulse.today,
          month: firstOfMonth(updated.workspace!.pulse.today),
        );
        shouldRefresh = true;
      }
      return updated;
    });
    // 对齐 React 的 useEffect([day, month])。
    if (shouldRefresh) unawaited(refresh());
  }

  void select(String date) {
    _update((s) => s.copyWith(day: date, month: firstOfMonth(date)));
    unawaited(refresh());
  }

  void setMonth(String month) {
    _update((s) => s.copyWith(month: month));
    unawaited(refresh());
  }

  void openOverlay(UiOverlay overlay) =>
      _update((s) => s.copyWith(overlay: overlay));

  void closeOverlay() =>
      _update((s) => s.copyWith(overlay: const UiOverlay()));

  void setThemePreview(AppTheme theme) => ref
      .read(themeModeProvider.notifier)
      .setFromSettings(theme);
}

// ------------------------------------------------------------- 派生 provider

final workspaceProvider = Provider<Workspace?>((ref) {
  final value = ref.watch(uiControllerProvider).value;
  return value?.workspace;
});

final busyProvider = Provider<bool>((ref) {
  final value = ref.watch(uiControllerProvider).value;
  return value?.busy ?? false;
});

final noticeProvider = Provider<Notice?>((ref) {
  final value = ref.watch(uiControllerProvider).value;
  return value?.notice;
});

final pulseProvider = Provider<Pulse?>((ref) => ref.watch(workspaceProvider)?.pulse);

/// 750ms 心跳。AppShell 必须 watch 它一次才会启动。
final heartbeatProvider = Provider<void>((ref) {
  final controller = ref.read(uiControllerProvider.notifier);
  final timer = Timer.periodic(
    const Duration(milliseconds: 750),
    (_) => unawaited(controller.tick()),
  );
  ref.onDispose(timer.cancel);
});
