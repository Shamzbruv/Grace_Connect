import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/church_stats.dart';
import '../../providers/user_role_provider.dart';
import '../../services/church_stats_service.dart';
import '../../services/finance_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_scaffold.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Future<_AnalyticsData>? _future;
  String? _futureChurchId;
  bool? _futureCanViewFinance;

  Future<_AnalyticsData> _loadAnalytics(
    String churchId,
    bool canViewFinance,
  ) async {
    final stats = await ChurchStatsService().getStats(churchId);

    final posts = await Supabase.instance.client
        .from('community_posts')
        .select('id')
        .eq('place_id', churchId)
        .count(CountOption.exact);

    final events = await Supabase.instance.client
        .from('events')
        .select('id')
        .eq('churchId', churchId)
        .count(CountOption.exact);

    final tickets = await Supabase.instance.client
        .from('support_tickets')
        .select('id')
        .eq('churchId', churchId)
        .neq('status', 'resolved')
        .count(CountOption.exact);

    Map<String, double>? finance;
    if (canViewFinance) {
      finance = await FinanceService().getMonthlySummary(churchId);
    }

    return _AnalyticsData(
      stats: stats,
      postsCount: posts.count,
      eventsCount: events.count,
      openTicketsCount: tickets.count,
      finance: finance,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProfile = Provider.of<UserRoleProvider>(context).userProfile;
    final churchId = userProfile?.churchId;

    if (churchId == null || churchId.isEmpty) {
      return const AppScaffold(
        title: 'Analytics',
        body: Center(child: Text('Join a church to view analytics.')),
      );
    }

    final canViewFinance = userProfile?.canViewFinance ?? false;
    if (_future == null ||
        _futureChurchId != churchId ||
        _futureCanViewFinance != canViewFinance) {
      _futureChurchId = churchId;
      _futureCanViewFinance = canViewFinance;
      _future = _loadAnalytics(churchId, canViewFinance);
    }

    return AppScaffold(
      title: 'Analytics',
      body: FutureBuilder<_AnalyticsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
                child: Text('Could not load analytics: ${snapshot.error}'));
          }

          final data = snapshot.data!;
          final currency = NumberFormat.simpleCurrency(name: 'JMD');

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _future = _loadAnalytics(churchId, canViewFinance);
              });
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatGrid(context, data),
                if (data.finance != null) ...[
                  const SizedBox(height: 16),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This Month Finance',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        _FinanceRow(
                          label: 'Income',
                          value: currency.format(data.finance!['income'] ?? 0),
                        ),
                        _FinanceRow(
                          label: 'Expenses',
                          value: currency.format(data.finance!['expense'] ?? 0),
                        ),
                        _FinanceRow(
                          label: 'Net',
                          value: currency.format(data.finance!['net'] ?? 0),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatGrid(BuildContext context, _AnalyticsData data) {
    final tiles = [
      _MetricTile(
        'Members',
        data.stats.activeMembers.toString(),
        Icons.people_outline,
        'Profiles attached to this church',
      ),
      _MetricTile('Attendance', data.stats.attendanceThisWeek.toString(),
          Icons.event_available_outlined, 'Check-ins recorded this week'),
      _MetricTile('Posts', data.postsCount.toString(),
          Icons.dynamic_feed_outlined, 'Feed updates shared by members'),
      _MetricTile(
        'Events',
        data.eventsCount.toString(),
        Icons.calendar_month_outlined,
        'Church calendar items',
      ),
      _MetricTile('Ministries', data.stats.ministryCount.toString(),
          Icons.groups_outlined, 'Groups and ministries being tracked'),
      _MetricTile('Open Tickets', data.openTicketsCount.toString(),
          Icons.support_agent_outlined, 'Support issues still unresolved'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tiles.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      itemBuilder: (context, index) {
        final tile = tiles[index];
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(tile.icon, color: Theme.of(context).colorScheme.primary),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tile.value,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    tile.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tile.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FinanceRow extends StatelessWidget {
  const _FinanceRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MetricTile {
  const _MetricTile(this.label, this.value, this.icon, this.description);

  final String label;
  final String value;
  final IconData icon;
  final String description;
}

class _AnalyticsData {
  const _AnalyticsData({
    required this.stats,
    required this.postsCount,
    required this.eventsCount,
    required this.openTicketsCount,
    this.finance,
  });

  final ChurchStats stats;
  final int postsCount;
  final int eventsCount;
  final int openTicketsCount;
  final Map<String, double>? finance;
}
