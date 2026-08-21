import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/church_stats.dart';

class ChurchStatsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Real attendance per calendar week over the last [weekCount] weeks,
  /// summed from the server-side finalized-service closeout (present + late
  /// + remote, i.e. everyone who actually attended one way or another).
  /// Weeks with no finalized service are a genuine 0, not a placeholder --
  /// unlike the old hardcoded stub, every point here is real.
  Future<(List<double>, List<String>)> _weeklyAttendanceTrend(
    String churchId, {
    int weekCount = 8,
  }) async {
    final now = DateTime.now();
    final lastSunday = now.subtract(Duration(days: now.weekday % 7));
    final currentWeekStart =
        DateTime(lastSunday.year, lastSunday.month, lastSunday.day);
    final earliestWeekStart =
        currentWeekStart.subtract(Duration(days: 7 * (weekCount - 1)));

    final rows = await _supabase
        .from('attendance_finalized_services')
        .select('service_date, present_count, late_count, remote_count')
        .eq('church_id', churchId)
        .gte('service_date', earliestWeekStart.toIso8601String())
        .lte('service_date', now.toIso8601String());

    final totalsByWeekStart = <DateTime, double>{};
    for (final row in rows) {
      final serviceDate =
          DateTime.tryParse(row['service_date']?.toString() ?? '');
      if (serviceDate == null) continue;
      final daysSinceSunday = serviceDate.weekday % 7;
      final weekStart = DateTime(
        serviceDate.year,
        serviceDate.month,
        serviceDate.day,
      ).subtract(Duration(days: daysSinceSunday));
      final attended = ((row['present_count'] as num?) ?? 0) +
          ((row['late_count'] as num?) ?? 0) +
          ((row['remote_count'] as num?) ?? 0);
      totalsByWeekStart[weekStart] =
          (totalsByWeekStart[weekStart] ?? 0) + attended.toDouble();
    }

    final labelFormat = DateFormat('MMM d');
    final trend = <double>[];
    final labels = <String>[];
    for (var i = 0; i < weekCount; i++) {
      final weekStart = earliestWeekStart.add(Duration(days: 7 * i));
      trend.add(totalsByWeekStart[weekStart] ?? 0);
      labels.add(labelFormat.format(weekStart));
    }
    return (trend, labels);
  }

  Future<ChurchStats> getStats(String churchId) async {
    try {
      final membersCountRes = await _supabase
          .from('users')
          .select('uid')
          .eq('placeId', churchId)
          .count(CountOption.exact);

      // Calculate start/end of current week (Sunday to now)
      final now = DateTime.now();
      final lastSunday = now.subtract(Duration(days: now.weekday % 7));
      final startOfWeek =
          DateTime(lastSunday.year, lastSunday.month, lastSunday.day);

      final attendanceCountRes = await _supabase
          .from('attendance')
          .select('id')
          .eq('church_id', churchId)
          .gte('timestamp', startOfWeek.toIso8601String())
          .count(CountOption.exact);

      final startOfLastWeek = startOfWeek.subtract(const Duration(days: 7));
      final endOfLastWeek = startOfWeek.subtract(const Duration(seconds: 1));

      final lastWeekAttendanceRes = await _supabase
          .from('attendance')
          .select('id')
          .eq('church_id', churchId)
          .gte('timestamp', startOfLastWeek.toIso8601String())
          .lte('timestamp', endOfLastWeek.toIso8601String())
          .count(CountOption.exact);

      var ministryCount = 0;
      try {
        final ministriesCountRes = await _supabase
            .from('ministries')
            .select('id')
            .eq('church_id', churchId)
            .eq('status', 'active')
            .count(CountOption.exact);
        ministryCount = ministriesCountRes.count;
      } catch (error) {
        debugPrint('Falling back to study group ministry count: $error');
        final studyGroupsCountRes = await _supabase
            .from('study_groups')
            .select('id')
            .eq('churchId', churchId)
            .count(CountOption.exact);
        ministryCount = studyGroupsCountRes.count;
      }

      final currentWeekCount = attendanceCountRes.count;
      final prevWeekCount = lastWeekAttendanceRes.count;

      var weeklyTrend = <double>[];
      var weeklyTrendLabels = <String>[];
      try {
        final trend = await _weeklyAttendanceTrend(churchId);
        weeklyTrend = trend.$1;
        weeklyTrendLabels = trend.$2;
      } catch (error) {
        debugPrint('Falling back to empty weekly trend: $error');
      }

      return ChurchStats(
        attendanceThisWeek: currentWeekCount,
        attendanceLastWeek: prevWeekCount,
        activeMembers: membersCountRes.count,
        sundaySchoolAdults: 0, // Future capability
        sundaySchoolYouth: 0, // Future capability
        sundaySchoolKids: 0, // Future capability
        ministryCount: ministryCount,
        weeklyTrend: weeklyTrend,
        weeklyTrendLabels: weeklyTrendLabels,
      );
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      return ChurchStats.empty();
    }
  }
}
