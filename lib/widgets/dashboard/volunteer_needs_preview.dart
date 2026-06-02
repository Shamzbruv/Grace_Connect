import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../services/volunteer_service.dart';
import '../../models/volunteer_need.dart';

class VolunteerNeedsPreview extends StatelessWidget {
  final String churchId;
  final VoidCallback onViewAll;

  const VolunteerNeedsPreview(
      {super.key, required this.churchId, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.volunteer_activism, color: AppColors.tertiary),
                SizedBox(width: 8),
                Text('Volunteer Needs',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            TextButton(
              onPressed: onViewAll,
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<VolunteerNeed>>(
          stream: VolunteerService().getOpenNeeds(churchId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final needs = snapshot.data ?? [];

            if (needs.isEmpty) {
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                child: Text('No volunteer requests right now',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.grey)),
              );
            }

            // Take top 2
            final previewNeeds = needs.take(2).toList();

            return Column(
              children: previewNeeds
                  .map((need) => _buildNeedItem(context, need))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNeedItem(BuildContext context, VolunteerNeed need) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(need.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(DateFormat('MMM d').format(need.date)),
        trailing: ElevatedButton(
          onPressed: onViewAll, // Go to full list to sign up
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.tertiary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(60, 30),
          ),
          child: const Text('View'),
        ),
      ),
    );
  }
}
