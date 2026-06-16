import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/ministry.dart';
import '../../../providers/user_role_provider.dart';
import '../../../services/ministry_service.dart';
import '../widgets/dashboard_scaffold.dart';
import '../widgets/action_card.dart';

class MinistryDashboard extends StatelessWidget {
  final bool isLeader;
  const MinistryDashboard({super.key, this.isLeader = false});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserRoleProvider>().userProfile;
    final ministryService = MinistryService();

    return DashboardScaffold(
      title: isLeader ? 'Ministry Leader Dashboard' : 'Ministry Dashboard',
      children: [
        FutureBuilder<List<MinistryManager>>(
          future: ministryService.fetchMyManagedMinistries(),
          builder: (context, snapshot) {
            final managedMinistries =
                snapshot.data ?? const <MinistryManager>[];
            final canCreateEvent = user?.capabilities.canCreateEvents == true ||
                managedMinistries.any((manager) => manager.canCreateEvents);
            final canPublishAnnouncement =
                user?.capabilities.canPublishAnnouncements == true ||
                    managedMinistries.any(
                      (manager) => manager.canPublishAnnouncements,
                    );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          managedMinistries.isEmpty
                              ? 'No assigned ministries yet.'
                              : '${managedMinistries.length} assigned ministr${managedMinistries.length == 1 ? 'y' : 'ies'}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (managedMinistries.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: managedMinistries
                                .map(
                                  (manager) => Chip(
                                    label: Text(manager.ministryName),
                                    avatar: const Icon(
                                      Icons.groups_outlined,
                                      size: 18,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Actions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ActionCard(
                  title: 'Ministries',
                  description: 'View ministries and manager assignments',
                  icon: Icons.groups_outlined,
                  onTap: () => Navigator.pushNamed(context, '/ministries'),
                ),
                if (canPublishAnnouncement) ...[
                  const SizedBox(height: 12),
                  ActionCard(
                    title: 'Create Announcement',
                    description: 'Share updates from your ministry',
                    icon: Icons.campaign_outlined,
                    onTap: () => Navigator.pushNamed(context, '/announcements'),
                  ),
                ],
                if (canCreateEvent) ...[
                  const SizedBox(height: 12),
                  ActionCard(
                    title: 'Create Event',
                    description: 'Add events for your ministry',
                    icon: Icons.event_available_outlined,
                    onTap: () => Navigator.pushNamed(context, '/events'),
                  ),
                ],
                const SizedBox(height: 12),
                ActionCard(
                  title: 'Upcoming Events',
                  description: 'View ministry calendar',
                  icon: Icons.calendar_month,
                  onTap: () => Navigator.pushNamed(context, '/events'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
