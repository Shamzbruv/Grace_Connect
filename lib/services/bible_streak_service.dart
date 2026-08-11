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

  factory BibleStreakStatus.fromMap(Map<String, dynamic> data) {
    return BibleStreakStatus(
      count: (data['count'] as num?)?.toInt() ?? 0,
      completedToday: data['completed_today'] == true,
      lastReadDate: DateTime.tryParse(data['last_read_date']?.toString() ?? ''),
    );
  }

  String get requirementText =>
      'Open any Bible chapter and spend at least 1 minute reading. Keep Grace Connect open on the Bible reader until the streak confirmation appears.';

  String get keepGoingText => completedToday
      ? 'Today is already counted. Come back tomorrow and read for 1 minute to keep your streak going.'
      : 'Read for 1 minute today to add 1 day to your streak. Missing a full day resets the count.';
}

class BibleStreakService {
  static const String _streakKey = 'bible_reading_streak_count';
  static const String _lastReadDateKey = 'bible_last_read_date';
  static const String _pendingReadDateKey = 'bible_pending_read_date';
  static const String _readingProgressDateKey = 'bible_reading_progress_date';
  static const String _readingProgressSecondsKey =
      'bible_reading_progress_seconds';
  BibleStreakService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<int> currentStreak() async {
    final status = await currentStatus();
    return status.count;
  }

  Future<BibleStreakStatus> currentStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await _preferenceKeys(prefs);

    await _flushPendingRead(prefs, keys);
    final remote = await _fetchRemoteStatus();
    if (remote != null) {
      await _saveLocalStatus(prefs, keys, remote);
      return remote;
    }

    final lastReadDate = _parseDate(prefs.getString(keys.lastReadDate));
    final streak = prefs.getInt(keys.streak) ?? 0;
    if (lastReadDate == null) {
      return const BibleStreakStatus(count: 0, completedToday: false);
    }

    final today = _today();
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

    await prefs.setInt(keys.streak, 0);
    return BibleStreakStatus(
      count: 0,
      completedToday: false,
      lastReadDate: lastReadDate,
    );
  }

  Future<int> recordQualifiedRead() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await _preferenceKeys(prefs);
    final today = _today();

    // Write the retry marker first. If the network request is interrupted, a
    // later app open on the same Jamaica day completes the server update.
    await prefs.setString(keys.pendingReadDate, _dateKey(today));
    final remote = await _recordRemoteRead();
    if (remote != null) {
      await _saveLocalStatus(prefs, keys, remote);
      await prefs.remove(keys.pendingReadDate);
      return remote.count;
    }

    final lastReadDate = _parseDate(prefs.getString(keys.lastReadDate));
    final current = prefs.getInt(keys.streak) ?? 0;

    if (lastReadDate != null && _sameDay(lastReadDate, today)) {
      return current;
    }

    final yesterday = today.subtract(const Duration(days: 1));
    final nextStreak = lastReadDate != null && _sameDay(lastReadDate, yesterday)
        ? current + 1
        : 1;

    await prefs.setInt(keys.streak, nextStreak);
    await prefs.setString(keys.lastReadDate, _dateKey(today));
    return nextStreak;
  }

  Future<int> recordFiveMinuteRead() {
    return recordQualifiedRead();
  }

  /// Adds foreground reading time across chapter changes. Returning a value
  /// means the one-minute daily qualification was reached and recorded.
  Future<int?> addActiveReadingTime(Duration elapsed) async {
    if (elapsed <= Duration.zero) return null;
    final prefs = await SharedPreferences.getInstance();
    final keys = await _preferenceKeys(prefs);
    final today = _today();
    final lastReadDate = _parseDate(prefs.getString(keys.lastReadDate));
    if (lastReadDate != null && _sameDay(lastReadDate, today)) return null;
    final progressDate = _parseDate(prefs.getString(keys.progressDate));
    var seconds = prefs.getInt(keys.progressSeconds) ?? 0;
    if (progressDate == null || !_sameDay(progressDate, today)) {
      seconds = 0;
      await prefs.setString(keys.progressDate, _dateKey(today));
    }
    seconds = (seconds + elapsed.inSeconds).clamp(0, 60).toInt();
    await prefs.setInt(keys.progressSeconds, seconds);
    if (seconds < 60) return null;
    return recordQualifiedRead();
  }

  Future<List<BibleStreakLeaderboardEntry>> fetchChurchLeaderboard({
    int limit = 25,
  }) async {
    try {
      final rows = await _supabase.rpc(
        'list_bible_streak_leaderboard',
        params: {'result_limit': limit},
      );
      if (rows is! List) return const [];
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
      debugPrint('Bible streak leaderboard RPC unavailable: $error');
      return const [];
    }
  }

  Future<BibleStreakStatus?> _fetchRemoteStatus() async {
    try {
      if (_supabase.auth.currentUser == null) return null;
      final data = await _supabase.rpc('get_my_bible_streak_status');
      if (data is Map) {
        return BibleStreakStatus.fromMap(Map<String, dynamic>.from(data));
      }
    } catch (error) {
      debugPrint('Bible streak status is using the offline fallback: $error');
    }
    return null;
  }

  Future<BibleStreakStatus?> _recordRemoteRead() async {
    try {
      if (_supabase.auth.currentUser == null) return null;
      final data = await _supabase.rpc('record_my_bible_reading');
      if (data is Map) {
        return BibleStreakStatus.fromMap(Map<String, dynamic>.from(data));
      }
    } catch (error) {
      debugPrint('Bible streak read will retry when online: $error');
    }
    return null;
  }

  Future<void> _flushPendingRead(
    SharedPreferences prefs,
    _BibleStreakPreferenceKeys keys,
  ) async {
    final pending = _parseDate(prefs.getString(keys.pendingReadDate));
    if (pending == null) return;
    if (!_sameDay(pending, _today())) {
      await prefs.remove(keys.pendingReadDate);
      return;
    }
    final remote = await _recordRemoteRead();
    if (remote == null) return;
    await _saveLocalStatus(prefs, keys, remote);
    await prefs.remove(keys.pendingReadDate);
  }

  Future<void> _saveLocalStatus(
    SharedPreferences prefs,
    _BibleStreakPreferenceKeys keys,
    BibleStreakStatus status,
  ) async {
    await prefs.setInt(keys.streak, status.count);
    if (status.lastReadDate == null) {
      await prefs.remove(keys.lastReadDate);
    } else {
      await prefs.setString(keys.lastReadDate, _dateKey(status.lastReadDate!));
    }
  }

  Future<_BibleStreakPreferenceKeys> _preferenceKeys(
    SharedPreferences prefs,
  ) async {
    var owner = 'signed_out';
    try {
      owner = _supabase.auth.currentUser?.id ?? owner;
    } catch (_) {
      // Supabase is deliberately not initialized in unit tests.
    }
    final safeOwner = owner.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final keys = _BibleStreakPreferenceKeys(
      streak: '${_streakKey}_$safeOwner',
      lastReadDate: '${_lastReadDateKey}_$safeOwner',
      pendingReadDate: '${_pendingReadDateKey}_$safeOwner',
      progressDate: '${_readingProgressDateKey}_$safeOwner',
      progressSeconds: '${_readingProgressSecondsKey}_$safeOwner',
    );

    // One-time compatibility import for builds that used device-global keys.
    if (!prefs.containsKey(keys.streak) && prefs.containsKey(_streakKey)) {
      await prefs.setInt(keys.streak, prefs.getInt(_streakKey) ?? 0);
    }
    if (!prefs.containsKey(keys.lastReadDate) &&
        prefs.containsKey(_lastReadDateKey)) {
      final legacyDate = prefs.getString(_lastReadDateKey);
      if (legacyDate != null) {
        await prefs.setString(keys.lastReadDate, legacyDate);
      }
    }
    if (owner != 'signed_out') {
      await prefs.remove(_streakKey);
      await prefs.remove(_lastReadDateKey);
    }
    return keys;
  }

  DateTime? _parseDate(String? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : _dateOnly(parsed);
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _today() {
    final jamaicaNow = _now().toUtc().subtract(const Duration(hours: 5));
    return DateTime(jamaicaNow.year, jamaicaNow.month, jamaicaNow.day);
  }

  String _dateKey(DateTime value) =>
      _dateOnly(value).toIso8601String().substring(0, 10);

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

class _BibleStreakPreferenceKeys {
  const _BibleStreakPreferenceKeys({
    required this.streak,
    required this.lastReadDate,
    required this.pendingReadDate,
    required this.progressDate,
    required this.progressSeconds,
  });

  final String streak;
  final String lastReadDate;
  final String pendingReadDate;
  final String progressDate;
  final String progressSeconds;
}
