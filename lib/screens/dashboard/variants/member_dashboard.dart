import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';
import '../widgets/dashboard_scaffold.dart';
import '../widgets/action_card.dart';
import '../../attendance/remote_attendance_screen.dart';

class MemberDashboard extends StatelessWidget {
  const MemberDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // Next Sunday calculation (simple)
    final now = DateTime.now();
    int daysUntilSunday = DateTime.sunday - now.weekday;
    if (daysUntilSunday <= 0) daysUntilSunday += 7;
    // ... logic for display ...

    return DashboardScaffold(
      title: 'Welcome Home',
      children: [
        // Next Service Card (Hero style)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient, // Navy
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.church, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(
                    'Next Service',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Sunday Celebration',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '9:00 AM • Main Sanctuary',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    Navigator.pushNamed(context, '/live_streaming'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Watch Live'),
              )
            ],
          ),
        ),

        const SizedBox(height: 24),

        Text('Quick Access', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _buildGridAction(context, 'Events', Icons.event,
                () => Navigator.pushNamed(context, '/events')),
            _buildGridAction(context, 'Groups', Icons.group_work,
                () => Navigator.pushNamed(context, '/study_groups')),
            _buildGridAction(context, 'Give', Icons.favorite,
                () => Navigator.pushNamed(context, '/donations')),
            _buildGridAction(context, 'Bible', Icons.book,
                () => Navigator.pushNamed(context, '/bible')),
            _buildGridAction(
                context,
                'Remote Check-In',
                Icons.wifi_tethering,
                () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const RemoteAttendanceScreen()))),
          ],
        ),

        const SizedBox(height: 24),
        ActionCard(
          title: 'Latest Announcements',
          description: 'Check what\'s happening in church',
          icon: Icons.notifications_active,
          onTap: () => Navigator.pushNamed(context, '/community'),
        ),
      ],
    );
  }

  Widget _buildGridAction(
      BuildContext context, String label, IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(label,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
