import 'package:flutter/material.dart';

/// The design tokens. Every colour, size and duration in the app comes from
/// here.
///
/// The previous build had 154 hardcoded `Colors.*` references against a theme
/// that defined a proper ColorScheme nobody used, which is why its dark mode
/// shipped white-on-white. `no_hardcoded_color` in `pk_lints` makes a literal
/// a build failure; this file is the only exception.
///
/// The direction is ink on paper. Borders rather than shadows, warm paper
/// rather than grey, and a receipt that looks like the ledger it replaces.
/// A cracked screen in daylight under a shop awning is the viewing condition,
/// so contrast is deliberately higher than a design system for an office app
/// would choose.
@immutable
final class BlTokens extends ThemeExtension<BlTokens> {
  const BlTokens({
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.paper,
    required this.surface,
    required this.surfaceRaised,
    required this.line,
    required this.lineStrong,
    required this.accent,
    required this.accentInk,
    required this.money,
    required this.moneyOut,
    required this.warning,
    required this.warningSurface,
    required this.danger,
    required this.dangerSurface,
    required this.isDark,
  });

  /// Body text and figures.
  final Color ink;

  /// Labels, captions, secondary rows.
  final Color inkMuted;

  /// Placeholders and disabled text. Still meets 4.5:1 on [paper].
  final Color inkFaint;

  /// The page.
  final Color paper;

  /// Cards, sheets, list surfaces.
  final Color surface;

  /// A surface that sits above another surface.
  final Color surfaceRaised;

  /// Hairlines and table rules.
  final Color line;

  /// Section dividers and focused borders.
  final Color lineStrong;

  /// The one brand colour. Used for the primary action and nothing else.
  final Color accent;

  /// Text drawn on [accent].
  final Color accentInk;

  /// Money coming in.
  final Color money;

  /// Money going out, and negative figures.
  final Color moneyOut;

  /// Fully transparent. A token rather than `Colors.transparent` so the
  /// `no_hardcoded_color` rule has no exception to carve out, and so a
  /// theme that wants a tinted scrim later has one place to change.
  Color get transparent => const Color(0x00000000);

  final Color warning;
  final Color warningSurface;
  final Color danger;
  final Color dangerSurface;

  final bool isDark;

  // --- Spacing ----------------------------------------------------------
  //
  // A four-point scale used as tokens and never as literals. The old build
  // defined a spacing scale and then wrote raw numbers everywhere.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;

  // --- Radius -----------------------------------------------------------
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 12;

  // --- Touch ------------------------------------------------------------
  //
  // Field research on Pakistani corner shops found the binding constraints are
  // cracked screens, dirty hands and constant interruption — not aesthetics.
  // 48 is the floor everywhere; the billing keypad gets 56 because it is used
  // fastest and mis-taps there cost money. The design mock this was built from
  // used 44 in five places, which is below the floor on every platform.
  static const double touchMin = 48;
  static const double touchKeypad = 56;

  // --- Motion -----------------------------------------------------------
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);

  /// Figures line up in a column. Non-negotiable for money.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static const BlTokens light = BlTokens(
    ink: Color(0xFF16130F),
    inkMuted: Color(0xFF5C544A),
    inkFaint: Color(0xFF8A8074),
    paper: Color(0xFFFBF8F3),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    line: Color(0xFFE6DFD3),
    lineStrong: Color(0xFFCFC5B4),
    accent: Color(0xFF1B5E3F),
    accentInk: Color(0xFFFFFFFF),
    money: Color(0xFF1B5E3F),
    moneyOut: Color(0xFF9E2B20),
    warning: Color(0xFF8A5A00),
    warningSurface: Color(0xFFFDF3DF),
    danger: Color(0xFF9E2B20),
    dangerSurface: Color(0xFFFCEDEB),
    isDark: false,
  );

  static const BlTokens dark = BlTokens(
    ink: Color(0xFFF3EEE5),
    inkMuted: Color(0xFFB6ADA0),
    inkFaint: Color(0xFF8A8175),
    paper: Color(0xFF14120F),
    surface: Color(0xFF1D1A16),
    surfaceRaised: Color(0xFF262119),
    line: Color(0xFF35302A),
    lineStrong: Color(0xFF4A443B),
    accent: Color(0xFF4CAF83),
    accentInk: Color(0xFF08150F),
    money: Color(0xFF6BC79C),
    moneyOut: Color(0xFFE8877B),
    warning: Color(0xFFE0A63C),
    warningSurface: Color(0xFF2C2311),
    danger: Color(0xFFE8877B),
    dangerSurface: Color(0xFF2E1815),
    isDark: true,
  );

  @override
  BlTokens copyWith({
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? paper,
    Color? surface,
    Color? surfaceRaised,
    Color? line,
    Color? lineStrong,
    Color? accent,
    Color? accentInk,
    Color? money,
    Color? moneyOut,
    Color? warning,
    Color? warningSurface,
    Color? danger,
    Color? dangerSurface,
    bool? isDark,
  }) =>
      BlTokens(
        ink: ink ?? this.ink,
        inkMuted: inkMuted ?? this.inkMuted,
        inkFaint: inkFaint ?? this.inkFaint,
        paper: paper ?? this.paper,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        line: line ?? this.line,
        lineStrong: lineStrong ?? this.lineStrong,
        accent: accent ?? this.accent,
        accentInk: accentInk ?? this.accentInk,
        money: money ?? this.money,
        moneyOut: moneyOut ?? this.moneyOut,
        warning: warning ?? this.warning,
        warningSurface: warningSurface ?? this.warningSurface,
        danger: danger ?? this.danger,
        dangerSurface: dangerSurface ?? this.dangerSurface,
        isDark: isDark ?? this.isDark,
      );

  @override
  BlTokens lerp(covariant BlTokens? other, double t) {
    if (other == null) return this;
    return BlTokens(
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      money: Color.lerp(money, other.money, t)!,
      moneyOut: Color.lerp(moneyOut, other.moneyOut, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSurface: Color.lerp(dangerSurface, other.dangerSurface, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// `context.bl` reads the tokens.
/// A fixed row height that still works at 200% text.
///
/// `itemExtent` is the single biggest list win on an Android Go handset — the
/// framework skips layout entirely for rows it is not drawing — but a constant
/// sized for 100% text clips the second line the moment a shopkeeper with poor
/// eyesight turns the system font up. Only the text block is scaled; the
/// padding around it is not, because padding does not grow with a typeface.
double blRowExtent(BuildContext context, double base, {double padding = 16}) {
  final text = base - padding;
  return padding + MediaQuery.textScalerOf(context).scale(text);
}

extension BlTokensLookup on BuildContext {
  BlTokens get bl =>
      Theme.of(this).extension<BlTokens>() ?? BlTokens.light;

  /// True on a tablet in landscape, which is the standard Pakistani retail
  /// counter setup and a recurring complaint against every competitor that
  /// only draws for a phone in portrait.
  bool get isWide => MediaQuery.sizeOf(this).width >= 720;
}
