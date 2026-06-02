import 'package:flutter/widgets.dart';

class MainTabScope extends InheritedWidget {
  const MainTabScope({
    super.key,
    required this.inTabShell,
    required super.child,
  });

  final bool inTabShell;

  static bool isInTabShell(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<MainTabScope>()
            ?.inTabShell ??
        false;
  }

  @override
  bool updateShouldNotify(MainTabScope oldWidget) {
    return inTabShell != oldWidget.inTabShell;
  }
}
