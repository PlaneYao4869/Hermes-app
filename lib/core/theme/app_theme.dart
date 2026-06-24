import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Hermes brand colors
  static const _primaryLight = Color(0xFF1565C0);
  static const _primaryDark = Color(0xFF64B5F6);
  static const primaryDark = Color(0xFF64B5F6);
  static const _surfaceDark = Color(0xFF121218);
  static const _surfaceContainerDark = Color(0xFF1E1E26);
  static const _surfaceContainerHighDark = Color(0xFF28283A);
  static const error = Color(0xFFCF6679);
  static const success = Color(0xFF81C784);
  static const warning = Color(0xFFFFB74D);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: _primaryLight,
      brightness: Brightness.light,
      textTheme: GoogleFonts.interTextTheme(),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _primaryDark,
      brightness: Brightness.dark,
      surface: _surfaceDark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        surfaceContainerLow: _surfaceDark,
        surfaceContainer: _surfaceContainerDark,
        surfaceContainerHigh: _surfaceContainerHighDark,
        error: error,
      ),
      scaffoldBackgroundColor: _surfaceDark,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      cardTheme: CardThemeData(
        color: _surfaceContainerDark,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _surfaceDark,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surfaceContainerDark,
        indicatorColor: _primaryDark.withOpacity(0.2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceContainerHighDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF2A2A3A)),
    );
  }

  // Semantic colors for chat bubbles, diff viewer, etc.
  static const userBubble = Color(0xFF1565C0);
  static const agentBubble = Color(0xFF1E1E26);
  static const toolBubble = Color(0xFF2A2A3A);
  static const diffAdded = Color(0xFF2E7D32);
  static const diffRemoved = Color(0xFFC62828);
  static const diffAddedBg = Color(0xFF1B3A1B);
  static const diffRemovedBg = Color(0xFF3A1B1B);
}
