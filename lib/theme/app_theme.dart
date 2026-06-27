import 'package:flutter/material.dart';

/// Shared theme so the arcade matches Sid + Amrita's main app — rose,
/// lavender, gold on a near-black canvas.
class AppTheme {
  AppTheme._();

  static const Color bg          = Color(0xFF0B0710);
  static const Color surface     = Color(0xFF15101B);
  static const Color surfaceElev = Color(0xFF1D1525);
  static const Color border      = Color(0xFF2A1F38);

  static const Color text        = Color(0xFFF6EEFB);
  static const Color textDim     = Color(0xFFB8A8C8);
  static const Color textMuted   = Color(0xFF7A6C8A);

  static const Color rose        = Color(0xFFF472B6);
  static const Color pink        = Color(0xFFEC4899);
  static const Color lavender    = Color(0xFFA78BFA);
  static const Color gold        = Color(0xFFFCD34D);
  static const Color sky         = Color(0xFF7DD3FC);
  static const Color success     = Color(0xFF34D399);
  static const Color danger      = Color(0xFFF87171);

  static const LinearGradient amrita = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [rose, pink, lavender],
  );

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: rose,
        secondary: lavender,
        tertiary: gold,
        surface: surface,
        onSurface: text,
      ),
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
      ),
    );
  }
}
