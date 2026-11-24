/// src/renderer/focus.tsx 的专注全屏页（倒计时 + 打断 + 总结）。
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../shared/model.dart';
import 'tasks.dart' show RunCommand;
import 'thoughts.dart';
import 'widgets.dart';

const Map<String, String> phaseLabels = {
  'focus': '专注',
  'short_break': '短休息',
  'long_break': '长休息',
};

const List<String> interruptReasons = [
  '临时有事',
  '接到电话或消息',
  '需要处理紧急任务',
  '身体不适或需要休息',
  '其他',
];

class FocusPage extends StatefulWidget {
  const FocusPage({
    required this.session,
    required this.serverNow,
    required this.notes,
    required this.run,
    this.recovered = false,
    super.key,
  });

  final ActiveSession session;
  final int serverNow;
  final List<Thought> notes;
  final RunCommand run;
  final bool recovered;

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  bool _showNotes = false;
  bool _saveQuick = false;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final session = widget.session;
    final summary = session.status == 'session_completed';
    final focusRunning = session.status == 'focus_running';
    final focusElapsed = session.status == 'focus_elapsed';
    final breakElapsed = session.status == 'break_elapsed';

    return Scaffold(
      key: const Key('focus-page'),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
            child: Row(
              children: [
                const Logo(),
                const Spacer(),
                FfButton(
                  key: const Key('focus-notes-toggle'),
                  label: '番茄想法（${widget.notes.length}）',
                  variant: FfButtonVariant.ghost,
                  icon: Icons.lightbulb_outline,
                  onPressed: () => setState(() => _showNotes = !_showNotes),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 880;
                final main = SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 30),
                        child: Column(
                          children: [
                            if (widget.recovered)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 9),
                                child: Text('已恢复上次的专注会话',
                                    key: const Key('recovered-banner'),
                                    style: TextStyle(color: t.muted, fontSize: 12)),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                              decoration: BoxDecoration(
                                color: t.wash,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    summary
                                        ? Icons.check
                                        : session.currentPhase == 'focus'
                                            ? Icons.timer
                                            : Icons.coffee,
                                    size: 16,
                                    color: t.accentText,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    key: const Key('focus-stage'),
                                    summary
                                        ? '专注总结'
                                        : phaseLabels[session.currentPhase] ?? session.currentPhase,
                                    style: TextStyle(
                                        color: t.accentText,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              session.session.taskTitleSnapshot,
                              key: const Key('focus-title'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w700,
                                  color: t.ink),
                            ),
                            const SizedBox(height: 7),
                            if (summary)
                              _Summary(
                                session: session,
                                saveQuick: _saveQuick,
                                onSaveQuick: (v) => setState(() => _saveQuick = v),
                                run: widget.run,
                              )
                            else ...[
                              Text('第 ${session.currentCycle} / ${session.plannedPomodoros} 个番茄',
                                  key: const Key('focus-cycle'),
                                  style: TextStyle(color: t.muted)),
                              const SizedBox(height: 16),
                              CountdownView(
                                key: const Key('countdown-view'),
                                serverNow: widget.serverNow,
                                phaseStartedAt: session.phaseStartedAt,
                                phaseEndsAt: session.phaseEndsAt,
                                builder: (countdown, percent) => Container(
                                  key: const Key('countdown-ring'),
                                  width: 260,
                                  height: 260,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: t.wash,
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 248,
                                      height: 248,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: t.paper,
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            countdown,
                                            key: const Key('countdown'),
                                            style: TextStyle(
                                                fontSize: 64,
                                                fontWeight: FontWeight.w500,
                                                color: t.ink),
                                          ),
                                          Text(
                                            focusElapsed
                                                ? '专注已完成'
                                                : breakElapsed
                                                    ? '休息已结束'
                                                    : session.currentPhase == 'focus'
                                                        ? '专注计时中'
                                                        : '休息计时中',
                                            key: const Key('countdown-caption'),
                                            style: TextStyle(color: t.muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                key: const Key('cycle-dots'),
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < session.plannedPomodoros; i++)
                                    Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 3),
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: i < session.completedPomodoros
                                            ? t.accent
                                            : t.wash,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 9),
                              Text(
                                key: const Key('focus-next'),
                                _nextText(session, focusElapsed, breakElapsed, focusRunning),
                                style: TextStyle(color: t.muted),
                              ),
                              const SizedBox(height: 16),
                              _FocusActions(
                                session: session,
                                run: widget.run,
                                onInterrupt: () => showDialog<void>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => InterruptDialog(
                                    session: session,
                                    run: widget.run,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
                final notesPanel = Container(
                  width: 282,
                  color: t.side,
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline, size: 19, color: t.accentText),
                          const SizedBox(width: 7),
                          Text('番茄想法',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: t.ink)),
                        ],
                      ),
                      const SizedBox(height: 13),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Thoughts(
                            key: const Key('focus-thoughts'),
                            notes: widget.notes,
                            editable: true,
                            run: widget.run,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                if (narrow) {
                  return Stack(
                    children: [
                      main,
                      if (_showNotes)
                        Positioned(right: 0, top: 0, bottom: 0, child: notesPanel),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [Expanded(child: main), notesPanel],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _nextText(
    ActiveSession session,
    bool focusElapsed,
    bool breakElapsed,
    bool focusRunning,
  ) {
    final next = session.nextBreak == null
        ? '可以查看本次专注总结'
        : '接下来是${phaseLabels[session.nextBreak]}';
    if (focusElapsed) return next;
    if (breakElapsed) {
      return session.endingBreak == 1
          ? '可以查看本次专注总结'
          : '准备好后开始下一个番茄';
    }
    if (focusRunning) {
      return session.nextBreak == null
          ? '本轮结束后查看专注总结'
          : '下一阶段：${phaseLabels[session.nextBreak]}';
    }
    return '休息结束后，由你继续';
  }
}

/// 单个 Ticker 本地插值；seconds 只在变化时 setState。
class CountdownView extends StatefulWidget {
  const CountdownView({
    required this.serverNow,
    required this.phaseStartedAt,
    required this.phaseEndsAt,
    required this.builder,
    super.key,
  });

  final int serverNow;
  final int phaseStartedAt;
  final int phaseEndsAt;
  final Widget Function(String countdown, double percent) builder;

  @override
  State<CountdownView> createState() => _CountdownViewState();
}

class _CountdownViewState extends State<CountdownView>
    with TickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _anchor = Duration.zero;
  bool _needsReset = true;
  String _countdown = '';
  double _percent = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _compute(Duration.zero);
  }

  @override
  void didUpdateWidget(CountdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverNow != widget.serverNow ||
        oldWidget.phaseStartedAt != widget.phaseStartedAt ||
        oldWidget.phaseEndsAt != widget.phaseEndsAt) {
      _needsReset = true;
    }
  }

  void _onTick(Duration elapsed) {
    if (_needsReset) {
      _anchor = elapsed;
      _needsReset = false;
    }
    _compute(elapsed - _anchor);
  }

  void _compute(Duration local) {
    final now = widget.serverNow + local.inMilliseconds;
    final seconds = math.max(
      0,
      ((widget.phaseEndsAt - now) / 1000).ceil(),
    );
    final countdown =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    final span = widget.phaseEndsAt - widget.phaseStartedAt;
    final percent = span <= 0
        ? 100.0
        : ((now - widget.phaseStartedAt) / span * 100).clamp(0.0, 100.0);
    if (countdown != _countdown || percent != _percent) {
      setState(() {
        _countdown = countdown;
        _percent = percent;
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_countdown, _percent);
}

class _FocusActions extends StatelessWidget {
  const _FocusActions({required this.session, required this.run, required this.onInterrupt});

  final ActiveSession session;
  final RunCommand run;
  final VoidCallback onInterrupt;

  @override
  Widget build(BuildContext context) {
    final focusRunning = session.status == 'focus_running';
    final focusElapsed = session.status == 'focus_elapsed';
    final breakElapsed = session.status == 'break_elapsed';
    if (focusRunning) {
      return FfButton(
        key: const Key('interrupt-button'),
        label: '打断番茄',
        icon: Icons.pause_circle_outline,
        variant: FfButtonVariant.ghost,
        onPressed: onInterrupt,
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 7,
      children: [
        if (!((focusElapsed && session.nextBreak == null) ||
            (breakElapsed && session.endingBreak == 1)))
          FfButton(
            label: session.endingBreak == 1 ||
                    session.completedPomodoros == session.plannedPomodoros
                ? '跳过休息'
                : '结束本次专注',
            icon: Icons.stop_circle_outlined,
            variant: FfButtonVariant.ghost,
            onPressed: () => run(EndSession(id: session.id)),
          ),
        if (focusElapsed || breakElapsed)
          FfButton(
            key: const Key('advance-button'),
            label: focusElapsed
                ? (session.nextBreak == null
                    ? '查看专注总结'
                    : '开始${phaseLabels[session.nextBreak]}')
                : (session.endingBreak == 1
                    ? '查看专注总结'
                    : '开始下一个番茄'),
            icon: focusElapsed && session.nextBreak != null
                ? Icons.coffee
                : Icons.play_arrow,
            variant: FfButtonVariant.primary,
            onPressed: () => run(Advance(id: session.id)),
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.session,
    required this.saveQuick,
    required this.onSaveQuick,
    required this.run,
  });

  final ActiveSession session;
  final bool saveQuick;
  final void Function(bool) onSaveQuick;
  final RunCommand run;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final canComplete = (session.taskId != null && session.canConfirm) ||
        (session.taskId == null && saveQuick);
    final text = session.taskId != null
        ? (session.canConfirm
            ? '这项任务完成了吗？'
            : '任务还未达到计划番茄数，可以稍后继续。')
        : (saveQuick ? '这项任务完成了吗？' : '本次专注记录已保存在日历里。');
    return SizedBox(
      width: 470,
      child: Column(
        children: [
          const SizedBox(height: 25),
          Row(
            children: [
              for (final entry in [
                ('${session.completedPomodoros} / ${session.plannedPomodoros}', '完成番茄'),
                (timeSpan(session.focusSeconds), '有效专注'),
                ('${session.thoughtCount}', '番茄想法'),
              ])
                Expanded(
                  child: Column(
                    children: [
                      Text(entry.$1,
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w600, color: t.ink)),
                      Text(entry.$2,
                          style: TextStyle(fontSize: 12, color: t.muted)),
                    ],
                  ),
                ),
            ],
          ),
          if (session.taskId == null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Checkbox(value: saveQuick, onChanged: (v) => onSaveQuick(v ?? false)),
                Text('加入今日待办', style: TextStyle(color: t.ink)),
              ],
            ),
          const SizedBox(height: 17),
          Text(text, style: TextStyle(color: t.muted)),
          const SizedBox(height: 17),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: canComplete
                ? [
                    FfButton(
                      key: const Key('summary-continue'),
                      label: '还需要继续',
                      onPressed: () => run(Resolve(
                          id: session.id, completed: false, saveQuick: saveQuick)),
                    ),
                    const SizedBox(width: 7),
                    FfButton(
                      key: const Key('summary-complete'),
                      label: '任务已完成',
                      icon: Icons.check,
                      variant: FfButtonVariant.primary,
                      onPressed: () => run(Resolve(
                          id: session.id, completed: true, saveQuick: saveQuick)),
                    ),
                  ]
                : [
                    FfButton(
                      key: const Key('summary-back'),
                      label: '返回今日待办',
                      variant: FfButtonVariant.primary,
                      onPressed: () => run(Resolve(
                          id: session.id, completed: false, saveQuick: saveQuick)),
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}

class InterruptDialog extends StatefulWidget {
  const InterruptDialog({required this.session, required this.run, super.key});

  final ActiveSession session;
  final RunCommand run;

  @override
  State<InterruptDialog> createState() => _InterruptDialogState();
}

class _InterruptDialogState extends State<InterruptDialog> {
  String? _selected;
  final _custom = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  String get reason {
    if (_selected == '其他' || _selected == null || _selected!.isEmpty) {
      return _custom.text.trim();
    }
    return [_selected!, _custom.text.trim()].where((s) => s.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return FfModal(
      key: const Key('interrupt-modal'),
      title: '打断番茄',
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '第 ${widget.session.currentCycle} 轮将记为已打断。已完成的番茄和记录的想法会保留。',
            style: TextStyle(color: t.muted),
          ),
          const SizedBox(height: 12),
          Text('打断原因', style: TextStyle(color: t.ink)),
          const SizedBox(height: 6),
          RadioGroup<String>(
            groupValue: _selected,
            onChanged: (value) => setState(() => _selected = value),
            child: Wrap(
              spacing: 12,
              children: [
                for (final item in interruptReasons)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Radio<String>(value: item),
                      Text(item, style: TextStyle(fontSize: 13)),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('interrupt-reason'),
            controller: _custom,
            maxLength: 450,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: _selected != null && _selected != '其他'
                  ? '补充说明（可选）'
                  : '填写原因',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FfButton(
                label: '返回专注',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              FfButton(
                key: const Key('interrupt-confirm'),
                label: '确认打断',
                variant: FfButtonVariant.danger,
                onPressed: reason.isEmpty || _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final ok = await widget.run(
                          Interrupt(id: widget.session.id, reason: reason),
                        );
                        if (ok && mounted && context.mounted) {
                          Navigator.of(context).pop();
                        } else if (mounted) {
                          setState(() => _busy = false);
                        }
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
