import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Background layers — darker → lighter for depth
  static const Color background = Color(0xFF0F0F1A);
  static const Color panel = Color(0xFF161625);
  static const Color surface = Color(0xFF1E1E32);
  static const Color surfaceHigh = Color(0xFF272742);
  static const Color border = Color(0xFF2A2A45);
  static const Color borderLight = Color(0xFF363658);

  // Text hierarchy
  static const Color textPrimary = Color(0xFFE8E6DF);
  static const Color textSecondary = Color(0xFFB4B2A9);
  static const Color textMuted = Color(0xFF6E6E8A);
  static const Color textDisabled = Color(0xFF454560);

  // Accent palette
  static const Color purple = Color(0xFF8B7FFF);
  static const Color purpleLight = Color(0xFFADA4FF);
  static const Color purpleDim = Color(0xFF3D3670);
  static const Color green = Color(0xFF5EE0A0);
  static const Color greenDim = Color(0xFF1B3D2F);
  static const Color amber = Color(0xFFFFBE4D);
  static const Color amberDim = Color(0xFF3D3018);
  static const Color red = Color(0xFFFF6B6B);
  static const Color redDim = Color(0xFF3D1B1B);
  static const Color blue = Color(0xFF6BB5FF);
  static const Color blueDim = Color(0xFF1B2E3D);
  static const Color white = Color(0xFFFFFFFF);

  // Shadows
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withAlpha(40),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: Colors.black.withAlpha(60),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get glowPurple => [
    BoxShadow(
      color: purple.withAlpha(30),
      blurRadius: 16,
      spreadRadius: 2,
    ),
  ];
}

/// Spacing constants — generous like WhatsApp/Instagram
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  // Touch target minimum (Apple/Google HIG)
  static const double touchTarget = 44;

  // Border radius
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusFull = 100;
}

class AppTheme {
  /// UI font — clean sans-serif (Inter via Google Fonts)
  static TextStyle uiFont({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.textPrimary,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// Code/terminal font — monospace (JetBrains Mono, bundled)
  static TextStyle codeFont({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    Color color = AppColors.textSecondary,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height ?? 1.5,
    );
  }

  static ThemeData get dark {
    final baseText = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.purple,
        secondary: AppColors.green,
        surface: AppColors.panel,
        error: AppColors.red,
      ),
      textTheme: baseText.copyWith(
        headlineLarge: baseText.headlineLarge?.copyWith(
          color: AppColors.white,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineMedium: baseText.headlineMedium?.copyWith(
          color: AppColors.white,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        titleLarge: baseText.titleLarge?.copyWith(
          color: AppColors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: baseText.titleMedium?.copyWith(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: baseText.bodyLarge?.copyWith(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
        bodyMedium: baseText.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
        bodySmall: baseText.bodySmall?.copyWith(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: baseText.labelLarge?.copyWith(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        labelMedium: baseText.labelMedium?.copyWith(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        labelSmall: baseText.labelSmall?.copyWith(
          color: AppColors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          borderSide: const BorderSide(color: AppColors.purple, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        hintStyle: GoogleFonts.inter(
          color: AppColors.textMuted,
          fontSize: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.purple,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          minimumSize: const Size(0, AppSpacing.touchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.purpleDim,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.purple,
            );
          }
          return GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: AppColors.textMuted,
          );
        }),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl),
          ),
        ),
        dragHandleColor: AppColors.borderLight,
        dragHandleSize: Size(36, 4),
        showDragHandle: true,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
      ),
    );
  }
}
