import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF1a1a2e);
  static const Color panel = Color(0xFF12122a);
  static const Color border = Color(0xFF2a2a4a);
  
  static const Color textPrimary = Color(0xFFb4b2a9);
  static const Color textMuted = Color(0xFF6a6a8a);
  
  static const Color green = Color(0xFF5dca7a);
  static const Color purple = Color(0xFF7f77dd);
  static const Color amber = Color(0xFFef9f27);
  static const Color red = Color(0xFFe24b4a);
  static const Color blue = Color(0xFF5b9bd5);
  static const Color white = Color(0xFFffffff);
  static const Color surface = Color(0xFF232340);
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.purple,
        secondary: AppColors.green,
        surface: AppColors.panel,
        error: AppColors.red,
      ),
      fontFamily: 'JetBrainsMono',
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 13),
        bodyMedium: TextStyle(color: AppColors.textPrimary, fontSize: 13),
        labelMedium: TextStyle(color: AppColors.textMuted, fontSize: 10),
        titleMedium: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w500),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.purple,
          foregroundColor: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}