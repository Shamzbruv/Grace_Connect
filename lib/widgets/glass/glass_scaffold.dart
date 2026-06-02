import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class GlassScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool extendBodyBehindAppBar;

  const GlassScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.extendBodyBehindAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      appBar: appBar,
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppColors.darkSurfaceGradient
                  : AppColors.primaryGradient
                      .scale(0.05), // Very subtle for light
              color: isDark ? AppColors.darkNavy : AppColors.warmGray,
            ),
          ),
          // Organic Mesh Gradients (Optional: Add Positioned blobs here)

          // Content
          SafeArea(
            bottom: false, // Let bottom nav handle safe area if needed
            child: body,
          ),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

extension GradientScale on LinearGradient {
  LinearGradient scale(double factor) {
    return LinearGradient(
      colors: colors.map((c) => c.withValues(alpha: factor)).toList(),
      begin: begin,
      end: end,
    );
  }
}
