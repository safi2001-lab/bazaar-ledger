import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Builds the Material theme from [BlTokens].
///
/// Both themes come from the same token set, so dark mode cannot drift out of
/// step with light the way the previous build's did — it shipped white cards
/// on a white background because the ColorScheme was defined and then ignored.
ThemeData blTheme({required bool dark}) {
  final t = dark ? BlTokens.dark : BlTokens.light;

  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: t.accent,
    onPrimary: t.accentInk,
    secondary: t.accent,
    onSecondary: t.accentInk,
    error: t.danger,
    onError: dark ? const Color(0xFF2E1815) : Colors.white,
    surface: t.surface,
    onSurface: t.ink,
    surfaceContainerHighest: t.surfaceRaised,
    outline: t.lineStrong,
    outlineVariant: t.line,
  );

  TextStyle body(double size, FontWeight weight, Color colour) => TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: colour,
        height: 1.35,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.paper,
    canvasColor: t.paper,
    dividerColor: t.line,
    extensions: [t],

    // Ink on paper: the page is separated by rules, not by drop shadows.
    cardTheme: CardThemeData(
      color: t.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        side: BorderSide(color: t.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),

    appBarTheme: AppBarTheme(
      backgroundColor: t.paper,
      foregroundColor: t.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: body(19, FontWeight.w700, t.ink),
      shape: Border(bottom: BorderSide(color: t.line)),
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),

    textTheme: TextTheme(
      displaySmall: body(30, FontWeight.w700, t.ink),
      headlineMedium: body(24, FontWeight.w700, t.ink),
      headlineSmall: body(20, FontWeight.w700, t.ink),
      titleLarge: body(18, FontWeight.w700, t.ink),
      titleMedium: body(16, FontWeight.w600, t.ink),
      titleSmall: body(14, FontWeight.w600, t.inkMuted),
      bodyLarge: body(16, FontWeight.w400, t.ink),
      bodyMedium: body(15, FontWeight.w400, t.ink),
      bodySmall: body(13, FontWeight.w400, t.inkMuted),
      labelLarge: body(15, FontWeight.w600, t.ink),
      labelMedium: body(13, FontWeight.w600, t.inkMuted),
      labelSmall: body(12, FontWeight.w500, t.inkFaint),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BlTokens.space4,
        vertical: BlTokens.space3,
      ),
      hintStyle: body(15, FontWeight.w400, t.inkFaint),
      labelStyle: body(14, FontWeight.w500, t.inkMuted),
      floatingLabelStyle: body(13, FontWeight.w600, t.accent),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        borderSide: BorderSide(color: t.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        borderSide: BorderSide(color: t.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        borderSide: BorderSide(color: t.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        borderSide: BorderSide(color: t.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        borderSide: BorderSide(color: t.danger, width: 2),
      ),
    ),

    listTileTheme: ListTileThemeData(
      minVerticalPadding: BlTokens.space3,
      iconColor: t.inkMuted,
      textColor: t.ink,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.ink,
      contentTextStyle: body(15, FontWeight.w500, t.paper),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(BlTokens.radiusLg),
        ),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BlTokens.radiusLg),
        side: BorderSide(color: t.line),
      ),
    ),

    // Every tap target clears 48. Anything smaller fails on a cracked screen
    // with a wet thumb, which is the actual operating condition.
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
  );
}
