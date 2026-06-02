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
      backgroundColor:
          Theme.of(context).scaffoldBackgroundColor, // Default background
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: effectiveBottomNavigationBar,
      body: SafeArea(
        child: withBackground
            ? Container(
                decoration: const BoxDecoration(
                  gradient: AppColors
                      .primaryGradient, // Use primary gradient for background
                ),
                child: body,
              )
            : body,
      ),
    );
  }
}
