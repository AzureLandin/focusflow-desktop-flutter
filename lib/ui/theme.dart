import 'package:material_ui/material_ui.dart';

/// src/renderer/styles.css 中的设计令牌（浅色 / 深色两套）。
///
/// 这里只做骨架映射：CSS 变量逐一落到 [FocusFlowTokens]，
/// 同时映射到 [ColorScheme] 供标准 Material 组件使用。
@immutable
class FocusFlowTokens extends ThemeExtension<FocusFlowTokens> {
  const FocusFlowTokens({
    required this.paper,
    required this.side,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.quiet,
    required this.line,
    required this.wash,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.accentHover,
    required this.focusCard,
    required this.onCard,
    required this.cardMuted,
    required this.warn,
    required this.danger,
    required this.onDanger,
    this.smallRadius = 8,
    this.mediumRadius = 12,
    this.largeRadius = 18,
  });

  final Color paper;
  final Color side;
  final Color surface;
  final Color ink;
  final Color muted;
  final Color quiet;
  final Color line;
  final Color wash;
  final Color accent;
  final Color accentText;
  final Color onAccent;
  final Color accentHover;
  final Color focusCard;
  final Color onCard;
  final Color cardMuted;
  final Color warn;
  final Color danger;
  final Color onDanger;
  final double smallRadius;
  final double mediumRadius;
  final double largeRadius;

  BorderRadius get smallBorder => BorderRadius.all(Radius.circular(smallRadius));
  BorderRadius get mediumBorder => BorderRadius.all(Radius.circular(mediumRadius));
  BorderRadius get largeBorder => BorderRadius.all(Radius.circular(largeRadius));

  @override
  FocusFlowTokens copyWith({
    Color? paper,
    Color? side,
    Color? surface,
    Color? ink,
    Color? muted,
    Color? quiet,
    Color? line,
    Color? wash,
    Color? accent,
    Color? accentText,
    Color? onAccent,
    Color? accentHover,
    Color? focusCard,
    Color? onCard,
    Color? cardMuted,
    Color? warn,
    Color? danger,
    Color? onDanger,
    double? smallRadius,
    double? mediumRadius,
    double? largeRadius,
  }) {
    return FocusFlowTokens(
      paper: paper ?? this.paper,
      side: side ?? this.side,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      muted: muted ?? this.muted,
      quiet: quiet ?? this.quiet,
      line: line ?? this.line,
      wash: wash ?? this.wash,
      accent: accent ?? this.accent,
      accentText: accentText ?? this.accentText,
      onAccent: onAccent ?? this.onAccent,
      accentHover: accentHover ?? this.accentHover,
      focusCard: focusCard ?? this.focusCard,
      onCard: onCard ?? this.onCard,
      cardMuted: cardMuted ?? this.cardMuted,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      smallRadius: smallRadius ?? this.smallRadius,
      mediumRadius: mediumRadius ?? this.mediumRadius,
      largeRadius: largeRadius ?? this.largeRadius,
    );
  }

  @override
  FocusFlowTokens lerp(FocusFlowTokens? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    double num(double a, double b) => a + (b - a) * t;
    return FocusFlowTokens(
      paper: mix(paper, other.paper),
      side: mix(side, other.side),
      surface: mix(surface, other.surface),
      ink: mix(ink, other.ink),
      muted: mix(muted, other.muted),
      quiet: mix(quiet, other.quiet),
      line: mix(line, other.line),
      wash: mix(wash, other.wash),
      accent: mix(accent, other.accent),
      accentText: mix(accentText, other.accentText),
      onAccent: mix(onAccent, other.onAccent),
      accentHover: mix(accentHover, other.accentHover),
      focusCard: mix(focusCard, other.focusCard),
      onCard: mix(onCard, other.onCard),
      cardMuted: mix(cardMuted, other.cardMuted),
      warn: mix(warn, other.warn),
      danger: mix(danger, other.danger),
      onDanger: mix(onDanger, other.onDanger),
      smallRadius: num(smallRadius, other.smallRadius),
      mediumRadius: num(mediumRadius, other.mediumRadius),
      largeRadius: num(largeRadius, other.largeRadius),
    );
  }
}

const lightTokens = FocusFlowTokens(
  paper: Color(0xFFF8F7F2),
  side: Color(0xFFEEEFE7),
  surface: Color(0xFFFDFCF8),
  ink: Color(0xFF242D28),
  muted: Color(0xFF56645A),
  quiet: Color(0xFF657167),
  line: Color(0xFFDCE1D7),
  wash: Color(0xFFE8EEE4),
  accent: Color(0xFF315F4B),
  accentText: Color(0xFF295641),
  onAccent: Color(0xFFFFFFFF),
  accentHover: Color(0xFF244C3B),
  focusCard: Color(0xFF284B3E),
  onCard: Color(0xFFF7F7E9),
  cardMuted: Color(0xFFDFEBDB),
  warn: Color(0xFF902F29),
  danger: Color(0xFFA33A33),
  onDanger: Color(0xFFFFFFFF),
);

const darkTokens = FocusFlowTokens(
  paper: Color(0xFF212723),
  side: Color(0xFF252E28),
  surface: Color(0xFF2B342D),
  ink: Color(0xFFEDF0E8),
  muted: Color(0xFFB6C6B8),
  quiet: Color(0xFFA3B5A7),
  line: Color(0xFF414E44),
  wash: Color(0xFF324539),
  accent: Color(0xFF9BCCAD),
  accentText: Color(0xFFB0DDC0),
  onAccent: Color(0xFF16281F),
  accentHover: Color(0xFFB5DBC2),
  focusCard: Color(0xFF2C4A3E),
  onCard: Color(0xFFF7F7E9),
  cardMuted: Color(0xFFE0ECDB),
  warn: Color(0xFFF9A49E),
  danger: Color(0xFF9C3029),
  onDanger: Color(0xFFFFFFFF),
);

/// 由 CSS 变量映射出的 [ThemeData]。浅/深各一套，themeMode 决定用哪套。
ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final t = dark ? darkTokens : lightTokens;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.wash,
    onPrimaryContainer: t.accentText,
    secondary: t.focusCard,
    onSecondary: t.onCard,
    secondaryContainer: t.cardMuted,
    onSecondaryContainer: t.focusCard,
    tertiary: t.accentHover,
    onTertiary: t.onAccent,
    error: t.danger,
    onError: t.onDanger,
    surface: t.surface,
    onSurface: t.ink,
    surfaceContainer: t.side,
    onSurfaceVariant: t.muted,
    outline: t.line,
    outlineVariant: t.wash,
    shadow: t.line,
    scrim: t.ink,
    inverseSurface: t.ink,
    onInverseSurface: t.paper,
    inversePrimary: t.accentText,
    surfaceTint: t.accent,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.paper,
    dividerColor: t.line,
    hintColor: t.quiet,
    extensions: <ThemeExtension<dynamic>>{t},
    fontFamily: 'Segoe UI Variable Text',
    textTheme: TextTheme(
      bodyMedium: TextStyle(height: 1.55, color: t.ink),
      titleLarge: TextStyle(height: 1.17, color: t.ink),
    ),
  );
}
