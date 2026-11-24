/// src/renderer/planner.tsx 的 Today 页。
library;

import 'package:material_ui/material_ui.dart';

import '../shared/model.dart';
import 'tasks.dart';
import 'widgets.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({required this.workspace, required this.actions, super.key});

  final Workspace workspace;
  final TaskActions actions;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final data = workspace.todayData;
    final record = data.record;
    final pending = data.tasks.where((task) => task.status != 'completed').toList();
    final done = data.tasks.where((task) => task.status == 'completed').toList();

    return SingleChildScrollView(
      key: const Key('today-page'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(27, 47, 27, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_month, size: 16, color: t.muted),
                              const SizedBox(width: 8),
                              Text(fullDate(workspace.pulse.today),
                                  style: TextStyle(color: t.muted, fontWeight: FontWeight.w500)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text('今日待办',
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.045,
                                color: t.ink,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 23),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 720;
                    final work = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text.rich(
                              TextSpan(
                                style: TextStyle(color: t.muted),
                                children: [
                                  TextSpan(
                                    text: '${record.completedTasks} / ${record.totalTasks}',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: t.ink),
                                  ),
                                  const TextSpan(text: ' 已完成'),
                                ],
                              ),
                            ),
                            const SizedBox(width: 15),
                            SizedBox(
                              width: 168,
                              height: 6,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  key: const Key('today-progress'),
                                  value: record.totalTasks == 0
                                      ? 0
                                      : record.completedTasks / record.totalTasks,
                                  backgroundColor: t.wash,
                                  color: t.accent,
                                  minHeight: 6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        QuickAdd(date: workspace.pulse.today, actions: actions),
                        SectionTitle(title: '待完成', count: pending.length),
                        const SizedBox(height: 6),
                        if (pending.isNotEmpty)
                          TaskRows(tasks: pending, actions: actions)
                        else
                          EmptyState(
                            title: done.isNotEmpty ? '今天的任务都完成了' : '今天从一件事开始',
                            text: done.isNotEmpty ? null : '把今天想做的事记到这里。',
                            action: FfButton(
                              key: const Key('empty-add'),
                              label: done.isNotEmpty ? '再添加一件事' : '添加今天的第一件事',
                              variant: FfButtonVariant.ghost,
                              onPressed: () => actions.add(null),
                            ),
                          ),
                        const SizedBox(height: 22),
                        SectionTitle(title: '已完成', count: done.length),
                        const SizedBox(height: 6),
                        if (done.isNotEmpty)
                          TaskRows(tasks: done, actions: actions)
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            child: Text('完成的任务会显示在这里。',
                                style: TextStyle(color: t.quiet)),
                          ),
                      ],
                    );
                    final aside = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          key: const Key('focus-card'),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: t.focusCard,
                            borderRadius: t.largeBorder,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.timer, color: t.onCard, size: 22),
                              const SizedBox(height: 19),
                              Text('番茄时钟',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      color: t.onCard)),
                              const SizedBox(height: 4),
                              Text('默认专注 ${workspace.settings.focusMinutes} 分钟',
                                  style: TextStyle(fontSize: 13, color: t.cardMuted)),
                              const SizedBox(height: 19),
                              FfButton(
                                key: const Key('quick-focus'),
                                label: '快速开始专注',
                                icon: Icons.play_arrow,
                                variant: FfButtonVariant.primary,
                                onPressed: () => actions.start(null),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${record.totalCompletedPomodoros}',
                                        style: TextStyle(fontSize: 19, color: t.ink)),
                                    Text('今日番茄',
                                        style: TextStyle(fontSize: 12, color: t.muted)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(timeSpan(record.totalFocusSeconds),
                                        style: TextStyle(fontSize: 19, color: t.ink)),
                                    Text('专注时长',
                                        style: TextStyle(fontSize: 12, color: t.muted)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          key: const Key('thought-entry'),
                          onPressed: actions.notes,
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            foregroundColor: t.accentText,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.lightbulb_outline, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('今日番茄想法',
                                        style: TextStyle(fontWeight: FontWeight.w600)),
                                    Text(
                                      data.thoughts.isEmpty
                                          ? '随手留下专注时冒出的念头'
                                          : data.thoughts.first.content,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12, color: t.muted),
                                    ),
                                  ],
                                ),
                              ),
                              Text('${data.thoughts.length}'),
                            ],
                          ),
                        ),
                        DayActivity(data: data),
                      ],
                    );
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [work, const SizedBox(height: 24), aside],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: work),
                        const SizedBox(width: 30),
                        SizedBox(width: 264, child: aside),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
