import 'package:flutter/material.dart';

class AppTheme {
  static const Color studioBackground = Color(0xFF090D16);
  static const Color panelSurface = Color(0xFF111827);
  static const Color cardSurface = Color(0xFF1E293B);
  static const Color borderSubtle = Color(0xFF334155);
  static const Color primaryAccent = Color(0xFF38BDF8);
  static const Color successEmerald = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color dangerRose = Color(0xFFEF4444);

  static const List<int> keyColorPalette = <int>[
    0xFF38BDF8, // Sky Blue
    0xFFFFB300, // Amber Gold
    0xFF10B981, // Emerald Green
    0xFF8B5CF6, // Violet
    0xFFEC4899, // Pink
    0xFFEF4444, // Red
    0xFFF97316, // Orange
    0xFF06B6D4, // Cyan
    0xFF6366F1, // Indigo
    0xFF22C55E, // Green
  ];

  const AppTheme._();

  static ThemeData darkStudioTheme() {
    const colorScheme = ColorScheme.dark(
      primary: primaryAccent,
      secondary: successEmerald,
      surface: panelSurface,
      error: dangerRose,
      onPrimary: Color(0xFF090D16),
      onSecondary: Color(0xFF090D16),
      onSurface: Color(0xFFF1F5F9),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: studioBackground,
      cardTheme: CardThemeData(
        color: cardSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderSubtle, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: studioBackground,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryAccent, width: 2),
        ),
      ),
      dividerColor: borderSubtle,
    );
  }
}
