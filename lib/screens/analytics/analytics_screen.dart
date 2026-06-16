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
    final client = Supabase.instance.client;
    final now = DateTime.now();
    final lastSunday = now.subtract(Duration(days: now.weekday % 7));
    final startOfWeek =
        DateTime(lastSunday.year, lastSunday.month, lastSunday.day);
    final today = DateTime(now.year, now.month, now.day);
    final stats = await ChurchStatsService().getStats(churchId);

    final posts = await client
        .from('community_posts')
        .select('id')
        .eq('place_id', churchId)
        .count(CountOption.exact);

    final events = await client
        .from('events')
        .select('id')
        .eq('churchId', churchId)
        .gte('date', today.toIso8601String())
        .count(CountOption.exact);

    final tickets = await client
        .from('support_tickets')
        .select('id')
        .eq('churchId', churchId)
        .neq('status', 'resolved')
        .count(CountOption.exact);

    final membersRows = await _safeRows(() => client
        .from('users')
        .select('uid, fullName, email, roles')
        .eq('placeId', churchId)
        .order('fullName')
        .limit(100));

    final attendanceRows = await _safeRows(() => client
        .from('attendance')
        .select('id, user_id, service_name, status, method, timestamp')
        .eq('church_id', churchId)
        .gte('timestamp', startOfWeek.toIso8601String())
        .order('timestamp', ascending: false)
        .limit(100));

    final postRows = await _safeRows(() => client
        .from('community_posts')
        .select('id, author_name, content, created_at')
        .eq('place_id', churchId)
        .order('created_at', ascending: false)
        .limit(50));

    final eventRows = await _safeRows(() => client
        .from('events')
        .select('id, title, date, time, location')
        .eq('churchId', churchId)
        .gte('date', today.toIso8601String())
        .order('date')
        .limit(50));

    final ministryRows = await _safeRows(() => client
        .from('ministries')
        .select('id, name, status')
        .eq('church_id', churchId)
        .eq('status', 'active')
        .order('name')
        .limit(50));

    final ticketRows = await _safeRows(() => client
        .from('support_tickets')
        .select('id, title, status, createdAt')
        .eq('churchId', churchId)
        .neq('status', 'resolved')
        .order('createdAt', ascending: false)
        .limit(50));

    Map<String, double>? finance;
    if (canViewFinance) {
      finance = await FinanceService().getMonthlySummary(churchId);
    }

    return _AnalyticsData(
      stats: stats,
      postsCount: posts.count,
      eventsCount: events.count,
      openTicketsCount: tickets.count,
      membersRows: membersRows,
      attendanceRows: attendanceRows,
      postRows: postRows,
      eventRows: eventRows,
      ministryRows: ministryRows,
      ticketRows: ticketRows,
      finance: finance,
    );
  }

  Future<List<Map<String, dynamic>>> _safeRows(
    Future<dynamic> Function() query,
  ) async {
    try {
      final response = await query();
      return (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (_) {
      return const [];
    }
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
    final memberById = {
      for (final row in data.membersRows)
        if ((row['uid'] ?? '').toString().isNotEmpty)
          row['uid'].toString(): row,
    };

    final tiles = [
      _MetricTile(
        'Members',
        data.stats.activeMembers.toString(),
        Icons.people_outline,
        'Profiles attached to this church',
        onTap: () => _showAnalyticsDetails(
          context,
          'Members',
          data.membersRows,
          itemBuilder: (row) {
            final roles = row['roles'] is List
                ? (row['roles'] as List).join(', ')
                : (row['roles'] ?? 'Member').toString();
            return _DetailTile(
              icon: Icons.person_outline,
              title: _string(row['fullName'], fallback: row['email']),
              subtitle: roles.isEmpty ? 'Member' : roles,
            );
          },
        ),
      ),
      _MetricTile('Attendance', data.stats.attendanceThisWeek.toString(),
          Icons.event_available_outlined, 'Check-ins recorded this week',
          onTap: () => _showAnalyticsDetails(
                context,
                'Attendance This Week',
                data.attendanceRows,
                itemBuilder: (row) {
                  final member = memberById[row['user_id']?.toString()];
                  final name = _string(
                    member?['fullName'],
                    fallback: member?['email'] ?? row['user_id'],
                  );
                  final status = _string(row['status'], fallback: 'recorded');
                  final method = _string(row['method'], fallback: 'check-in');
                  final service =
                      _string(row['service_name'], fallback: 'Service');
                  return _DetailTile(
                    icon: Icons.event_available_outlined,
                    title: name,
                    subtitle:
                        '$service - ${_titleCase(status)} via ${_titleCase(method)}',
                    trailing: _formatDate(row['timestamp']),
                  );
                },
              )),
      _MetricTile('Posts', data.postsCount.toString(),
          Icons.dynamic_feed_outlined, 'Feed updates shared by members',
          onTap: () => _showAnalyticsDetails(
                context,
                'Posts',
                data.postRows,
                itemBuilder: (row) => _DetailTile(
                  icon: Icons.dynamic_feed_outlined,
                  title: _string(row['author_name'], fallback: 'Member'),
                  subtitle: _string(row['content'], fallback: 'Media post'),
                  trailing: _formatDate(row['created_at']),
                ),
              )),
      _MetricTile(
        'Events',
        data.eventsCount.toString(),
        Icons.calendar_month_outlined,
        'Church calendar items',
        onTap: () => _showAnalyticsDetails(
          context,
          'Upcoming Events',
          data.eventRows,
          itemBuilder: (row) => _DetailTile(
            icon: Icons.calendar_month_outlined,
            title: _string(row['title'], fallback: 'Event'),
            subtitle: [
              _formatDate(row['date']),
              _string(row['time']),
              _string(row['location']),
            ].where((value) => value.trim().isNotEmpty).join(' - '),
          ),
        ),
      ),
      _MetricTile('Ministries', data.stats.ministryCount.toString(),
          Icons.groups_outlined, 'Groups and ministries being tracked',
          onTap: () => _showAnalyticsDetails(
                context,
                'Ministries',
                data.ministryRows,
                itemBuilder: (row) => _DetailTile(
                  icon: Icons.groups_outlined,
                  title: _string(row['name'], fallback: 'Ministry'),
                  subtitle:
                      _titleCase(_string(row['status'], fallback: 'active')),
                ),
              )),
      _MetricTile('Open Tickets', data.openTicketsCount.toString(),
          Icons.support_agent_outlined, 'Support issues still unresolved',
          onTap: () => _showAnalyticsDetails(
                context,
                'Open Tickets',
                data.ticketRows,
                itemBuilder: (row) => _DetailTile(
                  icon: Icons.support_agent_outlined,
                  title: _string(row['title'], fallback: 'Support ticket'),
                  subtitle:
                      _titleCase(_string(row['status'], fallback: 'open')),
                  trailing: _formatDate(row['createdAt']),
                ),
              )),
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
          padding: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: tile.onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAnalyticsDetails(
    BuildContext context,
    String title,
    List<Map<String, dynamic>> rows, {
    required Widget Function(Map<String, dynamic> row) itemBuilder,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('No records found.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            itemBuilder(rows[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _string(dynamic value, {dynamic fallback = ''}) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return fallback?.toString() ?? '';
    return text;
  }

  String _titleCase(String value) {
    final words = value.replaceAll('_', ' ').split(' ');
    return words
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return DateFormat.MMMd().add_jm().format(parsed.toLocal());
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null && trailing!.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(
              trailing!,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
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
  const _MetricTile(
    this.label,
    this.value,
    this.icon,
    this.description, {
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final String description;
  final VoidCallback? onTap;
}

class _AnalyticsData {
  const _AnalyticsData({
    required this.stats,
    required this.postsCount,
    required this.eventsCount,
    required this.openTicketsCount,
    required this.membersRows,
    required this.attendanceRows,
    required this.postRows,
    required this.eventRows,
    required this.ministryRows,
    required this.ticketRows,
    this.finance,
  });

  final ChurchStats stats;
  final int postsCount;
  final int eventsCount;
  final int openTicketsCount;
  final List<Map<String, dynamic>> membersRows;
  final List<Map<String, dynamic>> attendanceRows;
  final List<Map<String, dynamic>> postRows;
  final List<Map<String, dynamic>> eventRows;
  final List<Map<String, dynamic>> ministryRows;
  final List<Map<String, dynamic>> ticketRows;
  final Map<String, double>? finance;
}
