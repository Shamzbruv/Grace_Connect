import 'package:flutter/material.dart';

class AppColors {
  // --- CORE PALETTE ---

  // Primary (Deep Navy - from logo)
  static const Color primary = Color(0xFF10141C);
  static const Color primaryVariant =
      Color(0xFF1E2430); // Slightly lighter navy/charcoal

  // Secondary (Warm Gold - from logo)
  static const Color secondary = Color(0xFFD2982C);
  static const Color goldHighlight = Color(0xFFFFBF00);

  // Neutral / Surface
  static const Color background =
      Color(0xFFF8F9FA); // Off-white/Light Gray for background
  static const Color surface = Color(0xFFFFFFFF); // Pure white for cards

  static const Color backgroundDark = Color(0xFF10141C); // Dark Navy background
  static const Color surfaceDark = Color(0xFF1E2430); // Lighter Navy for cards

  // Text
  static const Color textPrimary = Color(0xFF1A1A1A); // Near Black
  static const Color textSecondary = Color(0xFF757575); // Muted Gray

  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFFB0B0B0);

  // Functional
  static const Color error = Color(0xFFB00020);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);

  // --- GRADIENTS ---
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, Color(0xFF2C3E50)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [secondary, goldHighlight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkSurfaceGradient = LinearGradient(
    colors: [Color(0xFF1E2430), Color(0xFF10141C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // --- LEGACY ALIASES (Mappings to new palette) ---
  static const Color gold = secondary;
  static const Color amber = goldHighlight;
  static const Color deepCharcoal = textPrimary;
  static const Color darkNavy = primary;
  static const Color warmGray = background;
  static const Color pureWhite = surface;
  static const Color burntOrange =
      Color(0xFFC45427); // Keeping original accent as tertiary option
  static const Color softBrown = Color(0xFFD26A4F);
  static const Color tertiary = burntOrange;

  static const Color glassBlack = Color(0x99000000);
  static const Color glassWhite = Color(0x99FFFFFF);
}
