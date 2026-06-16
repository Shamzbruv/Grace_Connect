import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../theme/app_colors.dart';
import '../../../../models/service_schedule.dart';
import '../../../../providers/user_role_provider.dart';
import '../../../../services/church_service.dart';
import '../widgets/dashboard_scaffold.dart';
import '../widgets/action_card.dart';
import '../../attendance/remote_attendance_screen.dart';

class MemberDashboard extends StatelessWidget {
  const MemberDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final userProfile = context.watch<UserRoleProvider>().userProfile;
    final churchId = userProfile?.churchId ?? '';

    return DashboardScaffold(
      title: 'Welcome Home',
      children: [
        _buildNextServiceCard(context, churchId),
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
          icon: Icons.campaign_outlined,
          onTap: () => Navigator.pushNamed(context, '/announcements'),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextServiceCard(BuildContext context, String churchId) {
    if (churchId.isEmpty) {
      return _NextServiceCard(
        title: 'Join a church',
        subtitle:
            'Your next service will show here once your profile is linked.',
        buttonLabel: 'Find Church',
        onPressed: () => Navigator.pushNamed(context, '/settings'),
      );
    }

    return StreamBuilder<List<ServiceSchedule>>(
      stream: ChurchService().getSchedules(churchId),
      builder: (context, snapshot) {
        final schedules = snapshot.data ?? const <ServiceSchedule>[];
        final next = _nextServiceFromSchedules(schedules);

        if (snapshot.connectionState == ConnectionState.waiting &&
            schedules.isEmpty) {
          return const _NextServiceCard(
            title: 'Loading next service...',
            subtitle: 'Checking your church service schedule',
            isLoading: true,
          );
        }

        if (snapshot.hasError && schedules.isEmpty) {
          return _NextServiceCard(
            title: 'Next service unavailable',
            subtitle: 'Could not load the church schedule right now.',
            buttonLabel: 'View Events',
            onPressed: () => Navigator.pushNamed(context, '/events'),
          );
        }

        if (next == null) {
          return _NextServiceCard(
            title: 'No upcoming service',
            subtitle: 'No recurring service schedule has been published yet.',
            buttonLabel: 'View Events',
            onPressed: () => Navigator.pushNamed(context, '/events'),
          );
        }

        return _NextServiceCard(
          title: next.schedule.name.isEmpty
              ? 'Church Service'
              : next.schedule.name,
          subtitle:
              '${_formatServiceDate(next.startsAt)} • ${_formatServiceTimeRange(next.schedule)}',
          buttonLabel: 'Watch Live',
          onPressed: () => Navigator.pushNamed(context, '/live_streaming'),
        );
      },
    );
  }

  _NextServiceInfo? _nextServiceFromSchedules(List<ServiceSchedule> schedules) {
    final now = DateTime.now();
    final upcoming = schedules
        .where((schedule) => schedule.attendanceEnabled)
        .map((schedule) {
          final startsAt = _nextOccurrence(now, schedule);
          if (startsAt == null) return null;
          return _NextServiceInfo(schedule: schedule, startsAt: startsAt);
        })
        .whereType<_NextServiceInfo>()
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    return upcoming.isEmpty ? null : upcoming.first;
  }

  DateTime? _nextOccurrence(DateTime now, ServiceSchedule schedule) {
    final start = _parseTime(schedule.startTime);
    if (start == null) return null;

    final daysUntil = (schedule.dayOfWeek - now.weekday) % 7;
    final date =
        DateTime(now.year, now.month, now.day).add(Duration(days: daysUntil));
    var startsAt = DateTime(
      date.year,
      date.month,
      date.day,
      start.hour,
      start.minute,
    );

    if (!startsAt.isAfter(now)) {
      startsAt = startsAt.add(const Duration(days: 7));
    }

    return startsAt;
  }

  _ClockTime? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return _ClockTime(hour, minute);
  }

  String _formatServiceDate(DateTime date) {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    final todayOnly = DateTime(today.year, today.month, today.day);
    final tomorrowOnly = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);

    if (dateOnly == todayOnly) return 'Today';
    if (dateOnly == tomorrowOnly) return 'Tomorrow';

    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  String _formatServiceTimeRange(ServiceSchedule schedule) {
    final start = _formatTime(schedule.startTime);
    final end = _formatTime(schedule.endTime);
    if (end.isEmpty || end == start) return start;
    return '$start - $end';
  }

  String _formatTime(String value) {
    final time = _parseTime(value);
    if (time == null) return '';

    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $suffix';
  }
}

class _NextServiceCard extends StatelessWidget {
  const _NextServiceCard({
    required this.title,
    required this.subtitle,
    this.buttonLabel,
    this.onPressed,
    this.isLoading = false,
  });

  final String title;
  final String subtitle;
  final String? buttonLabel;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
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
              if (isLoading) ...[
                const Spacer(),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white),
          ),
          if (buttonLabel != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(buttonLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _NextServiceInfo {
  const _NextServiceInfo({
    required this.schedule,
    required this.startsAt,
  });

  final ServiceSchedule schedule;
  final DateTime startsAt;
}

class _ClockTime {
  const _ClockTime(this.hour, this.minute);

  final int hour;
  final int minute;
}
