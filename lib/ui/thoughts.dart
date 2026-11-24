/// src/renderer/thoughts.tsx 的 Flutter 对应（Ctrl/Cmd+Enter 保存）。
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../shared/model.dart';
import 'tasks.dart' show RunCommand;
import 'widgets.dart';

class Thoughts extends StatefulWidget {
  const Thoughts({
    required this.notes,
    required this.editable,
    required this.run,
    super.key,
  });

  final List<Thought> notes;
  final bool editable;
  final RunCommand run;

  @override
  State<Thoughts> createState() => _ThoughtsState();
}

class _ThoughtsState extends State<Thoughts> {
  final _controller = TextEditingController();
  String? _editing;
  String? _removing;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _controller.text;
    if (content.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final ok = await widget.run(
        SaveThought(id: _editing, content: content),
      );
      if (ok && mounted) {
        _controller.clear();
        setState(() => _editing = null);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final enter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!enter) return false;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return false;
    }
    if (event is KeyRepeatEvent) return false;
    // 中文输入法组合期的 Enter 交给 TextField 处理，不在此提交。
    if (event.character == '\u000d') return false;
    _save();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.editable) ...[
          Focus(
            key: const Key('thought-key-focus'),
            onKeyEvent: (_, event) => _onKey(event)
                ? KeyEventResult.handled
                : KeyEventResult.ignored,
            child: TextField(
              key: const Key('thought-field'),
              controller: _controller,
              maxLength: 2000,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '把冒出来的想法先记在这里…',
              ),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text('Ctrl + Enter 保存', style: TextStyle(color: t.muted, fontSize: 12)),
              const Spacer(),
              if (_editing != null)
                FfButton(
                  label: '取消',
                  variant: FfButtonVariant.ghost,
                  onPressed: () {
                    _controller.clear();
                    setState(() => _editing = null);
                  },
                ),
              FfButton(
                key: const Key('thought-save'),
                label: _editing == null ? '记录' : '保存修改',
                variant: FfButtonVariant.primary,
                onPressed: _controller.text.trim().isEmpty || _busy ? null : _save,
              ),
            ],
          ),
        ],
        if (widget.notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Text(
              '当天还没有番茄想法。',
              style: TextStyle(color: t.muted),
            ),
          )
        else
          for (final note in widget.notes)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(note.content),
              subtitle: Row(
                children: [
                  Text(timeLabel(note.createdAt),
                      style: TextStyle(color: t.muted, fontSize: 12)),
                  const Spacer(),
                  if (widget.editable && _removing != note.id) ...[
                    FfIconButton(
                      key: Key('thought-edit-${note.id}'),
                      icon: Icons.edit_outlined,
                      label: '编辑想法',
                      onPressed: () {
                        setState(() {
                          _editing = note.id;
                          _controller.text = note.content;
                          _removing = null;
                        });
                      },
                    ),
                    FfIconButton(
                      key: Key('thought-remove-${note.id}'),
                      icon: Icons.delete_outline,
                      label: '删除想法',
                      onPressed: () => setState(() => _removing = note.id),
                    ),
                  ] else if (widget.editable) ...[
                    FfButton(
                      label: '取消',
                      variant: FfButtonVariant.ghost,
                      onPressed: () => setState(() => _removing = null),
                    ),
                    FfButton(
                      label: '删除这条想法',
                      variant: FfButtonVariant.danger,
                      onPressed: () async {
                        if (await widget.run(DeleteThought(id: note.id))) {
                          if (!mounted) return;
                          setState(() {
                            _removing = null;
                            if (_editing == note.id) {
                              _editing = null;
                              _controller.clear();
                            }
                          });
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}
