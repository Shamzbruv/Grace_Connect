import 'package:flutter/material.dart';

import '../../models/study_group_announcement.dart';
import '../../models/study_group_model.dart';
import '../../services/study_group_service.dart';
import '../../widgets/ui/app_card.dart';

class StudyGroupOverviewTab extends StatelessWidget {
  final StudyGroup group;
  final StudyGroupService service;

  const StudyGroupOverviewTab({
    super.key,
    required this.group,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        if (group.coverPhotoUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 7,
              child: Image.network(group.coverPhotoUrl, fit: BoxFit.cover),
            ),
          ),
        if (group.coverPhotoUrl.isNotEmpty) const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Study',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                group.displayStudy,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              if (group.description.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(group.description),
              ],
              const SizedBox(height: 16),
              LinearProgressIndicator(value: group.progressValue),
              const SizedBox(height: 8),
              Text(group.progressLabel),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                icon: Icons.event_outlined,
                label: 'Next meeting',
                value:
                    group.schedule.isEmpty ? 'Not scheduled' : group.schedule,
              ),
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: group.meetingLocation.isEmpty
                    ? 'Not set'
                    : group.meetingLocation,
              ),
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.people_outline,
                label: 'Members',
                value: '${group.memberCount} members',
              ),
            ],
          ),
        ),
        FutureBuilder<List<StudyGroupAnnouncement>>(
          future: service.fetchAnnouncements(group.id),
          builder: (context, snapshot) {
            final announcements = snapshot.data ?? const [];
            if (announcements.isEmpty) {
              return AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Leader Announcement',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    const Text('No announcement has been posted yet.'),
                  ],
                ),
              );
            }
            final announcement = announcements.first;
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    announcement.title.isEmpty
                        ? 'Leader Announcement'
                        : announcement.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(announcement.body),
                ],
              ),
            );
          },
        ),
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.volunteer_activism_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Quick prayer: Lord, help this group read with humility, discuss with grace and grow together.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(value),
            ],
          ),
        ),
      ],
    );
  }
}
