import 'dart:ui';

import 'package:flutter/material.dart';

const Color lightSurface = Color(0xFFF2F1EA);
const Color darkSurface = Color(0xFF2B2939);

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

ThemeData kiuTheme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF176B45),
    brightness: brightness,
    surface: surfaceFor(brightness),
  ),
  scaffoldBackgroundColor: surfaceFor(brightness),
  useMaterial3: true,
);
