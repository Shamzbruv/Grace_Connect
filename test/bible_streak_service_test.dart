import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/services/bible_streak_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime.utc(2026, 8, 5, 17);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('records a daily streak once per day', () async {
    final service = BibleStreakService(now: () => fixedNow);

    expect(await service.currentStreak(), 0);
    expect(await service.recordFiveMinuteRead(), 1);
    expect(await service.recordFiveMinuteRead(), 1);
    expect(await service.currentStreak(), 1);
  });

  test('continues the streak when the previous read was yesterday', () async {
    final yesterday = DateTime(2026, 8, 4);
    SharedPreferences.setMockInitialValues({
      'bible_reading_streak_count': 3,
      'bible_last_read_date': DateTime(
        yesterday.year,
        yesterday.month,
        yesterday.day,
      ).toIso8601String(),
    });

    final service = BibleStreakService(now: () => fixedNow);

    expect(await service.currentStreak(), 3);
    expect(await service.recordFiveMinuteRead(), 4);
  });

  test('resets an expired streak', () async {
    final olderRead = DateTime(2026, 8, 3);
    SharedPreferences.setMockInitialValues({
      'bible_reading_streak_count': 7,
      'bible_last_read_date': DateTime(
        olderRead.year,
        olderRead.month,
        olderRead.day,
      ).toIso8601String(),
    });

    final service = BibleStreakService(now: () => fixedNow);

    expect(await service.currentStreak(), 0);
    expect(await service.recordFiveMinuteRead(), 1);
  });

  test('uses the Jamaica calendar day at the UTC boundary', () async {
    final justBeforeMidnightInJamaica = DateTime.utc(2026, 8, 6, 4, 59);
    SharedPreferences.setMockInitialValues({
      'bible_reading_streak_count': 2,
      'bible_last_read_date': '2026-08-04',
    });

    final service = BibleStreakService(now: () => justBeforeMidnightInJamaica);

    expect(await service.recordQualifiedRead(), 3);
  });

  test('does not carry a stale streak into a new reading day', () async {
    SharedPreferences.setMockInitialValues({
      'bible_reading_streak_count': 12,
      'bible_last_read_date': '2026-08-02',
    });
    final service = BibleStreakService(now: () => fixedNow);

    final beforeRead = await service.currentStatus();
    expect(beforeRead.count, 0);
    expect(beforeRead.completedToday, isFalse);
    expect(await service.recordQualifiedRead(), 1);
  });

  test('accumulates one reading minute across chapter screens', () async {
    final firstScreen = BibleStreakService(now: () => fixedNow);
    final secondScreen = BibleStreakService(now: () => fixedNow);

    expect(
      await firstScreen.addActiveReadingTime(const Duration(seconds: 35)),
      isNull,
    );
    expect(
      await secondScreen.addActiveReadingTime(const Duration(seconds: 25)),
      1,
    );
    expect(await secondScreen.currentStreak(), 1);
  });
}
