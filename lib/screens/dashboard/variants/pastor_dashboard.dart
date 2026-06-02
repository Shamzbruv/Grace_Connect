import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/church_stats.dart';
import '../../../providers/user_role_provider.dart';
import '../../../services/church_stats_service.dart';
import '../widgets/action_card.dart';
import '../widgets/dashboard_scaffold.dart';

class PastorDashboard extends StatefulWidget {
  const PastorDashboard({super.key});

  @override
  State<PastorDashboard> createState() => _PastorDashboardState();
}

class _PastorDashboardState extends State<PastorDashboard> {
  Future<_PastorDashboardData>? _future;
  String? _futureChurchId;

  Future<_PastorDashboardData> _load(String churchId) async {
    final stats = await ChurchStatsService().getStats(churchId);
    final supabase = Supabase.instance.client;

    final prayers = await supabase
        .from('prayer_requests')
        .select('id')
        .eq('churchId', churchId)
        .not('status', 'eq', 'closed')
        .count(CountOption.exact);

    final counseling = await supabase
        .from('counseling_requests')
        .select('id')
        .eq('churchId', churchId)
        .neq('status', 'completed')
        .neq('status', 'cancelled')
        .count(CountOption.exact);

    final events = await supabase
        .from('events')
        .select('id')
        .eq('churchId', churchId)
        .gte('date', DateTime.now().toIso8601String())
        .count(CountOption.exact);

    return _PastorDashboardData(
      stats: stats,
      activePrayerRequests: prayers.count,
      openCareCases: counseling.count,
      upcomingEvents: events.count,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProfile = context.watch<UserRoleProvider>().userProfile;
    final churchId = userProfile?.churchId;

    if (churchId == null || churchId.isEmpty) {
      return const DashboardScaffold(
        title: 'Pastor Dashboard',
        children: [
          Center(child: Text('Join a church to view pastor tools.')),
        ],
      );
    }

    if (_future == null || _futureChurchId != churchId) {
      _futureChurchId = churchId;
      _future = _load(churchId);
    }

    return DashboardScaffold(
      title: 'Pastor Dashboard',
      children: [
        Text('Primary Actions', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ActionCard(
          title: "From the Pastor's Desk",
          description: 'Create an event or church-wide update',
          icon: Icons.campaign_outlined,
          onTap: () => Navigator.pushNamed(context, '/events'),
        ),
        const SizedBox(height: 12),
        ActionCard(
          title: 'Prayer Requests',
          description: 'Review and respond to prayer needs',
          icon: Icons.volunteer_activism_outlined,
          onTap: () => Navigator.pushNamed(context, '/prayers'),
        ),
        const SizedBox(height: 12),
        ActionCard(
          title: 'Counseling Cases',
          description: 'View pastoral care requests',
          icon: Icons.favorite_outline,
          onTap: () => Navigator.pushNamed(context, '/counseling'),
        ),
        if (userProfile?.canManageRoles == true) ...[
          const SizedBox(height: 12),
          ActionCard(
            title: 'Role Assignments',
            description: 'Assign ministry and leadership access',
            icon: Icons.security_outlined,
            onTap: () => Navigator.pushNamed(context, '/role_management'),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Church Overview',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        FutureBuilder<_PastorDashboardData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Text('Could not load overview: ${snapshot.error}');
            }

            final data = snapshot.data!;
            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.35,
              children: [
                _buildMiniCard(
                  context,
                  'Members',
                  '${data.stats.activeMembers}',
                  'Profiles linked to this church',
                  Icons.people_outline,
                ),
                _buildMiniCard(
                  context,
                  'Attendance',
                  '${data.stats.attendanceThisWeek}',
                  'Check-ins recorded this week',
                  Icons.event_available_outlined,
                ),
                _buildMiniCard(
                  context,
                  'Upcoming Events',
                  '${data.upcomingEvents}',
                  'Events still ahead',
                  Icons.calendar_month_outlined,
                ),
                _buildMiniCard(
                  context,
                  'Care Needs',
                  '${data.activePrayerRequests + data.openCareCases}',
                  'Open prayer and counseling items',
                  Icons.favorite_border,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMiniCard(
    BuildContext context,
    String title,
    String value,
    String description,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.brightness == Brightness.dark
                ? Colors.black26
                : Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PastorDashboardData {
  const _PastorDashboardData({
    required this.stats,
    required this.activePrayerRequests,
    required this.openCareCases,
    required this.upcomingEvents,
  });

  final ChurchStats stats;
  final int activePrayerRequests;
  final int openCareCases;
  final int upcomingEvents;
}
