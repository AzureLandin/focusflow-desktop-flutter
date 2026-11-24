/// src/renderer/planner.tsx 的 Calendar 页（42 格月历 + 日期详情）。
library;

import 'package:material_ui/material_ui.dart';

import '../shared/dates.dart';
import '../shared/model.dart';
import 'tasks.dart';
import 'widgets.dart';

class CalendarPage extends StatelessWidget {
  const CalendarPage({
    required this.workspace,
    required this.month,
    required this.date,
    required this.onMonthChanged,
    required this.onSelect,
    required this.onReset,
    required this.actions,
    super.key,
  });

  final Workspace workspace;
  final String month;
  final String date;
  final void Function(String month) onMonthChanged;
  final void Function(String date) onSelect;
  final VoidCallback onReset;
  final TaskActions actions;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final detail = workspace.selectedData;
    final record = detail.record;
    final history = date.compareTo(workspace.pulse.today) < 0;
    final monthDay = dayAtNoon(month);
    final title = '${monthDay.year}年${monthDay.month}月';

    return SingleChildScrollView(
      key: const Key('calendar-page'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(27, 47, 27, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('日历',
                          style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.045,
                              color: t.ink)),
                    ),
                    FfButton(
                      label: '回到今天',
                      icon: Icons.calendar_month,
                      onPressed: onReset,
                    ),
                  ],
                ),
                const SizedBox(height: 23),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 720;
                    final grid = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(title,
                                  style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w600,
                                      color: t.ink)),
                            ),
                            FfIconButton(
                              key: const Key('prev-month'),
                              icon: Icons.chevron_left,
                              label: '上个月',
                              onPressed: () => onMonthChanged(shiftMonth(month, -1)),
                            ),
                            FfIconButton(
                              key: const Key('next-month'),
                              icon: Icons.chevron_right,
                              label: '下个月',
                              onPressed: () => onMonthChanged(shiftMonth(month, 1)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        Row(
                          children: [
                            for (final label in ['周一', '周二', '周三', '周四', '周五', '周六', '周日'])
                              Expanded(
                                child: Center(
                                  child: Text(label,
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        GridView.count(
                          key: const Key('calendar-grid'),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 7,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                          childAspectRatio: 0.92,
                          children: [
                            for (final item in workspace.calendar)
                              _DayCell(
                                item: item,
                                selected: item.date == date,
                                today: item.date == workspace.pulse.today,
                                outside: item.date.substring(0, 7) != month.substring(0, 7),
                                onTap: () => onSelect(item.date),
                              ),
                          ],
                        ),
                      ],
                    );
                    final side = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          history ? '历史记录' : date == workspace.pulse.today ? '今天' : '未来计划',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: t.accentText),
                        ),
                        const SizedBox(height: 6),
                        Text(fullDate(date),
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: t.ink)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            for (final entry in [
                              ('${record.totalTasks}', '任务'),
                              ('${record.completedTasks}', '已完成'),
                              ('${record.unfinishedTasks}', history ? '未完成' : '待完成'),
                            ])
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(entry.$1,
                                        style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w600,
                                            color: t.ink)),
                                    Text(entry.$2,
                                        style: TextStyle(fontSize: 12, color: t.muted)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (!history)
                          FfButton(
                            key: const Key('add-for-day'),
                            label: '为这天添加任务',
                            icon: Icons.add,
                            variant: FfButtonVariant.primary,
                            onPressed: () => actions.add(null),
                          ),
                        const SizedBox(height: 9),
                        if (detail.tasks.isNotEmpty)
                          Column(
                            children: [
                              for (final task in detail.tasks)
                                _ReadOnlyTaskRow(
                                  task: task,
                                  onEdit: history ? null : () => actions.edit(task),
                                  onRemove: history ? null : () => actions.remove(task),
                                ),
                            ],
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text('当天没有安排任务。',
                                style: TextStyle(color: t.muted)),
                          ),
                        if (record.totalCompletedPomodoros > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Icon(Icons.timer, size: 17, color: t.accentText),
                                const SizedBox(width: 6),
                                Text(
                                  '${record.totalCompletedPomodoros} 个番茄 · '
                                  '${timeSpan(record.totalFocusSeconds)}',
                                  style: TextStyle(color: t.muted),
                                ),
                              ],
                            ),
                          ),
                        TextButton(
                          key: const Key('calendar-thoughts'),
                          onPressed: actions.notes,
                          style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              foregroundColor: t.accentText),
                          child: Row(
                            children: [
                              const Icon(Icons.lightbulb_outline, size: 17),
                              const SizedBox(width: 7),
                              Text('番茄想法（${detail.thoughts.length}）'),
                            ],
                          ),
                        ),
                        DayActivity(data: detail),
                      ],
                    );
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          grid,
                          const SizedBox(height: 22),
                          const Divider(),
                          const SizedBox(height: 22),
                          side,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: grid),
                        const SizedBox(width: 22),
                        SizedBox(width: 290, child: side),
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

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.item,
    required this.selected,
    required this.today,
    required this.outside,
    required this.onTap,
  });

  final DayRecord item;
  final bool selected;
  final bool today;
  final bool outside;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final label = '${item.date}${item.totalTasks > 0 ? '，完成 ${item.completedTasks} / ${item.totalTasks}' : ''}';
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: TextButton(
        key: Key('day-cell-${item.date}'),
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 1),
          backgroundColor: selected ? t.wash : Colors.transparent,
          side: BorderSide(
            color: selected ? t.accent : (outside ? Colors.transparent : t.line),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          foregroundColor: outside ? t.quiet : t.ink,
        ),
        child: Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: today ? t.accent : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  item.date.substring(8),
                  style: TextStyle(
                    fontSize: 14,
                    color: today ? t.onAccent : null,
                    fontWeight: today ? FontWeight.w700 : null,
                  ),
                ),
              ),
            ),
            if (item.totalTasks > 0)
              Text(
                '${item.completedTasks}/${item.totalTasks}',
                style: TextStyle(
                  fontSize: 11,
                  color: item.completedTasks == item.totalTasks ? t.accentText : t.muted,
                  fontWeight: item.completedTasks == item.totalTasks
                      ? FontWeight.w700
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyTaskRow extends StatelessWidget {
  const _ReadOnlyTaskRow({required this.task, this.onEdit, this.onRemove});

  final Task task;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return Row(
      children: [
        Icon(
          task.status == 'completed' ? Icons.check_circle_outline : Icons.circle_outlined,
          size: 16,
          color: t.muted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.title, style: TextStyle(color: t.ink)),
              if (task.description.isNotEmpty)
                Text(task.description, style: TextStyle(fontSize: 12, color: t.muted)),
            ],
          ),
        ),
        Text(
          const {
            'completed': '已完成',
            'unfinished': '未完成',
            'todo': '待完成',
            'in_progress': '进行中',
          }[task.status] ?? '',
          style: TextStyle(fontSize: 12, color: t.muted),
        ),
        if (onEdit != null)
          FfIconButton(icon: Icons.edit_outlined, label: '编辑：${task.title}', onPressed: onEdit),
        if (onRemove != null)
          FfIconButton(icon: Icons.delete_outline, label: '删除：${task.title}', onPressed: onRemove),
      ],
    );
  }
}
