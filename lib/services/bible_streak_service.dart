import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BibleStreakLeaderboardEntry {
  const BibleStreakLeaderboardEntry({
    required this.userId,
    required this.userName,
    required this.streakCount,
    this.photoUrl,
    this.lastReadDate,
  });

  final String userId;
  final String userName;
  final int streakCount;
  final String? photoUrl;
  final DateTime? lastReadDate;

  factory BibleStreakLeaderboardEntry.fromMap(Map<String, dynamic> data) {
    return BibleStreakLeaderboardEntry(
      userId: data['user_id']?.toString() ?? '',
      userName: data['user_name']?.toString() ?? 'Member',
      streakCount: data['streak_count'] as int? ?? 0,
      photoUrl: data['photo_url']?.toString(),
      lastReadDate: DateTime.tryParse(data['last_read_date']?.toString() ?? ''),
    );
  }
}

class BibleStreakStatus {
  const BibleStreakStatus({
    required this.count,
    required this.completedToday,
    this.lastReadDate,
  });

  final int count;
  final bool completedToday;
  final DateTime? lastReadDate;

  String get requirementText =>
      'Open any Bible chapter and spend at least 5 minutes reading. Keep Grace Connect open on the Bible reader until the streak confirmation appears.';

  String get keepGoingText => completedToday
      ? 'Today is already counted. Come back tomorrow and read for 5 minutes to keep your streak going.'
      : 'Read for 5 minutes today to add 1 day to your streak. Missing a full day resets the count.';
}

class BibleStreakService {
  static const String _streakKey = 'bible_reading_streak_count';
  static const String _lastReadDateKey = 'bible_last_read_date';
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<int> currentStreak() async {
    final status = await currentStatus();
    return status.count;
  }

  Future<BibleStreakStatus> currentStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lastReadDate = _parseDate(prefs.getString(_lastReadDateKey));
    final streak = prefs.getInt(_streakKey) ?? 0;
    if (lastReadDate == null) {
      return const BibleStreakStatus(count: 0, completedToday: false);
    }

    final today = _dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    if (_sameDay(lastReadDate, today)) {
      return BibleStreakStatus(
        count: streak,
        completedToday: true,
        lastReadDate: lastReadDate,
      );
    }
    if (_sameDay(lastReadDate, yesterday)) {
      return BibleStreakStatus(
        count: streak,
        completedToday: false,
        lastReadDate: lastReadDate,
      );
    }

    await prefs.setInt(_streakKey, 0);
    return BibleStreakStatus(
      count: 0,
      completedToday: false,
      lastReadDate: lastReadDate,
    );
  }

  Future<int> recordFiveMinuteRead() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateOnly(DateTime.now());
    final lastReadDate = _parseDate(prefs.getString(_lastReadDateKey));
    final current = prefs.getInt(_streakKey) ?? 0;

    if (lastReadDate != null && _sameDay(lastReadDate, today)) {
      return current;
    }

    final yesterday = today.subtract(const Duration(days: 1));
    final nextStreak = lastReadDate != null && _sameDay(lastReadDate, yesterday)
        ? current + 1
        : 1;

    await prefs.setInt(_streakKey, nextStreak);
    await prefs.setString(_lastReadDateKey, today.toIso8601String());
    await _syncRemoteStreak(nextStreak, today);
    return nextStreak;
  }

  Future<List<BibleStreakLeaderboardEntry>> fetchChurchLeaderboard({
    int limit = 25,
  }) async {
    try {
      final rows = await _supabase
          .from('bible_streaks')
          .select()
          .order('streak_count', ascending: false)
          .order('last_read_date', ascending: false)
          .limit(limit);
      return rows
          .map<BibleStreakLeaderboardEntry>(
            (row) => BibleStreakLeaderboardEntry.fromMap(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();
    } on PostgrestException catch (error) {
      if (_isMissingLeaderboardTable(error)) {
        debugPrint('Bible streak leaderboard setup pending: $error');
        return const [];
      }
      rethrow;
    }
  }

  Future<void> _syncRemoteStreak(int streak, DateTime date) async {
    try {
      if (_supabase.auth.currentUser == null) return;
      await _supabase.rpc(
        'upsert_my_bible_streak',
        params: {
          'streak_count': streak,
          'last_read_date': _dateOnly(date).toIso8601String().substring(0, 10),
        },
      );
    } catch (_) {
      // Local streaks should continue to work even when Supabase is offline,
      // uninitialized in tests, or the migration has not been applied yet.
    }
  }

  DateTime? _parseDate(String? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : _dateOnly(parsed);
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isMissingLeaderboardTable(PostgrestException error) {
    final message = error.message.toLowerCase();
    return error.code == 'PGRST205' ||
        error.code == '42P01' ||
        message.contains('bible_streaks') &&
            (message.contains('could not find') ||
                message.contains('does not exist'));
  }
}
