import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/church_stats.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/church_service.dart';
import '../../widgets/ui/app_loader.dart';

// Modules
import 'dashboard_module.dart';
import 'modules/urgent_alerts_module.dart';
import 'modules/prayer_assigned_module.dart';
import 'modules/prayer_oversight_module.dart';
import 'modules/leadership_actions_module.dart';
import 'modules/church_health_module.dart';

class ChurchDashboardScreen extends StatefulWidget {
  final String churchId;
  const ChurchDashboardScreen({super.key, required this.churchId});

  @override
  State<ChurchDashboardScreen> createState() => _ChurchDashboardScreenState();
}

class _ChurchDashboardScreenState extends State<ChurchDashboardScreen> {
  bool _isLoading = true;
  ChurchStats? _stats;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final stats = await ChurchService().getStats(widget.churchId);
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading stats: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserRoleProvider>(context);
    final UserProfile? user = userProvider.user;

    if (user == null) {
      return const Center(child: Text("User not found"));
    }

    if (_isLoading) {
      return const AppLoader();
    }

    // Define All Modules
    final List<DashboardModule> allModules = [
      UrgentAlertsModule(),
      LeadershipActionsModule(), // Added
      PrayerAssignedModule(),
      PrayerOversightModule(),
      if (_stats != null) ChurchHealthModule(stats: _stats!),
    ];

    // Filter and Sort
    final accessibleModules =
        allModules.where((m) => m.shouldShow(user)).toList();
    accessibleModules.sort((a, b) => a.priority.compareTo(b.priority));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome, ${user.fullName}",
                  style: GoogleFonts.outfit(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text(
                  "Role: ${user.roles.join(', ')}",
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          if (accessibleModules.isEmpty)
            const Card(
              margin: EdgeInsets.all(16),
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text("No specific dashboard modules for your role."),
              ),
            ),
          ...accessibleModules.map((module) => module),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
