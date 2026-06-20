import 'package:flutter/material.dart';

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isSecondary;
  final IconData? icon;
  final bool isFullWidth;
  final Color? backgroundColor;
  final Color? textColor;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isSecondary = false,
    this.icon,
    this.isFullWidth = true,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine styles based on secondary flag or overrides
    final bgColor = backgroundColor ??
        (isSecondary ? Colors.transparent : theme.colorScheme.primary);
    final fgColor = textColor ??
        (isSecondary ? theme.colorScheme.primary : theme.colorScheme.onPrimary);
    final borderSide = isSecondary
        ? BorderSide(color: theme.colorScheme.primary, width: 2)
        : BorderSide.none;

    Widget buttonContent = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fgColor),
            ),
          ),
          const SizedBox(width: 12),
        ] else if (icon != null) ...[
          Icon(icon, size: 20),
          const SizedBox(width: 8),
        ],
        Text(text),
      ],
    );

    // If loading, we disable press but keep style active (or use disabled style?)
    // Requirement says "loading spinner inside button", usually implies button is still visible but unclickable.

    Widget button;

    if (isSecondary) {
      button = OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: fgColor,
          side: borderSide,
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((states) => bgColor),
        ),
        child: buttonContent,
      );
    } else {
      button = ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
        ),
        child: buttonContent,
      );
    }

    // Animate button press effect? Default material ripple is good, but we can add entrance animation.
    return isFullWidth
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}
