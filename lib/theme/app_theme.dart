import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_typography.dart';

class AppTheme {
  // Premium Layout Constants
  static const double radiusCard = 24.0;
  static const double radiusButton = 16.0;
  static const double radiusInput = 50.0; // Pill shape

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary, // Deep Navy
      onPrimary: Colors.white,
      secondary: const Color(0xFF805500),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFFFE3AC),
      onSecondaryContainer: const Color(0xFF291800),
      tertiary: AppColors.tertiary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
    );

    return _buildTheme(colorScheme);
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: Color(
          0xFF90CAF9), // Lighter blue for dark mode visibility (M3 standard from Navy seed, approx)
      onPrimary: AppColors.primary,
      secondary: AppColors.secondary, // Gold stays Gold
      onSecondary: Colors.black,
      tertiary: AppColors.tertiary,
      surface: AppColors.surfaceDark, // Deep Charcoal/Navy
      onSurface: AppColors.textPrimaryDark,
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
    );

    return _buildTheme(colorScheme);
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.background,
      fontFamily: GoogleFonts.outfit().fontFamily,
      textTheme:
          isDark ? AppTypography.darkTextTheme : AppTypography.lightTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 2,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusButton)),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          textStyle:
              GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? const Color(0xFF2C3440)
            : Colors.white, // Slightly lighter than surfaceDark for inputs
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide(
              color: isDark ? Colors.white12 : const Color(0xFFE0E0E0),
              width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusInput),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        hintStyle:
            TextStyle(color: isDark ? Colors.white54 : AppColors.textSecondary),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 4,
        shadowColor: isDark ? const Color(0x80000000) : const Color(0x1A000000),
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusCard)),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusCard)),
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface),
      dividerTheme: DividerThemeData(
          color: isDark ? Colors.white10 : const Color(0xFFEEEEEE),
          thickness: 1),
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.onSurface.withValues(alpha: 0.22),
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.16),
        valueIndicatorColor: colorScheme.primary,
        valueIndicatorTextStyle: GoogleFonts.outfit(
          color: colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.background,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        modalBackgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.primaryVariant,
        contentTextStyle: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: AppColors.goldHighlight,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
        insetPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        titleTextStyle: GoogleFonts.outfit(
          color: colorScheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: GoogleFonts.outfit(
          color: colorScheme.onSurfaceVariant,
          fontSize: 15,
          height: 1.35,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: isDark ? Colors.white10 : const Color(0xFFE5E7EB),
          ),
        ),
      ),
    );
  }
}
