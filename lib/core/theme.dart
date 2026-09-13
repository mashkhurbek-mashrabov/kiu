import 'dart:ui';

import 'package:flutter/material.dart';

/// KIU brand green. Anchors both schemes; every other role is derived from it
/// so light and dark stay the same family rather than two unrelated palettes.
const Color kiuGreen = Color(0xFF176B45);

/// Warm accent used for "scheduled but not started" states. Shared with the
/// home-screen widget's amber accent bar so the two surfaces agree.
const Color kiuAmber = Color(0xFF9A6B00);

const Color lightSurface = Color(0xFFF6F8F5);
const Color darkSurface = Color(0xFF14181A);

/// Brightness the app renders with. Reads the platform dispatcher rather than
/// MediaQuery so background isolates and `initState` can resolve it too.
bool resolveDark(ThemeMode mode) => switch (mode) {
  ThemeMode.dark => true,
  ThemeMode.light => false,
  ThemeMode.system =>
    PlatformDispatcher.instance.platformBrightness == Brightness.dark,
};

Color surfaceFor(Brightness brightness) =>
    brightness == Brightness.dark ? darkSurface : lightSurface;

ColorScheme _scheme(Brightness brightness) {
  final base = ColorScheme.fromSeed(
    seedColor: kiuGreen,
    brightness: brightness,
    surface: surfaceFor(brightness),
  );
  // fromSeed's tertiary lands on a blue-ish hue that fights the green; pin it
  // to the amber the native widget already uses for scheduled lessons.
  return base.copyWith(
    tertiary: brightness == Brightness.dark
        ? const Color(0xFFE3B85F)
        : kiuAmber,
    tertiaryContainer: brightness == Brightness.dark
        ? const Color(0xFF3D2E00)
        : const Color(0xFFFFEFC9),
    onTertiaryContainer: brightness == Brightness.dark
        ? const Color(0xFFFFDF9C)
        : const Color(0xFF2E2100),
  );
}

ThemeData kiuTheme(Brightness brightness) {
  final colors = _scheme(brightness);
  return ThemeData(
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    useMaterial3: true,
    // One radius vocabulary across the app: 16 for containers, 28 for sheets.
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    bottomAppBarTheme: BottomAppBarThemeData(
      color: colors.surfaceContainer,
      elevation: 0,
      height: 60,
      padding: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant.withValues(alpha: 0.6),
      space: 1,
      thickness: 1,
    ),
    chipTheme: ChipThemeData(
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: colors.outlineVariant),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.inverseSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: TextStyle(color: colors.onInverseSurface, fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.symmetric(horizontal: 24),
    ),
  );
}
