import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/user_role_provider.dart';
import '../../services/attendance_analytics_service.dart';
import '../../widgets/charts/attendance_trend_chart.dart';
import '../../widgets/ui/app_scaffold.dart';

class ChurchOverviewDetailScreen extends StatefulWidget {
  const ChurchOverviewDetailScreen({
    super.key,
    required this.metric,
  });

  final String metric;

  @override
  State<ChurchOverviewDetailScreen> createState() =>
      _ChurchOverviewDetailScreenState();
}

class _ChurchOverviewDetailScreenState
    extends State<ChurchOverviewDetailScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late Future<_OverviewDetailData> _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final churchId =
        context.read<UserRoleProvider>().userProfile?.churchId ?? '';
    _future = _load(churchId);
  }

  Future<_OverviewDetailData> _load(String churchId) async {
    if (churchId.trim().isEmpty) {
      return _OverviewDetailData(
        title: 'Church Overview',
        icon: Icons.church_outlined,
        rows: const [],
        emptyLabel: 'Join a church to view details.',
      );
    }

    return switch (widget.metric) {
      'members' => _loadMembers(churchId),
      'attendance' => _loadAttendance(churchId),
      'events' => _loadEvents(churchId),
      'care' => _loadCare(churchId),
      _ => _loadMembers(churchId),
    };
  }

  Future<_OverviewDetailData> _loadMembers(String churchId) async {
    final rows = await _supabase
        .from('users')
        .select('uid, fullName, email, roles')
        .eq('placeId', churchId)
        .order('fullName')
        .limit(100);

    return _OverviewDetailData(
      title: 'Members',
      icon: Icons.people_outline,
      emptyLabel: 'No linked member profiles found.',
      rows: [
        for (final row in rows)
          _OverviewRow(
            title: _firstText(row['fullName'], row['email'], 'Member'),
            subtitle: _roleLabel(row),
            icon: Icons.person_outline,
          ),
      ],
    );
  }

  Future<_OverviewDetailData> _loadAttendance(String churchId) async {
    final since = DateTime.now()
        .subtract(const Duration(days: 7))
        .toUtc()
        .toIso8601String();
    final rows = await _supabase
        .from('attendance')
        .select()
        .eq('church_id', churchId)
        .gte('timestamp', since)
        .order('timestamp', ascending: false)
        .limit(100);

    List<ServiceAttendanceSummary> chartSummaries = const [];
    try {
      chartSummaries = await AttendanceAnalyticsService()
          .recentServiceSummaries(churchId);
    } catch (_) {
      // The raw list below still renders even if the aggregate table isn't
      // reachable (e.g. RLS denies this role) -- charts are additive, not a
      // hard dependency for this screen's core purpose.
    }

    return _OverviewDetailData(
      title: 'Attendance',
      icon: Icons.event_available_outlined,
      emptyLabel: 'No attendance records this week.',
      chartSummaries: chartSummaries,
      rows: [
        for (final row in rows)
          _OverviewRow(
            title: _firstText(row['service_name'], 'Attendance record'),
            subtitle: [
              _formatDate(row['timestamp']),
              row['status']?.toString() ?? 'unknown',
              row['method']?.toString() ?? 'unknown',
            ].join(' • '),
            icon: row['present'] == true
                ? Icons.check_circle_outline
                : Icons.schedule_outlined,
          ),
      ],
    );
  }

  Future<_OverviewDetailData> _loadEvents(String churchId) async {
    final rows = await _supabase
        .from('events')
        .select('id, title, description, date')
        .eq('churchId', churchId)
        .gte('date', DateTime.now().toIso8601String())
        .order('date')
        .limit(100);

    return _OverviewDetailData(
      title: 'Upcoming Events',
      icon: Icons.calendar_month_outlined,
      emptyLabel: 'No upcoming events.',
      rows: [
        for (final row in rows)
          _OverviewRow(
            title: _firstText(row['title'], 'Event'),
            subtitle: [
              _formatDate(row['date']),
              if (row['description']?.toString().trim().isNotEmpty == true)
                row['description'].toString(),
            ].join(' • '),
            icon: Icons.event_outlined,
          ),
      ],
    );
  }

  Future<_OverviewDetailData> _loadCare(String churchId) async {
    final prayers = await _supabase
        .from('prayer_requests')
        .select('id, title, userName, status, createdAt')
        .eq('churchId', churchId)
        .not('status', 'eq', 'closed')
        .order('createdAt', ascending: false)
        .limit(50);
    final counseling = await _supabase
        .from('counseling_requests')
        .select('id, category, urgency, status, createdAt')
        .eq('churchId', churchId)
        .neq('status', 'completed')
        .neq('status', 'cancelled')
        .order('createdAt', ascending: false)
        .limit(50);

    final rows = <_OverviewRow>[
      for (final row in prayers)
        _OverviewRow(
          title: _firstText(row['title'], 'Prayer request'),
          subtitle: [
            row['userName']?.toString() ?? 'Member',
            row['status']?.toString() ?? 'active',
            _formatDate(row['createdAt']),
          ].join(' • '),
          icon: Icons.volunteer_activism_outlined,
        ),
      for (final row in counseling)
        _OverviewRow(
          title: _firstText(row['category'], 'Counseling request'),
          subtitle: [
            row['urgency']?.toString() ?? 'Care',
            row['status']?.toString() ?? 'pending',
            _formatDate(row['createdAt']),
          ].join(' • '),
          icon: Icons.favorite_outline,
        ),
    ];

    return _OverviewDetailData(
      title: 'Care Needs',
      icon: Icons.favorite_border,
      emptyLabel: 'No open prayer or counseling items.',
      rows: rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OverviewDetailData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return AppScaffold(
          title: data?.title ?? 'Church Overview',
          body: snapshot.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator())
              : snapshot.hasError
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Text('Could not load details: ${snapshot.error}'),
                      ),
                    )
                  : _OverviewDetailList(data: data!),
        );
      },
    );
  }
}

class _OverviewDetailList extends StatelessWidget {
  const _OverviewDetailList({required this.data});

  final _OverviewDetailData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chartSummaries = data.chartSummaries;
    // The chart draws from a different, longer-window table than the raw
    // row list (this week's individual check-ins) -- an empty week of rows
    // must not hide weeks of real chart history that still exist.
    if (data.rows.isEmpty && (chartSummaries == null || chartSummaries.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(data.icon, size: 52, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(data.emptyLabel, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: data.rows.length + (chartSummaries != null ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (chartSummaries != null) {
          if (index == 0) {
            return AttendanceTrendChart(summaries: chartSummaries);
          }
          index -= 1;
        }
        if (data.rows.isEmpty) return const SizedBox.shrink();
        final row = data.rows[index];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: theme.dividerColor.withValues(alpha: 0.18)),
          ),
          child: ListTile(
            leading: Icon(row.icon, color: theme.colorScheme.primary),
            title: Text(row.title),
            subtitle: Text(row.subtitle),
          ),
        );
      },
    );
  }
}

class _OverviewDetailData {
  const _OverviewDetailData({
    required this.title,
    required this.icon,
    required this.rows,
    required this.emptyLabel,
    this.chartSummaries,
  });

  final String title;
  final IconData icon;
  final List<_OverviewRow> rows;
  final String emptyLabel;
  final List<ServiceAttendanceSummary>? chartSummaries;
}

class _OverviewRow {
  const _OverviewRow({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}

String _firstText(Object? primary, [Object? secondary, String fallback = '']) {
  final first = primary?.toString().trim() ?? '';
  if (first.isNotEmpty) return first;
  final second = secondary?.toString().trim() ?? '';
  return second.isNotEmpty ? second : fallback;
}

String _roleLabel(Map<String, dynamic> row) {
  final roles = row['roles'];
  if (roles is List && roles.isNotEmpty) {
    return roles.map((role) => role.toString()).join(', ');
  }
  return 'Member';
}

String _formatDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'No date';
  return DateFormat('MMM d, yyyy h:mm a').format(date);
}
