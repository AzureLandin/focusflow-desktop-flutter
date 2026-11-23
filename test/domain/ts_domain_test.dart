/// tests/domain.test.ts 的 8 个用例逐条移植（文件:行号见每个 test 注释）。
library;

import 'package:focusflow/data/backup.dart';
import 'package:focusflow/shared/errors.dart';
import 'package:focusflow/shared/model.dart';
import 'package:test/test.dart';

import 'harness.dart';
import 'rust_domain_test.dart' show deepCopy;

void main() {
  /// domain.test.ts:36 task CRUD, rank, completion, undo, moving retain ID
  test('T1 任务增删改、排序、完成与撤销保留 ID', () async {
    final h = Harness();
    await h.init();
    final first = await h.task('第一项', pomodoroEnabled: false);
    final second = await h.task('第二项', pomodoroEnabled: false);

    await h.cmd(MoveTask(id: second, direction: -1));
    expect(
      (await h.read()).todayData.tasks.map((t) => t.id).toList(),
      [second, first],
    );
    await h.cmd(ToggleTask(id: first));
    expect((await h.read()).todayData.record.completedTasks, 1);
    await h.cmd(ToggleTask(id: first));
    expect((await h.read()).todayData.record.completedTasks, 0);

    await h.cmd(
      SaveTask(
        id: first,
        task: const TaskInput(
          title: '改名',
          scheduledDate: '2026-11-25',
          description: '详情',
          pomodoroEnabled: true,
          plannedPomodoros: 2,
        ),
      ),
    );
    expect(
      (await h.read()).todayData.tasks.map((t) => t.id).toList(),
      [second],
    );
    expect((await h.read('2026-11-25')).selectedData.tasks[0].id, first);
    await h.cmd(DeleteTask(id: first));
    expect((await h.read('2026-11-25')).selectedData.tasks.length, 0);
    final rows = await h.repo.db.customSelect(
      "SELECT deleted_at FROM tasks WHERE id='$first'",
    ).get();
    expect(rows.single.data['deleted_at'], isNotNull);
  });

  /// domain.test.ts:55 opening after several days archives days, future IDs and final states
  test('T2 多日后归档空日与有数据日、保留未来 ID 与终态', () async {
    final h = Harness();
    await h.init();
    final finished = await h.task('设计方案', pomodoroEnabled: false);
    final unfinished = await h.task('设计方案', pomodoroEnabled: false);
    final future = await h.task(
      '设计方案',
      day: '2026-11-26',
      pomodoroEnabled: false,
    );
    await h.cmd(ToggleTask(id: finished));

    h.setTime('2026-11-26');
    await h.reopen();
    final snapshot = await h.read('2026-11-23');
    expect(snapshot.todayData.tasks.map((t) => t.id).toList(), [future]);
    expect(
      snapshot.selectedData.tasks.map((t) => [t.id, t.status]).toList(),
      [
        [finished, 'completed'],
        [unfinished, 'unfinished']
      ],
    );
    final rows = await h.repo.db.customSelect(
      'SELECT date FROM daily_records ORDER BY date',
    ).get();
    expect(
      rows.map((r) => r.read<String>('date')).toList(),
      ['2026-11-23', '2026-11-24', '2026-11-25'],
    );
    await expectLater(
      h.cmd(ToggleTask(id: unfinished)),
      throwsA(isA<FocusFlowException>()),
    );
    final count = await h.repo.db.customSelect('SELECT COUNT(*) AS n FROM tasks').get();
    expect(count.single.read<int>('n'), 3);
  });

  /// domain.test.ts:71 six cycles use short and long breaks correctly
  test('T3 六轮番茄的长短休交替与显式完成', () async {
    final h = Harness();
    await h.init();
    final id = await h.task('设计方案', count: 6);
    await h.cmd(Start(taskId: id, count: 6));
    final session = (await h.active()).id;

    Future<ActiveSession> active() => h.active();
    Future<void> advance() => h.cmd(Advance(id: session));
    var a = await active();
    expect(a.phaseEndsAt - a.phaseStartedAt, 25 * 60_000);

    for (var cycle = 1; cycle <= 6; cycle++) {
      h.elapse(25);
      a = await active();
      expect(a.status, 'focus_elapsed');
      expect(a.currentCycle, cycle);
      expect(a.completedPomodoros, cycle);
      expect((await h.read()).todayData.tasks[0].completedPomodoros, cycle);
      await advance();
      if (cycle == 6) break;
      a = await active();
      expect(
        a.status,
        cycle == 4 ? 'long_break_running' : 'short_break_running',
      );
      expect(
        a.phaseEndsAt - a.phaseStartedAt,
        (cycle == 4 ? 15 : 5) * 60_000,
      );
      h.elapse(cycle == 4 ? 15 : 5);
      expect((await active()).status, 'break_elapsed');
      await advance();
    }
    expect((await active()).status, 'session_completed');
    expect((await h.read()).todayData.tasks[0].status, 'in_progress');
    await h.cmd(Resolve(id: session, completed: true));
    expect((await h.read()).todayData.tasks[0].status, 'completed');
    expect((await h.read()).todayData.record.totalFocusSeconds, 6 * 25 * 60);
    expect(h.notifications.length, 11);
  });

  /// domain.test.ts:102 optional final long break can be skipped; continued task appends cycles
  test('T4 可选末轮长休可跳过，继续任务可追加番茄', () async {
    final h = Harness();
    await h.init();
    await h.cmd(
      SettingsCommand(
        settings: Settings.defaults.copyWith(finalLongBreak: true, longEvery: 1),
      ),
    );
    final id = await h.task('设计方案');
    await h.cmd(Start(count: 1, taskId: id));
    final session = (await h.active()).id;

    h.elapse(25);
    expect((await h.active()).nextBreak, 'long_break');
    await h.cmd(EndSession(id: session));
    expect((await h.active()).status, 'session_completed');
    await h.cmd(Resolve(id: session, completed: false));
    await h.cmd(Start(count: 1, taskId: id));
    h.elapse(25);
    expect((await h.read()).todayData.tasks[0].completedPomodoros, 2);
  });

  /// domain.test.ts:119 interruption captures reason, thoughts intact, no tomato
  test('T5 打断保留原因与想法、不计番茄', () async {
    final h = Harness();
    await h.init();
    final id = await h.task('设计方案');
    await h.cmd(Start(count: 2, taskId: id));
    final session = (await h.active()).id;
    await h.cmd(const SaveThought(content: '把资料放进草稿'));
    await expectLater(
      h.cmd(ToggleTask(id: id)),
      throwsA(isA<FocusFlowException>()),
    );
    await expectLater(
      h.cmd(Interrupt(id: session, reason: ' ')),
      throwsA(isA<Exception>()),
    );
    h.elapse(3);
    await h.cmd(Interrupt(id: session, reason: '紧急电话'));
    await h.reopen();

    final ws = await h.read();
    expect(ws.pulse.session, isNull);
    expect(ws.todayData.tasks[0].completedPomodoros, 0);
    expect(ws.todayData.thoughts[0].sessionId, session);
    expect(ws.todayData.activity[0].reason, '紧急电话');
    expect(ws.todayData.activity[0].focusSeconds, 180);
    await h.cmd(DeleteTask(id: id));
    expect((await h.read()).todayData.activity[0].title, '设计方案');

    h.elapse(1440);
    expect((await h.read()).todayData.thoughts.length, 0);
    expect((await h.read('2026-11-23')).selectedData.thoughts.length, 1);
  });

  /// domain.test.ts:143 restart after elapsed records one phase and waits
  test('T6 重启后只记一次完成阶段并等待用户', () async {
    final h = Harness();
    await h.init();
    final id = await h.task('设计方案', count: 2);
    await h.cmd(Start(count: 2, taskId: id));
    final oldEnd = (await h.active()).phaseEndsAt;

    h.elapse(5);
    await h.reopen();
    expect((await h.active()).phaseEndsAt, oldEnd);
    expect((await h.active()).status, 'focus_running');

    h.elapse(48 * 60);
    await h.reopen();
    final state = await h.active();
    expect(state.status, 'focus_elapsed');
    expect(state.completedPomodoros, 1);
    expect(
      (await h.read('2026-11-23')).selectedData.record.totalCompletedPomodoros,
      1,
    );
    await h.cmd(Advance(id: state.id));
    h.elapse(100);
    await h.reopen();
    final after = await h.active();
    expect(after.status, 'break_elapsed');
    expect(after.currentCycle, 1);
  });

  /// domain.test.ts:165 quick focus saved only when requested; backup restores atomically
  test('T7 快速专注按选项保存，备份原子恢复', () async {
    final h = Harness();
    await h.init();
    for (final saveQuick in [false, true]) {
      await h.cmd(const Start(count: 1, title: '自由阅读'));
      final id = (await h.active()).id;
      h.elapse(25);
      await h.cmd(Advance(id: id));
      await h.cmd(
        Resolve(id: id, completed: saveQuick, saveQuick: saveQuick),
      );
    }
    expect((await h.read()).todayData.tasks.length, 1);
    expect((await h.read()).todayData.tasks[0].status, 'completed');

    final raw = await exportBackup(h.repo.db);
    await h.task('备份之外', pomodoroEnabled: false);
    await restoreBackup(h.repo, raw, h.now);
    expect((await h.read()).todayData.tasks.length, 1);

    final broken = deepCopy(decodeBackup(raw));
    (broken['data']['pomodoro_cycles'] as List).first['session_id'] = 'missing';
    await expectLater(
      restoreBackup(h.repo, broken, h.now),
      throwsA(isA<Exception>()),
    );
    expect(await exportBackup(h.repo.db), raw);
  });

  /// domain.test.ts:187 interrupted quick session becomes a single task
  test('T8 被打断的快速专注转为单个任务且不计轮次', () async {
    final h = Harness();
    await h.init();
    await h.cmd(const Start(count: 1, title: '随手练习'));
    final id = (await h.active()).id;
    await h.cmd(Interrupt(id: id, reason: '需要离开'));
    expect((await h.read()).todayData.tasks.length, 0);
    await h.cmd(SaveInterruptedQuick(id: id));
    await expectLater(
      h.cmd(SaveInterruptedQuick(id: id)),
      throwsA(isA<FocusFlowException>()),
    );
    final saved = (await h.read()).todayData.tasks.single;
    expect(saved.completedPomodoros, 0);
    expect(saved.title, '随手练习');
  });
}
