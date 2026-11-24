/// 平台 hook 测试：pulse/command 事件按 sound / notifications 开关触发，
/// 插件替身通过 provider override 注入，不依赖真实音频/通知。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focusflow/shared/model.dart';
import 'package:focusflow/state/providers.dart';
import 'package:test/test.dart';

class _StubApi implements DesktopApi {
  _StubApi(this.settings, this.event, {this.backupResult = false});

  final Settings settings;
  final TimerEvent? event;
  final bool backupResult;
  final List<Command> commands = <Command>[];

  Workspace _workspace() {
    final record = DayRecord(
      date: '2026-11-23',
      finalizedAt: null,
      totalTasks: 0,
      completedTasks: 0,
      unfinishedTasks: 0,
      totalCompletedPomodoros: 0,
      totalFocusSeconds: 0,
    );
    final data = DayData(
      tasks: const [],
      thoughts: const [],
      record: record,
      activity: const [],
    );
    return Workspace(
      pulse: Pulse(now: 1763900000000, today: '2026-11-23', session: null),
      todayData: data,
      selectedData: data,
      calendar: const [],
      settings: settings,
      dataPath: '/tmp/focusflow.sqlite3',
    );
  }

  @override
  Future<Workspace> read(Query query) async => _workspace();

  @override
  Future<PulseResult> pulse() async =>
      PulseResult(pulse: _workspace().pulse, event: event);

  @override
  Future<TimerEvent?> run(Command command) async {
    commands.add(command);
    return event;
  }

  @override
  Future<bool> backup(String action) async => backupResult;

  @override
  Future<void> dispose() async {}
}

ProviderContainer _container(
  _StubApi api,
  List<String> chimes,
  List<String> notifications,
) {
  final container = ProviderContainer(
    overrides: [
      desktopApiProvider.overrideWith((ref) async => api),
      chimeHookProvider.overrideWithValue(() => chimes.add('chime')),
      notifyHookProvider.overrideWithValue(notifications.add),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  const event = TimerEvent(
    message: '本轮专注已完成',
    sound: true,
    notify: true,
  );

  test('pulse 事件：sound/notifications 都开 → 两个 hook 都调用', () async {
    final chimes = <String>[];
    final notifications = <String>[];
    final api = _StubApi(Settings.defaults, event);
    final container = _container(api, chimes, notifications);
    await container.read(uiControllerProvider.future);

    await container.read(uiControllerProvider.notifier).tick();

    expect(chimes, ['chime']);
    expect(notifications, ['本轮专注已完成']);
  });

  test('pulse 事件：都关 → 两个 hook 都不调用', () async {
    final chimes = <String>[];
    final notifications = <String>[];
    final settings = Settings.defaults.copyWith(
      sound: false,
      notifications: false,
    );
    final api = _StubApi(settings, event);
    final container = _container(api, chimes, notifications);
    await container.read(uiControllerProvider.future);

    await container.read(uiControllerProvider.notifier).tick();

    expect(chimes, isEmpty);
    expect(notifications, isEmpty);
  });

  test('pulse 事件：只开提示音 → 仅 chime', () async {
    final chimes = <String>[];
    final notifications = <String>[];
    final settings = Settings.defaults.copyWith(notifications: false);
    final api = _StubApi(settings, event);
    final container = _container(api, chimes, notifications);
    await container.read(uiControllerProvider.future);

    await container.read(uiControllerProvider.notifier).tick();

    expect(chimes, ['chime']);
    expect(notifications, isEmpty);
  });

  test('无事件时 hook 不调用', () async {
    final chimes = <String>[];
    final notifications = <String>[];
    final api = _StubApi(Settings.defaults, null);
    final container = _container(api, chimes, notifications);
    await container.read(uiControllerProvider.future);

    await container.read(uiControllerProvider.notifier).tick();

    expect(chimes, isEmpty);
    expect(notifications, isEmpty);
  });

  test('命令返回的事件同样触发 hook（对齐 with_repository）', () async {
    final chimes = <String>[];
    final notifications = <String>[];
    final api = _StubApi(Settings.defaults, event);
    final container = _container(api, chimes, notifications);
    await container.read(uiControllerProvider.future);

    final ok = await container
        .read(uiControllerProvider.notifier)
        .run(const ToggleTask(id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'));

    expect(ok, isTrue);
    expect(chimes, ['chime']);
    expect(notifications, ['本轮专注已完成']);
  });

  test('备份取消（返回 false）静默，不显示 notice', () async {
    final chimes = <String>[];
    final notifications = <String>[];
    final api = _StubApi(Settings.defaults, null, backupResult: false);
    final container = _container(api, chimes, notifications);
    await container.read(uiControllerProvider.future);

    await container.read(uiControllerProvider.notifier).backup('export');

    final state = container.read(uiControllerProvider).value!;
    expect(state.notice, isNull);
    expect(state.busy, isFalse);
  });

  test('备份成功（返回 true）显示成功提示', () async {
    final api = _StubApi(Settings.defaults, null, backupResult: true);
    final container = _container(api, <String>[], <String>[]);
    await container.read(uiControllerProvider.future);

    await container.read(uiControllerProvider.notifier).backup('export');

    final state = container.read(uiControllerProvider).value!;
    expect(state.notice?.message, '备份已导出');
    expect(state.notice?.isError, isFalse);
  });
}
