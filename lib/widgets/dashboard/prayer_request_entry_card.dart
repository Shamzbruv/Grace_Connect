import 'package:flutter/material.dart';

class PrayerRequestEntryCard extends StatelessWidget {
  final VoidCallback onRequest;

  const PrayerRequestEntryCard({super.key, required this.onRequest});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).colorScheme.brightness == Brightness.dark
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.15)
          : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3), // Subtle tint
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.favorite, color: Theme.of(context).colorScheme.onPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Need Prayer?',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text('Our team is ready to pray for you.',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onRequest,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Request'),
            ),
          ],
        ),
      ),
    );
  }
}
