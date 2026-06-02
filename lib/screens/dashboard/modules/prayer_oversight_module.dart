import 'package:flutter/material.dart';
import '../../../models/user_profile.dart';
import '../dashboard_module.dart';

class PrayerOversightModule extends DashboardModule {
  const PrayerOversightModule({super.key});

  @override
  int get priority => 2; // High priority for Pastors

  @override
  bool shouldShow(UserProfile user) {
    return user.isPastor || user.isActingPastor;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Column(
        children: [
          ListTile(
            title: const Text("Prayer Oversight",
                style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: TextButton(onPressed: () {}, child: const Text("Manage")),
          ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(label: "New", count: "3"),
                _StatItem(label: "Assigned", count: "5"),
                _StatItem(label: "Prayed", count: "12"),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String count;
  const _StatItem({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(count,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
