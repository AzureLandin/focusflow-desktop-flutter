/// src/renderer/tasks.tsx 的 Flutter 对应。
library;

import 'package:material_ui/material_ui.dart';

import '../shared/model.dart';
import 'widgets.dart';

typedef RunCommand = Future<bool> Function(Command command);

class TaskActions {
  const TaskActions({
    required this.run,
    required this.busy,
    required this.add,
    required this.edit,
    required this.remove,
    required this.start,
    required this.notes,
  });

  final RunCommand run;
  final bool busy;
  final void Function(String? title) add;
  final void Function(Task task) edit;
  final void Function(Task task) remove;
  final void Function(Task? task) start;
  final VoidCallback notes;
}

class QuickAdd extends StatefulWidget {
  const QuickAdd({required this.date, required this.actions, super.key});

  final String date;
  final TaskActions actions;

  @override
  State<QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<QuickAdd> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _submitting) return;
    _submitting = true;
    try {
      final ok = await widget.actions.run(
        SaveTask(
          task: TaskInput(
            title: title,
            description: '',
            scheduledDate: widget.date,
            pomodoroEnabled: false,
            plannedPomodoros: 1,
          ),
        ),
      );
      if (ok) _controller.clear();
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return Container(
      key: const Key('quick-add'),
      constraints: const BoxConstraints(minHeight: 56),
      margin: const EdgeInsets.only(top: 20, bottom: 24),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: t.mediumBorder,
      ),
      child: Row(
        children: [
          Icon(Icons.add, color: t.accentText, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('quick-add-field'),
              controller: _controller,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: '添加任务，按 Enter 保存',
                border: InputBorder.none,
                counterText: '',
                isDense: true,
              ),
              onSubmitted: (_) => _add(),
            ),
          ),
          FfButton(
            label: '详细添加',
            variant: FfButtonVariant.ghost,
            onPressed: () => widget.actions.add(_controller.text.trim().isEmpty
                ? null
                : _controller.text.trim()),
          ),
          const SizedBox(width: 5),
          FfButton(
            label: '添加',
            variant: FfButtonVariant.primary,
            onPressed: _controller.text.trim().isEmpty ? null : _add,
          ),
        ],
      ),
    );
  }
}

class TaskRows extends StatelessWidget {
  const TaskRows({
    required this.tasks,
    required this.actions,
    this.allowStart = true,
    super.key,
  });

  final List<Task> tasks;
  final TaskActions actions;
  final bool allowStart;


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < tasks.length; index++)
          _TaskRow(
            task: tasks[index],
            index: index,
            total: tasks.length,
            actions: actions,
            allowStart: allowStart,
          ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.index,
    required this.total,
    required this.actions,
    required this.allowStart,
  });

  final Task task;
  final int index;
  final int total;
  final TaskActions actions;
  final bool allowStart;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final done = task.status == 'completed';
    final checkLabel = '${done ? '撤销完成' : '完成'}：${task.title}';
    return Container(
      constraints: const BoxConstraints(minHeight: 61),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: checkLabel,
            button: true,
            enabled: !actions.busy,
            child: SizedBox(
              width: 20,
              height: 20,
              child: TextButton(
                key: Key('task-check-${task.id}'),
                onPressed: actions.busy
                    ? null
                    : () => actions.run(ToggleTask(id: task.id)),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: done ? t.accent : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: done ? t.accent : t.quiet),
                  ),
                ),
                child: done
                    ? Icon(Icons.check, size: 15, color: t.onAccent)
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: done ? t.muted : t.ink,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (task.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(task.description, style: TextStyle(color: t.muted)),
                ],
                const SizedBox(height: 5),
                Row(
                  children: [
                    Semantics(
                      label: '番茄时钟：${task.title}',
                      button: true,
                      child: InkWell(
                        onTap: actions.busy
                            ? null
                            : () => actions.run(
                                  SaveTask(
                                    id: task.id,
                                    task: TaskInput(
                                      title: task.title,
                                      description: task.description,
                                      scheduledDate: task.scheduledDate,
                                      pomodoroEnabled: task.pomodoroEnabled == 0,
                                      plannedPomodoros: task.plannedPomodoros,
                                    ),
                                  ),
                                ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(color: t.line),
                            borderRadius: BorderRadius.circular(6),
                            color: task.pomodoroEnabled == 1 ? t.wash : null,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.timer, size: 14, color: t.accentText),
                              const SizedBox(width: 4),
                              Text('番茄', style: TextStyle(fontSize: 12, color: t.accentText)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (task.pomodoroEnabled == 1) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${task.completedPomodoros} / ${task.plannedPomodoros}',
                        style: TextStyle(fontSize: 12, color: t.muted),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (!done && task.pomodoroEnabled == 1 && allowStart)
            FfButton(
              label: '开始专注',
              variant: FfButtonVariant.ghost,
              onPressed: () => actions.start(task),
            ),
          FfIconButton(
            key: Key('move-up-${task.id}'),
            icon: Icons.arrow_upward,
            label: '上移：${task.title}',
            onPressed: actions.busy || index == 0
                ? null
                : () => actions.run(MoveTask(id: task.id, direction: -1)),
          ),
          FfIconButton(
            key: Key('move-down-${task.id}'),
            icon: Icons.arrow_downward,
            label: '下移：${task.title}',
            onPressed: actions.busy || index == total - 1
                ? null
                : () => actions.run(MoveTask(id: task.id, direction: 1)),
          ),
          FfIconButton(
            key: Key('edit-${task.id}'),
            icon: Icons.edit_outlined,
            label: '编辑：${task.title}',
            onPressed: () => actions.edit(task),
          ),
          FfIconButton(
            key: Key('delete-${task.id}'),
            icon: Icons.delete_outline,
            label: '删除：${task.title}',
            onPressed: () => actions.remove(task),
          ),
        ],
      ),
    );
  }
}

class TaskForm extends StatefulWidget {
  const TaskForm({
    required this.task,
    required this.title,
    required this.date,
    required this.minimum,
    required this.onSave,
    required this.onClose,
    super.key,
  });

  final Task? task;
  final String? title;
  final String date;
  final String minimum;
  final Future<bool> Function(TaskInput input) onSave;
  final VoidCallback onClose;

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _date;
  late final TextEditingController _plan;
  late bool _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.task?.title ?? widget.title ?? '');
    _description = TextEditingController(text: widget.task?.description ?? '');
    _date = TextEditingController(text: widget.task?.scheduledDate ?? widget.date);
    _plan = TextEditingController(
      text: '${widget.task?.plannedPomodoros ?? 1}',
    );
    _enabled = widget.task?.pomodoroEnabled == 1;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _date.dispose();
    _plan.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await widget.onSave(
        TaskInput(
          title: _title.text,
          description: _description.text,
          scheduledDate: _date.text,
          pomodoroEnabled: _enabled,
          plannedPomodoros: int.tryParse(_plan.text) ?? 1,
        ),
      );
      if (ok) widget.onClose();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return FfModal(
      title: widget.task == null ? '添加任务' : '编辑任务',
      onClose: widget.onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('task-form-title'),
            controller: _title,
            autofocus: true,
            maxLength: 200,
            decoration: const InputDecoration(labelText: '任务名称', hintText: '输入任务名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '描述（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _date,
            decoration: InputDecoration(
              labelText: '计划日期',
              helperText: '不早于 ${widget.minimum}',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value ?? false),
              ),
              Text('启用番茄时钟', style: TextStyle(color: t.ink)),
              if (_enabled) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _plan,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '计划番茄数'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FfButton(label: '取消', onPressed: widget.onClose),
              const SizedBox(width: 8),
              FfButton(
                key: const Key('task-form-save'),
                label: '保存任务',
                variant: FfButtonVariant.primary,
                onPressed: _busy ? null : _save,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FocusForm extends StatefulWidget {
  const FocusForm({
    required this.task,
    required this.run,
    required this.onClose,
    super.key,
  });

  final Task? task;
  final RunCommand run;
  final VoidCallback onClose;

  @override
  State<FocusForm> createState() => _FocusFormState();
}

class _FocusFormState extends State<FocusForm> {
  late final TextEditingController _title;
  late final TextEditingController _count;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _count = TextEditingController(
      text: widget.task == null
          ? '1'
          : '${widget.task!.plannedPomodoros - widget.task!.completedPomodoros < 1 ? 1 : widget.task!.plannedPomodoros - widget.task!.completedPomodoros}',
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await widget.run(
        Start(
          taskId: widget.task?.id,
          title: widget.task == null ? _title.text : null,
          count: int.tryParse(_count.text) ?? 1,
        ),
      );
      if (ok) widget.onClose();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FfModal(
      title: widget.task == null ? '快速开始专注' : '开始任务专注',
      onClose: widget.onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.task == null)
            TextField(
              key: const Key('focus-form-title'),
              controller: _title,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '这次想专注做什么？',
                hintText: '例如：读完一章书',
              ),
            )
          else
            Text(
              widget.task!.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('focus-form-count'),
            controller: _count,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '本次计划番茄数'),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FfButton(label: '取消', onPressed: widget.onClose),
              const SizedBox(width: 8),
              FfButton(
                label: '开始计时',
                variant: FfButtonVariant.primary,
                icon: Icons.play_arrow,
                onPressed: _busy ? null : _start,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
