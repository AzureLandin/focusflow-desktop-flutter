/// src/renderer/ui.tsx 的 Flutter 对应：通用按钮、弹窗、空态、专注记录等。
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../shared/dates.dart';
import '../shared/model.dart';
import 'theme.dart';

enum FfButtonVariant { primary, secondary, ghost, danger }

String fullDate(String day) {
  final d = dayAtNoon(day);
  const weeks = ['一', '二', '三', '四', '五', '六', '日'];
  return '${d.year}年${d.month}月${d.day}日星期${weeks[d.weekday - 1]}';
}

String timeLabel(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String timeSpan(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  return '${minutes ~/ 60} 小时 ${minutes % 60} 分钟';
}

FocusFlowTokens tokens(BuildContext context) =>
    Theme.of(context).extension<FocusFlowTokens>() ?? lightTokens;

class FfButton extends StatelessWidget {
  const FfButton({
    required this.label,
    this.onPressed,
    this.variant = FfButtonVariant.secondary,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final FfButtonVariant variant;
  final IconData? icon;


  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final foreground = switch (variant) {
      FfButtonVariant.primary => t.onAccent,
      FfButtonVariant.danger => t.onDanger,
      FfButtonVariant.ghost => t.accentText,
      FfButtonVariant.secondary => t.ink,
    };
    final background = switch (variant) {
      FfButtonVariant.primary => t.accent,
      FfButtonVariant.danger => t.danger,
      FfButtonVariant.ghost => Colors.transparent,
      FfButtonVariant.secondary => t.surface,
    };
    final border = variant == FfButtonVariant.secondary
        ? BorderSide(color: t.line)
        : null;
    return Opacity(
      opacity: onPressed == null ? 0.48 : 1,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: background,
          side: border,
          shape: RoundedRectangleBorder(borderRadius: t.smallBorder),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          minimumSize: const Size(0, 38),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17),
              const SizedBox(width: 7),
            ],
            Text(label),
          ],
        ),
      ),
    );
  }
}

class FfIconButton extends StatelessWidget {
  const FfIconButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.size = 32,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;


  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        child: Opacity(
          opacity: onPressed == null ? 0.48 : 1,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, size: 17),
            color: t.accentText,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(width: size, height: size),
          ),
        ),
      ),
    );
  }
}

class FfModal extends StatelessWidget {
  const FfModal({
    required this.title,
    required this.onClose,
    required this.child,
    super.key,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;


  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470, maxHeight: 700),
          child: Material(
            color: t.surface,
            shape: RoundedRectangleBorder(
              borderRadius: t.mediumBorder,
              side: BorderSide(color: t.line),
            ),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            color: t.ink,
                          ),
                        ),
                      ),
                      FfIconButton(
                        icon: Icons.close,
                        label: '关闭',
                        onPressed: onClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Flexible(child: SingleChildScrollView(child: child)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    this.text,
    this.action,
    super.key,
  });

  final String title;
  final String? text;
  final Widget? action;


  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return SizedBox(
      height: 217,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.grid_view_outlined, size: 24, color: t.accentText),
            const SizedBox(height: 6),
            Text(title, style: TextStyle(fontSize: 16, color: t.ink)),
            if (text != null) ...[
              const SizedBox(height: 4),
              Text(text!, style: TextStyle(color: t.muted)),
            ],
            if (action != null) ...[
              const SizedBox(height: 4),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.title, required this.count, super.key});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: t.ink)),
          const SizedBox(width: 10),
          Text('$count', style: TextStyle(fontSize: 13, color: t.quiet)),
        ],
      ),
    );
  }
}

class Logo extends StatelessWidget {
  const Logo({super.key});

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: t.accent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.menu, color: t.onAccent, size: 20),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'FocusFlow',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.04,
              color: t.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class DayActivity extends StatelessWidget {
  const DayActivity({required this.data, super.key});

  final DayData data;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return ExpansionTile(
      key: const Key('day-activity-expanded'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 3),
      iconColor: t.accentText,
      collapsedIconColor: t.accentText,
      title: Row(
        children: [
          Icon(Icons.show_chart, size: 16, color: t.accentText),
          const SizedBox(width: 6),
          Text('专注记录', style: TextStyle(color: t.accentText)),
          const SizedBox(width: 7),
          Text('${data.activity.length}', style: TextStyle(color: t.muted)),
        ],
      ),
      children: data.activity.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('当天还没有专注记录。', style: TextStyle(color: t.muted)),
              )
            ]
          : data.activity
              .map(
                (item) => ListTile(
                  dense: true,
                  leading: Icon(
                    item.reason == null ? Icons.check_circle_outline : Icons.error_outline,
                    size: 16,
                    color: item.reason == null ? t.accent : t.warn,
                  ),
                  title: Text(item.title, style: TextStyle(color: t.ink)),
                  subtitle: Text(
                    '${timeLabel(item.endedAt)} · 第 ${item.cycleIndex} 轮 · '
                    '${item.reason != null ? '已打断：${item.reason}' : timeSpan(item.focusSeconds)}',
                    style: TextStyle(color: t.muted, fontSize: 12),
                  ),
                ),
              )
              .toList(),
    );
  }
}
