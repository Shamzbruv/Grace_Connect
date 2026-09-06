import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/services/notification_service.dart';

void main() {
  group('Notification destination resolution', () {
    test('opens a direct message through its parent lookup', () {
      expect(
          NotificationService.resolveRoute(
              route: '/inbox',
              type: 'direct_message',
              entityTable: 'direct_messages',
              entityId: 'message-123'),
          '/notification_target?table=direct_messages&id=message-123');
    });
    test('does not treat a room message id as a room id', () {
      expect(
          NotificationService.resolveRoute(
              route: '/grace_rooms',
              type: 'message',
              entityTable: 'grace_room_messages',
              entityId: 'message-123'),
          '/notification_target?table=grace_room_messages&id=message-123');
    });
    test('role changes do not open an unrelated public profile', () {
      expect(
          NotificationService.resolveRoute(
              route: '/notifications',
              type: 'role_changed',
              entityTable: 'users',
              entityId: 'user-123'),
          '/notifications');
    });
    test('events and announcements open the referenced item', () {
      for (final table in ['events', 'announcements']) {
        expect(
            NotificationService.resolveRoute(
                route: '/$table',
                type: table,
                entityTable: table,
                entityId: 'item-1'),
            '/notification_target?table=$table&id=item-1');
      }
    });
    test('custom deep links preserve the room path', () {
      expect(
          NotificationService.normalizeRoute(
              'graceconnect://grace_rooms/room?id=room-1'),
          '/grace_rooms/room?id=room-1');
      expect(
          NotificationService.normalizeRoute('https://unrelated.example/inbox'),
          isNull);
      expect(NotificationService.normalizeRoute('//unrelated.example/inbox'),
          isNull);
    });
  });
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
