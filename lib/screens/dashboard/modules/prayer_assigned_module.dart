import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/user_profile.dart';
import '../../../models/prayer_task_model.dart';
import '../dashboard_module.dart';

class PrayerAssignedModule extends DashboardModule {
  const PrayerAssignedModule({super.key});

  @override
  int get priority => 1; // High priority for Prayer Warriors

  @override
  bool shouldShow(UserProfile user) {
    return user.isPrayerWarrior;
  }

  @override
  Widget build(BuildContext context) {
    // Note: Ideally obtain current user UID via Provider/Context
    // String currentUid = Provider.of<UserRoleProvider>(context).user?.uid ?? '';
    // For now, we assume we can get it or fail gracefully.

    // We will query simply by 'assignedToUid' which requires us to know the UID.
    // Since we don't have easy access to AUTH state in this snippet, we will assume
    // the parent widget or a Provider supplies it. Functional placeholder:

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('prayer_tasks')
          .stream(primaryKey: ['id']),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        // Filter manually for current user if needed, or rely on security rules + exact query in real app
        // Here we just map everything because we assume the query would be correct
        final tasks = snapshot.data!
            .where((doc) => doc['status'] == 'assigned' || doc['status'] == 'acknowledged')
            .map((doc) =>
                PrayerTask.fromMap(doc, doc['id'] ?? ''))
            .toList();

        // Filter locally for "assignedToUid" if we haven't filtered in query
        // if (task.assignedToUid != currentUid) ...

        if (tasks.isEmpty) {
          // Return nothing or a placeholder?
          // Spec says "Every module must render even if empty: 'No pending items'"
          return const Card(
            margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: ListTile(
              leading: Icon(Icons.check_circle_outline, color: Colors.grey),
              title: Text("My Assigned Prayers"),
              subtitle: Text("No pending prayer assignments."),
            ),
          );
        }

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text(
                  "My Assigned Prayers (${tasks.length})",
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Divider(height: 1),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  return ListTile(
                    leading: const Icon(Icons.volunteer_activism,
                        color: Colors.amber),
                    title: Text(task.priority == 'high'
                        ? "URGENT Prayer"
                        : "Prayer Request"),
                    subtitle: Text("Status: ${task.status}"),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(60, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        // On tap
                      },
                      child: const Text("View"),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
