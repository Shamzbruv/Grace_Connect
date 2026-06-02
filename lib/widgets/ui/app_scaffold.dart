import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../app_bottom_menu.dart';
import '../main_tab_scope.dart';

class AppScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool withBackground;
  final bool impliesLeading;
  final Widget? leading;
  final Color? backgroundColor;
  final Widget? drawer;
  final bool showBottomMenu;
  final double? appBarHeight;
  final TextStyle? appBarTitleStyle;
  final bool bodySafeAreaTop;

  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.withBackground = false,
    this.impliesLeading = true,
    this.leading,
    this.backgroundColor,
    this.drawer,
    this.showBottomMenu = false,
    this.appBarHeight,
    this.appBarTitleStyle,
    this.bodySafeAreaTop = true,
  });

  @override
  Widget build(BuildContext context) {
    // If backgroundColor is provided, use it. Otherwise, use scaffoldBackgroundColor from theme.
    // If withBackground is true, we might want to overlay a gradient or something.
    final effectiveBottomNavigationBar = bottomNavigationBar ??
        (showBottomMenu && !MainTabScope.isInTabShell(context)
            ? const AppBottomMenu()
            : null);

    return Scaffold(
      backgroundColor: backgroundColor,
      extendBodyBehindAppBar:
          withBackground, // If we have a fancy background, extend body
      drawer: drawer,
      appBar: title != null
          ? AppBar(
              toolbarHeight: appBarHeight,
              title: Text(title!, style: appBarTitleStyle),
              actions: actions,
              backgroundColor: withBackground ? Colors.transparent : null,
              elevation: withBackground ? 0 : null,
              leading: leading,
              automaticallyImplyLeading:
                  showBottomMenu ? false : impliesLeading,
              centerTitle: true,
            )
          : null,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: withBackground
            ? BoxDecoration(
                // Use a subtle gradient from the theme or define one here
                // if we want that "premium" feel, we can add a very subtle top-to-bottom gradient
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: Theme.of(context).brightness == Brightness.light
                      ? [
                          const Color(0xFFF9F9F7), // Very light warm gray
                          AppColors.warmGray,
                        ]
                      : [
                          const Color(0xFF151922), // Slightly lighter top
                          const Color(0xFF10141C), // Deep navy bottom
                        ],
                  stops: const [0.0, 0.4],
                ),
              )
            : null,
        child: SafeArea(
          top: bodySafeAreaTop,
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxWidth: 600), // Enforce mobile width on desktop
              child: body,
            ),
          ),
        ),
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: effectiveBottomNavigationBar,
    );
  }
}
