import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/attendance_record.dart';
import '../models/priority_follow_up.dart';
import '../models/user_profile.dart';

class AttendanceAnalysisService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // 1. Get Priority Follow-Up List for Church
  Stream<List<PriorityFollowUp>> getPriorityList(String churchId) {
    return _supabase
        .from('priority_follow_ups')
        .stream(primaryKey: ['id'])
        .eq('churchId', churchId)
        .order('flaggedAt', ascending: false)
        .map((docs) => docs
            .where((doc) => doc['status'] == 'open') // Filter active items in Dart
            .map((doc) => PriorityFollowUp.fromMap(doc))
            .toList());
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
  Future<void> refreshPriorityList(String churchId) async {
    // A. Get all members of church
    final membersSnapshot = await _supabase
        .from('users')
        .select()
        .eq('placeId', churchId);

    // B. Define "4 weeks ago" window
    final now = DateTime.now();
    final fourWeeksAgo = now.subtract(const Duration(days: 28));

    for (var doc in membersSnapshot) {
      final user = UserProfile.fromMap(doc);

      // Check if already flagged and open
      final existingFlag = await _supabase
          .from('priority_follow_ups')
          .select('id')
          .eq('userId', user.uid)
          .eq('status', 'open')
          .limit(1);

      if ((existingFlag as List).isNotEmpty) continue; // Already flagged

      // Check attendance in last 4 weeks
      final attendanceSnapshot = await _supabase
          .from('attendance')
          .select('id')
          .eq('user_id', user.uid)
          .eq('church_id', churchId)
          .gt('timestamp', fourWeeksAgo.toIso8601String())
          .limit(1);

      if ((attendanceSnapshot as List).isEmpty) {
        // No attendance in last 4 weeks!
        // Get LAST known attendance date (to calculate streak/show data)
        final lastAttendanceQuery = await _supabase
            .from('attendance')
            .select()
            .eq('user_id', user.uid)
            .eq('church_id', churchId)
            .order('timestamp', ascending: false)
            .limit(1);

        DateTime? lastDate;
        if ((lastAttendanceQuery as List).isNotEmpty) {
          final record = AttendanceRecord.fromMap(lastAttendanceQuery.first);
          lastDate = record.timestamp;
        }

        // Create Flag
        // Calculate weeks absent roughly
        int weeksAbsent = 4;
        if (lastDate != null) {
          final diff = now.difference(lastDate).inDays;
          weeksAbsent = (diff / 7).floor();
        } else {
          // Never attended? Maybe ignore or flag as "New/Inactive"
          // For now, if they are a member and have NO attendance, flag them.
          weeksAbsent = 99;
        }

        final followUp = PriorityFollowUp(
          id: const Uuid().v4(),
          userId: user.uid,
          userName: user.fullName,
          userPhotoUrl: user.photoUrl,
          churchId: churchId,
          flaggedAt: DateTime.now(),
          absenceStreakWeeks: weeksAbsent,
          lastAttendedDate: lastDate,
          status: 'open',
        );

        await _supabase
            .from('priority_follow_ups')
            .insert(followUp.toMap());
      }
    }
  }

  // 4. Get Basic Engagement Stats
  Future<Map<String, dynamic>> getEngagementStats(String churchId) async {
    // Mocking some aggregate stats for the chart as Firestore aggregation is heavy client-side
    // In production, use Count queries or dedicated localized increments

    final countList = await _supabase
        .from('attendance')
        .select('id')
        .eq('church_id', churchId)
        .gt('timestamp', DateTime.now().subtract(const Duration(days: 7)).toIso8601String());

    return {
      'weeklyAttendance': (countList as List).length,
      // 'trend': '+5%', // Removed placeholder logic, real trend computation needs to be implemented.
    };
  }
}
