import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../dashboard/church_dashboard_screen.dart';

class MemberDashboardScreen extends StatelessWidget {
  const MemberDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProfile = Provider.of<UserRoleProvider>(context).userProfile;
    // Navigate directly to the new Church Dashboard
    return ChurchDashboardScreen(churchId: userProfile?.placeId ?? '');
  }
}
