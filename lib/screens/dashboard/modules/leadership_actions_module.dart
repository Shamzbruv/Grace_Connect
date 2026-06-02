import 'package:flutter/material.dart';
import '../../../models/user_profile.dart';
import '../dashboard_module.dart';

class LeadershipActionsModule extends DashboardModule {
  const LeadershipActionsModule({super.key});

  @override
  int get priority => 3;

  @override
  bool shouldShow(UserProfile user) {
    return user.canAssignPrayers; // Pastor, Asst Pastor
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            title: Text("Quick Actions",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.person_add, size: 16),
                  label: const Text("Assign Role"),
                  onPressed: () {
                    // Navigate to Role Manager
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.volunteer_activism, size: 16),
                  label: const Text("Assign Prayer"),
                  onPressed: () {
                    // This creates a task from scratch? usually we assign from a list.
                    // Navigate to Prayer Requests List to pick one.
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.announcement, size: 16),
                  label: const Text("Post Announcement"),
                  onPressed: () {},
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
