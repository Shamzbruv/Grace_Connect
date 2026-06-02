import 'package:flutter/material.dart';
import '../../../models/user_profile.dart';
import '../dashboard_module.dart';

class UrgentAlertsModule extends DashboardModule {
  const UrgentAlertsModule({super.key});

  @override
  int get priority => 0; // Top priority

  @override
  bool shouldShow(UserProfile user) {
    return user.isStaff;
  }

  @override
  Widget build(BuildContext context) {
    // Logic to check for alerts would go here.
    return Card(
      color: Colors.red.shade50,
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
        title: const Text("Urgent Alerts"),
        subtitle: const Text("No critical system alerts."),
        trailing:
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red.shade300),
      ),
    );
  }
}
