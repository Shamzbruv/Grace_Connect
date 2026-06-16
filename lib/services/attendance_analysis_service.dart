import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/attendance_record.dart';
import '../models/priority_follow_up.dart';
import '../models/user_profile.dart';

class AttendanceAnalysisService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const int defaultAlertThresholdWeeks = 2;

  Future<int> getAlertThresholdWeeks(String churchId) async {
    try {
      final row = await _supabase
          .from('church_attendance_alert_settings')
          .select('absence_threshold_weeks')
          .eq('church_id', churchId)
          .maybeSingle();
      final value = row?['absence_threshold_weeks'];
      if (value is int) return value.clamp(1, 26).toInt();
      if (value is num) return value.toInt().clamp(1, 26).toInt();
    } catch (_) {
      // Older databases did not have configurable attendance alerts.
    }
    return defaultAlertThresholdWeeks;
  }

  Future<void> saveAlertThresholdWeeks(String churchId, int weeks) async {
    final cleanWeeks = weeks.clamp(1, 26);
    await _supabase.from('church_attendance_alert_settings').upsert({
      'church_id': churchId,
      'absence_threshold_weeks': cleanWeeks,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'updated_by': _supabase.auth.currentUser?.id,
    }, onConflict: 'church_id');
  }

  // 1. Get Priority Follow-Up List for Church
  Stream<List<PriorityFollowUp>> getPriorityList(String churchId) {
    return _supabase
        .from('priority_follow_ups')
        .stream(primaryKey: ['id'])
        .eq('churchId', churchId)
        .order('flaggedAt', ascending: false)
        .map((docs) => docs
            .where(
                (doc) => doc['status'] == 'open') // Filter active items in Dart
            .map((doc) => PriorityFollowUp.fromMap(doc))
            .toList());
  }

  Future<List<PriorityFollowUp>> fetchPriorityList(String churchId) async {
    final rows = await _supabase
        .from('priority_follow_ups')
        .select()
        .eq('churchId', churchId)
        .eq('status', 'open')
        .order('flaggedAt', ascending: false);
    return rows
        .map<PriorityFollowUp>((row) => PriorityFollowUp.fromMap(row))
        .toList();
  }

  Future<Map<String, PriorityFollowUp>> getOpenFollowUpsByUserIds(
    String churchId,
    Iterable<String> userIds,
  ) async {
    final ids = userIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return {};

    final rows = await _supabase
        .from('priority_follow_ups')
        .select()
        .eq('churchId', churchId)
        .eq('status', 'open')
        .inFilter('userId', ids);

    final result = <String, PriorityFollowUp>{};
    for (final row in rows) {
      final followUp = PriorityFollowUp.fromMap(row);
      if (followUp.userId.isNotEmpty) {
        result[followUp.userId] = followUp;
      }
    }
    return result;
  }

  // 2. Resolve a Flag (Pastor only logic controlled by UI, backend validates existence)
  Future<void> resolveFlag(
      String flagId, String resolvedByUserId, String method) async {
    // method: 'resolved' or 'acknowledged' (if acknowledging keeps it but changes status)
    // Requirement says "Acknowledges and removes it" or "marks resolved".
    // We'll mark status as 'resolved' to hide from open list.

    await _supabase.from('priority_follow_ups').update({
      'status': 'resolved',
      'resolvedBy': resolvedByUserId,
      'resolvedAt': DateTime.now().toIso8601String(),
    }).eq('id', flagId);
  }

  // 3. Refresh/Generate Flags (Lazy Job)
  // This should be called when opening the Attendance Insights page.
  // It iterates active members, checks their last 4 weeks, and creates triggers.
  // NOTE: In a real app with thousands of users, this should be a Cloud Function.
  // For MVP client-side, we limit to batch size or expect smaller church sizes (<500).
  Future<void> refreshPriorityList(String churchId,
      {int? thresholdWeeks}) async {
    final threshold = thresholdWeeks ?? await getAlertThresholdWeeks(churchId);

    // A. Get all members of church
    final membersSnapshot =
        await _supabase.from('users').select().eq('placeId', churchId);

    final now = DateTime.now();

    for (var doc in membersSnapshot) {
      final user = UserProfile.fromMap(doc);
      if (user.uid.isEmpty || user.accountState == 'deletion_requested') {
        continue;
      }

      // Check if already flagged and open
      final existingFlag = await _supabase
          .from('priority_follow_ups')
          .select('id')
          .eq('userId', user.uid)
          .eq('churchId', churchId)
          .eq('status', 'open')
          .limit(1);
      final existingFlags = (existingFlag as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      final lastDate = await _lastPresentDate(user.uid, churchId);
      final baseline = lastDate ?? user.joinDate;
      final daysAbsent = now.difference(baseline).inDays;
      final weeksAbsent = daysAbsent <= 0 ? 0 : daysAbsent ~/ 7;

      if (weeksAbsent >= threshold) {
        final followUp = PriorityFollowUp(
          id: existingFlags.isNotEmpty
              ? existingFlags.first['id']?.toString() ?? const Uuid().v4()
              : const Uuid().v4(),
          userId: user.uid,
          userName: user.fullName,
          userPhotoUrl: user.photoUrl,
          churchId: churchId,
          flaggedAt: DateTime.now(),
          absenceStreakWeeks: weeksAbsent,
          lastAttendedDate: lastDate,
          status: 'open',
        );

        if (existingFlags.isNotEmpty) {
          await _supabase.from('priority_follow_ups').update({
            'userName': followUp.userName,
            'userPhotoUrl': followUp.userPhotoUrl,
            'absenceStreakWeeks': followUp.absenceStreakWeeks,
            'lastAttendedDate': followUp.lastAttendedDate?.toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          }).eq('id', followUp.id);
        } else {
          await _supabase.from('priority_follow_ups').insert(followUp.toMap());
        }
      } else if (existingFlags.isNotEmpty) {
        await _supabase.from('priority_follow_ups').update({
          'status': 'resolved',
          'resolvedAt': DateTime.now().toIso8601String(),
          'resolvedBy': _supabase.auth.currentUser?.id,
          'updatedAt': DateTime.now().toIso8601String(),
        }).eq('id', existingFlags.first['id']);
      }
    }
  }

  Future<DateTime?> _lastPresentDate(String userId, String churchId) async {
    final lastAttendanceQuery = await _supabase
        .from('attendance')
        .select()
        .eq('user_id', userId)
        .eq('church_id', churchId)
        .eq('present', true)
        .order('timestamp', ascending: false)
        .limit(1);

    if ((lastAttendanceQuery as List).isEmpty) return null;
    final record = AttendanceRecord.fromMap(lastAttendanceQuery.first);
    return record.timestamp;
  }

  // 4. Get Basic Engagement Stats
  Future<Map<String, dynamic>> getEngagementStats(String churchId) async {
    // Mocking some aggregate stats for the chart as Firestore aggregation is heavy client-side
    // In production, use Count queries or dedicated localized increments

    final countList = await _supabase
        .from('attendance')
        .select('id')
        .eq('church_id', churchId)
        .gt('timestamp',
            DateTime.now().subtract(const Duration(days: 7)).toIso8601String());

    return {
      'weeklyAttendance': (countList as List).length,
      // 'trend': '+5%', // Removed placeholder logic, real trend computation needs to be implemented.
    };
  }
}
