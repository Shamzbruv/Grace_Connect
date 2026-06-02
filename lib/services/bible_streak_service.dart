import 'package:shared_preferences/shared_preferences.dart';

class BibleStreakService {
  static const String _streakKey = 'bible_reading_streak_count';
  static const String _lastReadDateKey = 'bible_last_read_date';

  Future<int> currentStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final lastReadDate = _parseDate(prefs.getString(_lastReadDateKey));
    final streak = prefs.getInt(_streakKey) ?? 0;
    if (lastReadDate == null) return 0;

    final today = _dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    if (_sameDay(lastReadDate, today) || _sameDay(lastReadDate, yesterday)) {
      return streak;
    }

    await prefs.setInt(_streakKey, 0);
    return 0;
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
    return nextStreak;
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
}
