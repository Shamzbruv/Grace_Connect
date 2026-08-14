import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/event_model.dart';
import 'package:grace_connect/services/event_service.dart';
import 'package:grace_connect/utils/event_link.dart';

EventModel _event({
  required String id,
  String title = 'Community Breakfast',
  String churchId = 'church-1',
  String organizerId = 'user-1',
  String? ministryId,
  DateTime? date,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return EventModel(
    id: id,
    title: title,
    description: 'Breakfast and fellowship.',
    date: date ?? DateTime.utc(2027, 1, 10, 14),
    time: '9:00 AM',
    churchId: churchId,
    organizerId: organizerId,
    ministryId: ministryId,
    createdAt: createdAt ?? DateTime.utc(2026, 8, 14),
    updatedAt: updatedAt ?? DateTime.utc(2026, 8, 14),
  );
}

void main() {
  group('event links', () {
    test('normalizes convenient public links to HTTPS', () {
      expect(
        EventLink.normalize('  zoom.us/j/123?pwd=abc  '),
        'https://zoom.us/j/123?pwd=abc',
      );
      expect(
        EventLink.normalize('https://events.example.org/register'),
        'https://events.example.org/register',
      );
    });

    test('rejects insecure, credentialed, and local destinations', () {
      for (final link in const [
        'http://events.example.org',
        'javascript:alert(1)',
        'https://user:password@example.org',
        'https://localhost/event',
        'https://127.0.0.1/event',
        'https://[::1]/event',
        'https://single-label/event',
      ]) {
        expect(EventLink.normalize(link), isNull, reason: link);
      }
    });
  });

  group('event model and local feed guard', () {
    test('preserves optional URL, duration, update version, and end time', () {
      final event = EventModel.fromMap({
        'id': 'event-1',
        'title': 'Prayer Night',
        'description': 'Join us.',
        'date': '2027-01-10T14:00:00.000Z',
        'time': '9:00 AM',
        'event_url': 'https://meet.example.org/prayer',
        'duration_minutes': 120,
        'churchId': 'church-1',
        'organizerId': 'user-1',
        'createdAt': '2026-08-14T12:00:00.000Z',
        'updated_at': '2026-08-15T12:00:00.000Z',
      });

      expect(event.eventUrl, 'https://meet.example.org/prayer');
      expect(event.durationMinutes, 120);
      expect(event.endDate, DateTime.utc(2027, 1, 10, 16));
      expect(event.toMap()['updated_at'], '2026-08-15T12:00:00.000Z');
    });

    test('deduplicates one canonical occurrence but keeps real differences',
        () {
      final first = _event(id: 'first');
      final duplicate = _event(
        id: 'duplicate',
        title: '  COMMUNITY   breakfast ',
        createdAt: DateTime.utc(2026, 8, 15),
      );
      final otherOrganizer = _event(
        id: 'other-user',
        organizerId: 'user-2',
        createdAt: DateTime.utc(2026, 8, 16),
      );
      final otherTime = _event(
        id: 'other-time',
        date: DateTime.utc(2027, 1, 10, 15),
      );
      final otherMinistry = _event(
        id: 'other-ministry',
        ministryId: '00000000-0000-0000-0000-000000000123',
      );

      final result = EventService.deduplicateEvents([
        duplicate,
        otherOrganizer,
        first,
        otherTime,
        otherMinistry,
      ]);

      expect(
        result.map((event) => event.id),
        containsAll(['first', 'other-time', 'other-ministry']),
      );
      expect(result.map((event) => event.id), isNot(contains('duplicate')));
      expect(result.map((event) => event.id), isNot(contains('other-user')));
      expect(result, hasLength(3));
    });

    test('same row id keeps its newest realtime version', () {
      final old = _event(id: 'same');
      final newer = _event(
        id: 'same',
        updatedAt: DateTime.utc(2026, 8, 15),
      );

      final result = EventService.deduplicateEvents([old, newer]);
      expect(result, hasLength(1));
      expect(result.single.updatedAt, DateTime.utc(2026, 8, 15));
    });
  });

  group('server-authoritative event reliability contract', () {
    final migration = File(
      'supabase/migrations/20260814143000_event_reliability_reminders.sql',
    ).readAsStringSync();
    final service = File('lib/services/event_service.dart').readAsStringSync();
    final screen =
        File('lib/screens/events/events_screen.dart').readAsStringSync();
    final calendar =
        File('lib/services/event_calendar_service.dart').readAsStringSync();
    final reminderFunction =
        File('supabase/functions/send-event-reminders/index.ts')
            .readAsStringSync();
    final sharedPush =
        File('supabase/functions/_shared/grace.ts').readAsStringSync();

    test('event creation is idempotent under retries and concurrent taps', () {
      expect(migration, contains('save_event_idempotent'));
      expect(migration, contains('events_creation_request_unique_idx'));
      expect(migration, contains('events_canonical_occurrence_unique_idx'));
      final canonicalIndex = RegExp(
        r'create unique index if not exists events_canonical_occurrence_unique_idx([\s\S]*?)\);',
      ).firstMatch(migration)!.group(1)!;
      expect(canonicalIndex, isNot(contains('organizerId')));
      expect(migration, isNot(contains('and event."organizerId" =')));
      expect(migration, contains('pg_advisory_xact_lock'));
      expect(migration, contains('exception when unique_violation'));
      expect(migration, contains("'reused_existing', true"));
      expect(
        migration,
        contains(
          'revoke insert, update on table public.events from public, anon, authenticated',
        ),
      );
      expect(service, contains("'save_event_idempotent'"));
      expect(service, isNot(contains('.insert(newEvent')));
      expect(screen, contains('_eventCreationRequestId ??='));
      expect(screen, contains('requestId: _eventCreationRequestId'));
      expect(screen, contains('Event was already posted'));
      expect(service, isNot(contains('event.organizerId.trim(),')));
    });

    test('RSVP reminders are retryable, idempotent, and user scoped', () {
      expect(
          migration, contains('create table if not exists public.event_rsvps'));
      expect(migration, contains('primary key (event_id, user_id)'));
      expect(migration, contains('reminder_minutes in (30, 120, 1440)'));
      expect(migration, contains('claim_due_event_reminders'));
      expect(migration, contains("status = 'processing'"));
      expect(migration, contains("interval '15 minutes'"));
      expect(migration, contains('notifications_one_event_rsvp_reminder_idx'));
      expect(migration, contains('reminder_version uuid'));
      expect(migration, contains('claim_token uuid'));
      expect(migration, contains('reset_event_reminders_after_reschedule'));
      expect(migration, contains('and claim_token = p_claim_token'));
      expect(migration, contains("'*/10 * * * *'"));
      expect(reminderFunction, contains(r'topic: `user_${userId}`'));
      expect(reminderFunction, contains('Promise.allSettled'));
      expect(reminderFunction, contains('p_claim_token: claimToken'));
      expect(reminderFunction, contains('completionError'));
      expect(reminderFunction, contains('idempotencyKey:'));
      expect(reminderFunction, contains('complete_event_reminder_delivery'));
      expect(reminderFunction, contains('requireCronSecret'));
      expect(sharedPush, contains('params.idempotencyKey ?? params.entityId'));
    });

    test('calendar sync is explicit and updates one native entry', () {
      expect(screen, contains('Sync to my device calendar'));
      expect(screen, contains('Calendar access is never used'));
      expect(calendar, contains('CalendarAccessLevel.full'));
      expect(calendar, contains('updateEvent('));
      expect(calendar, contains('createEvent('));
      expect(calendar, contains('reminders: Patch.set(reminders)'));
      expect(calendar, contains('savedReminderMinutes'));
      expect(calendar, contains('syncOutdated'));
    });

    test('event link is validated by both client and database', () {
      expect(service, contains('EventLink.normalize'));
      expect(migration, contains('events_event_url_check'));
      expect(migration, contains('Event links must be public HTTPS links'));
      expect(screen, contains('Event link (optional)'));
      expect(screen, contains('Open event link'));
    });
  });
}
