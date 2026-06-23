import 'package:flutter/material.dart';

enum AppSnackbarTone { info, success, warning, error }

class AppSnackbar {
  static void show(
    BuildContext context,
    String message, {
    AppSnackbarTone tone = AppSnackbarTone.info,
  }) {
    final theme = Theme.of(context);
    final colors = _colors(theme, tone);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 8,
          backgroundColor: colors.$1,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: colors.$2.withValues(alpha: 0.35)),
          ),
          content: Row(
            children: [
              Icon(_icon(tone), color: colors.$2),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.$3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  static (Color, Color, Color) _colors(
    ThemeData theme,
    AppSnackbarTone tone,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    return switch (tone) {
      AppSnackbarTone.success => (
          isDark ? const Color(0xFF12281A) : const Color(0xFFEAF8ED),
          const Color(0xFF4CCB5B),
          isDark ? Colors.white : const Color(0xFF12351A),
        ),
      AppSnackbarTone.warning => (
          isDark ? const Color(0xFF2F2510) : const Color(0xFFFFF6D8),
          const Color(0xFFE0A526),
          isDark ? Colors.white : const Color(0xFF3B2A02),
        ),
      AppSnackbarTone.error => (
          isDark ? const Color(0xFF321818) : const Color(0xFFFFEAEA),
          const Color(0xFFFF6464),
          isDark ? Colors.white : const Color(0xFF451111),
        ),
      AppSnackbarTone.info => (
          isDark ? const Color(0xFF1D2735) : const Color(0xFFEAF5FF),
          const Color(0xFF8CCBFF),
          isDark ? Colors.white : const Color(0xFF0E2B44),
        ),
    };
  }

  static IconData _icon(AppSnackbarTone tone) {
    return switch (tone) {
      AppSnackbarTone.success => Icons.check_circle_outline,
      AppSnackbarTone.warning => Icons.warning_amber_rounded,
      AppSnackbarTone.error => Icons.error_outline,
      AppSnackbarTone.info => Icons.info_outline,
    };
  }
}
