import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/church_stats.dart';

class ChurchStatsService {
  final SupabaseClient _supabase = Supabase.instance.client;

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
          .eq('churchId', churchId)
          .gte('timestamp', startOfWeek.toIso8601String())
          .count(CountOption.exact);

      final startOfLastWeek = startOfWeek.subtract(const Duration(days: 7));
      final endOfLastWeek = startOfWeek.subtract(const Duration(seconds: 1));

      final lastWeekAttendanceRes = await _supabase
          .from('attendance')
          .select('id')
          .eq('churchId', churchId)
          .gte('timestamp', startOfLastWeek.toIso8601String())
          .lte('timestamp', endOfLastWeek.toIso8601String())
          .count(CountOption.exact);

      final ministriesCountRes = await _supabase
          .from('study_groups')
          .select('id')
          .eq('churchId', churchId)
          .count(CountOption.exact);

      final currentWeekCount = attendanceCountRes.count;
      final prevWeekCount = lastWeekAttendanceRes.count;

      return ChurchStats(
        attendanceThisWeek: currentWeekCount,
        attendanceLastWeek: prevWeekCount,
        activeMembers: membersCountRes.count,
        sundaySchoolAdults: 0, // Future capability
        sundaySchoolYouth: 0, // Future capability
        sundaySchoolKids: 0, // Future capability
        ministryCount: ministriesCountRes.count,
        weeklyTrend: [
          0.0,
          0.0,
          0.0,
          prevWeekCount.toDouble(),
          currentWeekCount.toDouble()
        ],
      );
    } catch (e) {
      debugPrint('Error fetching stats: $e');
      return ChurchStats.empty();
    }
  }
}
