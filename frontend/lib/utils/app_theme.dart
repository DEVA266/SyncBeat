import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color bg = Color(0xFF0D0D14);
  static const Color surface = Color(0xFF16161F);
  static const Color surfaceElevated = Color(0xFF1E1E2E);
  static const Color accent = Color(0xFF6C63FF);
  static const Color accentLight = Color(0xFF9D97FF);
  static const Color success = Color(0xFF4ECCA3);
  static const Color warning = Color(0xFFFFB347);
  static const Color danger = Color(0xFFFF6B6B);
  static const Color textPrimary = Color(0xFFF0F0F8);
  static const Color textSecondary = Color(0xFF8888AA);
  static const Color divider = Color(0xFF2A2A3A);
  static const Color hostBadge = Color(0xFFFFB347);
  static const Color adminBadge = Color(0xFF6C63FF);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        primary: accent,
        secondary: success,
        error: danger,
        onSurface: textPrimary,
        onPrimary: Colors.white,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accentLight),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: divider),
        ),
      ),
    );
  }
}