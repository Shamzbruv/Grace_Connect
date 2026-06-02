import 'package:flutter/material.dart';
import '../../models/user_profile.dart';

abstract class DashboardModule extends StatelessWidget {
  const DashboardModule({super.key});

  /// Priority of the module (lower is higher)
  int get priority => 10;

  /// Whether this module should be shown for the given user role
  bool shouldShow(UserProfile user);

  @override
  Widget build(BuildContext context);
}
