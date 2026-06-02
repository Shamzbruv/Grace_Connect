import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final VoidCallback? onTap;
  final double? elevation;
  final Border? border;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.onTap,
    this.elevation,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    // Default theme values if not provided
    final theme = Theme.of(context);

    Widget cardContent = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: border != null
          ? BoxDecoration(
              color: color ?? theme.cardTheme.color,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: border,
            )
          : null,
      child: child,
    );

    Widget card = Card(
      margin: margin ?? theme.cardTheme.margin,
      color: color,
      elevation: elevation,
      // If border is provided, we used container decoration instead, so clip behavior might be needed
      clipBehavior: Clip.antiAlias,
      child: onTap != null
          ? InkWell(onTap: onTap, child: cardContent)
          : cardContent,
    );

    return card;
  }
}
