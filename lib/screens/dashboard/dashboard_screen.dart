import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../logic/dashboard_resolver.dart';
import '../signup screen/complete_profile_screen.dart';

// Variants
import 'variants/pastor_dashboard.dart';
import 'variants/admin_dashboard.dart';
import 'variants/finance_dashboard.dart';
import 'variants/ministry_dashboard.dart';
import 'variants/member_dashboard.dart';

import '../../services/attendance_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Initialize GPS Tracking when user lands on dashboard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AttendanceService().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 1. Get User Profile safely
    final provider = Provider.of<UserRoleProvider>(context);

    // Show loading or fallback if initializing
    if (provider.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 2. Resolve Dashboard Type
    final userProfile = provider.userProfile;
    if (userProfile == null) {
      return const CompleteProfileScreen();
    }

    final roles = userProfile.roles;
    final dashboardType = DashboardResolver.resolve(roles);

    // 3. Render appropriate widget
    switch (dashboardType) {
      case DashboardType.pastor:
        return const PastorDashboard();
      case DashboardType.admin:
        return const AdminDashboard();
      case DashboardType.finance:
        return const FinanceDashboard();
      case DashboardType.ministryLeader:
        return const MinistryDashboard(isLeader: true);
      case DashboardType.care:
        // Re-use Ministry or create specific later
        return const MinistryDashboard(isLeader: true);
      case DashboardType.service:
        // Use MinistryWorker variant for now
        return const MinistryDashboard(isLeader: false);
      case DashboardType.ministryWorker:
        return const MinistryDashboard(isLeader: false);
      case DashboardType.member:
        return const MemberDashboard();
    }
  }
}
