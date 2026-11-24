/// src/renderer/settings.tsx 的 Flutter 对应。
library;

import 'package:material_ui/material_ui.dart';

import '../shared/model.dart';
import 'tasks.dart' show RunCommand;
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.settings,
    required this.dataPath,
    required this.run,
    required this.backup,
    this.onThemePreview,
    super.key,
  });

  final Settings settings;
  final String dataPath;
  final RunCommand run;
  final Future<void> Function(String action) backup;
  final void Function(AppTheme theme)? onThemePreview;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Settings _draft;
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _draft = widget.settings;
    _controllers = {
      for (final key in const ['focusMinutes', 'shortMinutes', 'longMinutes', 'longEvery'])
        key: TextEditingController(text: '${_valueOf(_draft, key)}'),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int _valueOf(Settings settings, String key) => switch (key) {
        'focusMinutes' => settings.focusMinutes,
        'shortMinutes' => settings.shortMinutes,
        'longMinutes' => settings.longMinutes,
        _ => settings.longEvery,
      };

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _draft = widget.settings;
      for (final entry in _controllers.entries) {
        final value = '${_valueOf(_draft, entry.key)}';
        if (entry.value.text != value) entry.value.text = value;
      }
    }
  }

  bool get _changed => _draft != widget.settings;

  void _update(SettingsUpdater updater) => setState(() => _draft = updater(_draft));

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final timings = [
      ('focusMinutes', '专注时长', 1, 120, '分钟'),
      ('shortMinutes', '短休息', 1, 60, '分钟'),
      ('longMinutes', '长休息', 15, 30, '分钟'),
      ('longEvery', '长休息间隔', 1, 12, '个番茄'),
    ];
    final switches = [
      (true, '会话结束后仍提示长休息', '当最后一个番茄刚好达到长休息间隔时显示提示。'),
      (false, '提示音', '每个专注或休息阶段结束时播放。'),
      (false, '系统通知', '阶段结束时发送系统通知。'),
    ];

    return SingleChildScrollView(
      key: const Key('settings-page'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(27, 47, 27, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('设置',
                    style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.045,
                        color: t.ink)),
                const SizedBox(height: 23),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('番茄时钟',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: t.ink)),
                      const SizedBox(height: 13),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth < 720 ? 1 : 2;
                          return Wrap(
                            spacing: 22,
                            runSpacing: 9,
                            children: [
                              for (final entry in timings)
                                SizedBox(
                                  width: columns == 2
                                      ? (constraints.maxWidth - 22) / 2
                                      : constraints.maxWidth,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(entry.$2,
                                            style: TextStyle(color: t.ink)),
                                      ),
                                      SizedBox(
                                        width: 64,
                                        child: TextField(
                                          key: Key('setting-${entry.$1}'),
                                          controller: _controllers[entry.$1],
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          decoration: InputDecoration(
                                            isDense: true,
                                            suffixText: entry.$5,
                                            contentPadding:
                                                const EdgeInsets.symmetric(horizontal: 6),
                                          ),
                                          onChanged: (value) {
                                            final parsed = int.tryParse(value);
                                            if (parsed == null) return;
                                            _update((s) => switch (entry.$1) {
                                                  'focusMinutes' =>
                                                    s.copyWith(focusMinutes: parsed),
                                                  'shortMinutes' =>
                                                    s.copyWith(shortMinutes: parsed),
                                                  'longMinutes' =>
                                                    s.copyWith(longMinutes: parsed),
                                                  _ => s.copyWith(longEvery: parsed),
                                                });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      for (final i in [0, 1, 2])
                        _SwitchRow(
                          key: Key('setting-${i == 0 ? 'finalLongBreak' : i == 1 ? 'sound' : 'notifications'}'),
                          title: switches[i].$2,
                          detail: switches[i].$3,
                          value: i == 0
                              ? _draft.finalLongBreak
                              : i == 1
                                  ? _draft.sound
                                  : _draft.notifications,
                          onChanged: (value) => _update((s) => switch (i) {
                                0 => s.copyWith(finalLongBreak: value),
                                1 => s.copyWith(sound: value),
                                _ => s.copyWith(notifications: value),
                              }),
                        ),
                      const SizedBox(height: 17),
                      Text('外观',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: t.ink)),
                      const SizedBox(height: 13),
                      Row(
                        children: [
                          Text('主题', style: TextStyle(color: t.ink)),
                          const Spacer(),
                          DropdownButton<AppTheme>(
                            key: const Key('setting-theme'),
                            value: _draft.theme,
                            items: const [
                              DropdownMenuItem(value: AppTheme.system, child: Text('跟随系统')),
                              DropdownMenuItem(value: AppTheme.light, child: Text('浅色')),
                              DropdownMenuItem(value: AppTheme.dark, child: Text('深色')),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              _update((s) => s.copyWith(theme: value));
                              widget.onThemePreview?.call(value);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 17),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FfButton(
                          key: const Key('settings-save'),
                          label: '保存设置',
                          icon: Icons.save,
                          variant: FfButtonVariant.primary,
                          onPressed: !_changed ? null : () => widget.run(
                            SettingsCommand(settings: _draft),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 23),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('本地数据',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: t.ink)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.storage, size: 16, color: t.muted),
                          const SizedBox(width: 5),
                          Text('SQLite 数据库', style: TextStyle(color: t.muted)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: t.wash,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(widget.dataPath,
                            style: TextStyle(color: t.ink, fontSize: 12)),
                      ),
                      const SizedBox(height: 13),
                      Wrap(
                        spacing: 8,
                        children: [
                          FfButton(
                            key: const Key('backup-export'),
                            label: '导出 JSON 备份',
                            icon: Icons.download,
                            onPressed: () => widget.backup('export'),
                          ),
                          FfButton(
                            key: const Key('backup-import'),
                            label: '恢复 JSON 备份',
                            icon: Icons.upload,
                            onPressed: () => widget.backup('import'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

typedef SettingsUpdater = Settings Function(Settings settings);

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String detail;
  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.line))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontWeight: FontWeight.w600, color: t.ink)),
                Text(detail, style: TextStyle(fontSize: 12, color: t.muted)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
