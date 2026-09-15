import 'dart:ui';

import 'package:flutter/material.dart';

/// KIU brand green. Anchors both schemes; every other role is derived from it
/// so light and dark stay the same family rather than two unrelated palettes.
const Color kiuGreen = Color(0xFF176B45);

/// Warm accent used for "scheduled but not started" states. Shared with the
/// home-screen widget's amber accent bar so the two surfaces agree.
const Color kiuAmber = Color(0xFF9A6B00);

/// [kiuGreen] lightened for dark surfaces. The brand green is a deep 4.5:1
/// green chosen against white; on black it reads as near-black itself. Mirrors
/// `WidgetTheme.brand` on the native side, which lightens for the same reason.
const Color kiuGreenDark = Color(0xFF6FD3A0);

/// Brand green resolved for the surface it will sit on. State that means
/// "this lesson has started / this call is armed" uses this rather than
/// `colorScheme.primary`, which is deliberately neutral now.
Color brandGreen(Brightness brightness) =>
    brightness == Brightness.dark ? kiuGreenDark : kiuGreen;

/// Neutral surfaces. The nav bar and settings read as one family only if the
/// page behind them is a true white/black rather than a green-tinted grey —
/// a seeded surface put a faint green wash behind every row.
const Color lightSurface = Color(0xFFFFFFFF);
const Color darkSurface = Color(0xFF000000);

/// Raised surface in dark mode. Pure black for the page, one step up for the
/// things that sit on it (sheets, cards), so they separate without a border.
const Color darkElevated = Color(0xFF121212);

/// Hairline between rows. The only separator in the flat list, so it carries
/// the whole structure.
const Color lightSeparator = Color(0xFFDBDBDB);
const Color darkSeparator = Color(0xFF262626);

/// Secondary text and inactive glyphs.
const Color lightSecondaryText = Color(0xFF737373);
const Color darkSecondaryText = Color(0xFFA8A8A8);

/// What `primary` resolves to: near-black on light, near-white on dark. Every
/// control that used to be green (switches, chips, slider, captions) reads
/// this role, so they all go neutral without touching their call sites.
const Color lightInk = Color(0xFF262626);
const Color darkInk = Color(0xFFF5F5F5);

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
  final dark = brightness == Brightness.dark;
  // The seed still sets the family, but every role the chrome actually reads
  // is pinned to a neutral here. Doing it once on the scheme is what keeps
  // green out of the switches, chips, slider and section captions without
  // editing a dozen call sites — and what makes a later palette change one
  // edit rather than a sweep.
  //
  // kiuGreen is NOT retired: it still marks the brand and lesson state, which
  // is why it is passed explicitly at those few call sites rather than ridden
  // in on `primary`.
  return base.copyWith(
    primary: dark ? darkInk : lightInk,
    onPrimary: dark ? darkSurface : lightSurface,
    // Tinted containers were the other green carrier (the speed read-out
    // pill). Neutral grey keeps them legible without the accent.
    primaryContainer: dark ? const Color(0xFF2A2A2A) : const Color(0xFFEFEFEF),
    onPrimaryContainer: dark ? darkInk : lightInk,
    // ChoiceChip and SegmentedButton paint their *selected* state from
    // secondaryContainer, not primary — so leaving this seeded kept a green
    // speed chip and a green theme segment sitting in an otherwise neutral
    // sheet. Selection reads as a filled grey, the way the nav bar's capsule
    // does.
    secondary: dark ? darkInk : lightInk,
    onSecondary: dark ? darkSurface : lightSurface,
    secondaryContainer: dark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFE8E8E8),
    onSecondaryContainer: dark ? darkInk : lightInk,
    // fromSeed derives every surface tone from the seed, so each one carries a
    // faint green wash. They are pinned as a set rather than individually —
    // missing one shows up as a single off-colour panel (surfaceContainer is
    // the nav bar's, surfaceTint is what M3 blends into elevated surfaces).
    surfaceTint: Colors.transparent,
    surfaceDim: dark ? darkSurface : const Color(0xFFEDEDED),
    surfaceBright: dark ? const Color(0xFF232323) : lightSurface,
    surfaceContainerLowest: dark ? Colors.black : lightSurface,
    surfaceContainer: dark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
    surfaceContainerLow: dark ? darkElevated : lightSurface,
    surfaceContainerHigh: dark
        ? const Color(0xFF1C1C1C)
        : const Color(0xFFFAFAFA),
    surfaceContainerHighest: dark
        ? const Color(0xFF232323)
        : const Color(0xFFF1F1F1),
    onSurface: dark ? const Color(0xFFF5F5F5) : const Color(0xFF0F0F0F),
    onSurfaceVariant: dark ? darkSecondaryText : lightSecondaryText,
    outline: dark ? const Color(0xFF545454) : const Color(0xFF8E8E8E),
    outlineVariant: dark ? darkSeparator : lightSeparator,
    // Snackbars and tooltips invert; the seeded pair tinted both green.
    inverseSurface: dark ? const Color(0xFFF5F5F5) : const Color(0xFF1A1A1A),
    onInverseSurface: dark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
    inversePrimary: dark ? lightInk : darkInk,
    // fromSeed's tertiary lands on a blue-ish hue that fights the green; pin it
    // to the amber the native widget already uses for scheduled lessons.
    tertiary: dark ? const Color(0xFFE3B85F) : kiuAmber,
    tertiaryContainer: dark ? const Color(0xFF3D2E00) : const Color(0xFFFFEFC9),
    onTertiaryContainer: dark
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
      // The sheet is the settings surface itself, so it takes the plain
      // surface rather than a raised container: on light that is the pure
      // white the flat list needs.
      backgroundColor: colors.surface,
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
