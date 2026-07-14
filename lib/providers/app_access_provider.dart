import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../access/app_access_context.dart';

class AppAccessScope extends StatelessWidget {
  const AppAccessScope({
    super.key,
    required this.access,
    required this.child,
  });

  final AppAccessContext access;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Provider<AppAccessContext>.value(
      value: access,
      child: child,
    );
  }
}

extension AppAccessLookup on BuildContext {
  AppAccessContext? get maybeAppAccess {
    try {
      return read<AppAccessContext>();
    } catch (_) {
      return null;
    }
  }
}
