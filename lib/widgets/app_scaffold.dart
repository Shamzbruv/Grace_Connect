import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_bottom_menu.dart';
import 'main_tab_scope.dart';

class AppScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final bool withBackground;
  final Widget? drawer;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool showBottomMenu;

  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.withBackground = false,
    this.drawer,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.showBottomMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveBottomNavigationBar = bottomNavigationBar ??
        (showBottomMenu && !MainTabScope.isInTabShell(context)
            ? const AppBottomMenu()
            : null);

    return Scaffold(
      appBar: title != null
          ? AppBar(
              title: Text(title!),
              centerTitle: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              automaticallyImplyLeading: !showBottomMenu,
              actions: actions,
            )
          : null,
      drawer: drawer,
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: effectiveBottomNavigationBar,
      body: SafeArea(
        child: withBackground
            ? Container(
                decoration: BoxDecoration(
                  gradient: isDark
                      ? AppColors.primaryGradient
                      : const LinearGradient(
                          colors: [Color(0xFFFFFFFF), Color(0xFFF8F9FA)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                ),
                child: body,
              )
            : body,
      ),
    );
  }
}
