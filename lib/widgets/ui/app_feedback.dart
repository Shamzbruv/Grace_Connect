import 'package:flutter/material.dart';

enum AppFeedbackType { info, success, warning, error }

class AppFeedback {
  const AppFeedback._();

  static void show(
    BuildContext context,
    String message, {
    AppFeedbackType type = AppFeedbackType.info,
  }) {
    final theme = Theme.of(context);
    final color = switch (type) {
      AppFeedbackType.success => Colors.greenAccent.shade400,
      AppFeedbackType.warning => Colors.amberAccent.shade400,
      AppFeedbackType.error => theme.colorScheme.error,
      AppFeedbackType.info => theme.colorScheme.primary,
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(_iconFor(type), color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String cancelLabel = 'Cancel',
    String confirmLabel = 'Confirm',
    IconData icon = Icons.help_outline,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? 0.2
                                : 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(cancelLabel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result == true;
  }

  static IconData _iconFor(AppFeedbackType type) {
    return switch (type) {
      AppFeedbackType.success => Icons.check_circle_outline,
      AppFeedbackType.warning => Icons.warning_amber_rounded,
      AppFeedbackType.error => Icons.error_outline,
      AppFeedbackType.info => Icons.info_outline,
    };
  }
}
