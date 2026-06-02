import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/services/bible_streak_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('records a daily streak once per day', () async {
    final service = BibleStreakService();

    expect(await service.currentStreak(), 0);
    expect(await service.recordFiveMinuteRead(), 1);
    expect(await service.recordFiveMinuteRead(), 1);
    expect(await service.currentStreak(), 1);
  });

  test('continues the streak when the previous read was yesterday', () async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    SharedPreferences.setMockInitialValues({
      'bible_reading_streak_count': 3,
      'bible_last_read_date': DateTime(
        yesterday.year,
        yesterday.month,
        yesterday.day,
      ).toIso8601String(),
    });

    final service = BibleStreakService();

    expect(await service.currentStreak(), 3);
    expect(await service.recordFiveMinuteRead(), 4);
  });

  test('resets an expired streak', () async {
    final olderRead = DateTime.now().subtract(const Duration(days: 2));
    SharedPreferences.setMockInitialValues({
      'bible_reading_streak_count': 7,
      'bible_last_read_date': DateTime(
        olderRead.year,
        olderRead.month,
        olderRead.day,
      ).toIso8601String(),
    });

    final service = BibleStreakService();

    expect(await service.currentStreak(), 0);
    expect(await service.recordFiveMinuteRead(), 1);
  });
}
