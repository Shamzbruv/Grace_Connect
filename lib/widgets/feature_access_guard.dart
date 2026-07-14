import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../access/app_access_context.dart';
import '../access/app_feature.dart';
import '../screens/access/feature_unavailable_screen.dart';

class FeatureAccessGuard extends StatelessWidget {
  const FeatureAccessGuard({
    super.key,
    required this.feature,
    required this.child,
  });

  final AppFeature feature;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    AppAccessContext? access;
    try {
      access = context.watch<AppAccessContext>();
    } catch (_) {
      access = null;
    }
    if (access == null || access.canUse(feature)) return child;

    return FeatureUnavailableScreen(
      feature: feature,
      access: access,
    );
  }
}
