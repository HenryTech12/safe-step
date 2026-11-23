import 'package:material_ui/material_ui.dart';

/// High-contrast dark theme: near-black background, white text, yellow accent
/// (yellow on black is the most legible pairing for many low-vision users).
class SafeStepColors {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF121212);
  static const text = Color(0xFFFFFFFF);
  static const accent = Color(0xFFFFD600);
  static const danger = Color(0xFFFF5252);
  static const ok = Color(0xFF69F0AE);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    surface: SafeStepColors.surface,
    primary: SafeStepColors.accent,
    onPrimary: Colors.black,
    onSurface: SafeStepColors.text,
    error: SafeStepColors.danger,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: SafeStepColors.background,
    textTheme: const TextTheme(
      displaySmall: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: SafeStepColors.text),
      headlineMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: SafeStepColors.text),
      titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: SafeStepColors.text),
      bodyLarge: TextStyle(fontSize: 22, color: SafeStepColors.text),
    ),
  );
}
