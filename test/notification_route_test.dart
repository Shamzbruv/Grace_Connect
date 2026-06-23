import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/services/notification_service.dart';

void main() {
  group('Notification route normalization', () {
    test('keeps app routes with query strings', () {
      expect(
        NotificationService.normalizeRoute('/daily_bible_quiz?month=2026-06'),
        '/daily_bible_quiz?month=2026-06',
      );
      expect(
        NotificationService.normalizeRoute('/daily_word?id=abc123'),
        '/daily_word?id=abc123',
      );
    });

    test('normalizes app deep-link URLs to in-app routes', () {
      expect(
        NotificationService.normalizeRoute(
          'graceconnect://daily_bible_quiz?quizId=7',
        ),
        '/daily_bible_quiz?quizId=7',
      );
      expect(
        NotificationService.normalizeRoute(
          'https://graceconnect.app/live_streaming',
        ),
        '/live_streaming',
      );
    });

    test('rejects unsafe relative routes', () {
      expect(NotificationService.normalizeRoute('daily_bible_quiz'), isNull);
      expect(NotificationService.normalizeRoute(''), isNull);
    });
  });
}
