import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/event_model.dart';
import '../utils/event_link.dart';
import 'supabase_resilience.dart';

class EventMutationResult {
  const EventMutationResult({
    required this.event,
    required this.created,
    required this.reusedExisting,
  });

  final EventModel event;
  final bool created;
  final bool reusedExisting;
}

class EventService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _collection = 'events';

  // Get stream of events for a specific church, optionally including events
  // intentionally shared by other churches.
  Stream<List<EventModel>> getEvents(
    String churchId, {
    bool includeSharedEvents = false,
  }) async* {
    unawaited(cleanupPastEvents());
    await for (final events
        in SupabaseResilience.guardedStream<List<EventModel>>(
      debugLabel: 'Events',
      emptyValue: const <EventModel>[],
      yieldEmptyOnInitialFailure: true,
      fetchInitial: () => fetchEvents(
        churchId,
        includeSharedEvents: includeSharedEvents,
      ),
      subscribe: () => _supabase
          .from(_collection)
          .stream(primaryKey: ['id'])
          .order('date', ascending: true)
          .limit(200)
          .map((docs) => _normalizeEvents(
                docs,
                churchId,
                includeSharedEvents: includeSharedEvents,
              )),
    )) {
      yield events;
    }
  }

  Future<List<EventModel>> fetchEvents(
    String churchId, {
    bool includeSharedEvents = false,
  }) async {
    final data = await _supabase
        .from(_collection)
        .select()
        .order('date', ascending: true)
        .limit(200);

    return _normalizeEvents(
      data,
      churchId,
      includeSharedEvents: includeSharedEvents,
    );
  }

  Stream<List<EventModel>> getPublicEvents() async* {
    unawaited(cleanupPastEvents());
    await for (final events
        in SupabaseResilience.guardedStream<List<EventModel>>(
      debugLabel: 'Public events',
      emptyValue: const <EventModel>[],
      yieldEmptyOnInitialFailure: true,
      fetchInitial: fetchPublicEvents,
      subscribe: () => _supabase
          .from(_collection)
          .stream(primaryKey: ['id'])
          .order('date', ascending: true)
          .limit(200)
          .map((docs) => _normalizePublicEvents(docs)),
    )) {
      yield events;
    }
  }

  Future<List<EventModel>> fetchPublicEvents() async {
    final data = await _supabase
        .from(_collection)
        .select()
        .eq('visible_to_all_churches', true)
        .order('date', ascending: true)
        .limit(200);

    return _normalizePublicEvents(data);
  }

  Future<EventMutationResult> updateEvent(EventModel event) async {
    return _writeEvent(event, eventId: event.id);
  }

  Future<void> deleteEvent(String eventId) async {
    await _supabase.from(_collection).delete().eq('id', eventId);
  }

  // Get upcoming events (limited)
  Stream<List<EventModel>> getUpcomingEvents(String churchId, {int limit = 3}) {
    unawaited(cleanupPastEvents());
    return SupabaseResilience.guardedStream<List<EventModel>>(
      debugLabel: 'Upcoming events',
      emptyValue: const <EventModel>[],
      yieldEmptyOnInitialFailure: true,
      fetchInitial: () async {
        final events = await fetchEvents(churchId);
        return events
            .where((event) => !_isPastEvent(event))
            .take(limit)
            .toList();
      },
      subscribe: () => _supabase
          .from(_collection)
          .stream(primaryKey: ['id'])
          .eq('churchId', churchId)
          .order('date', ascending: true)
          .map((docs) => deduplicateEvents(
                docs
                    .map((doc) => EventModel.fromMap(doc))
                    .where((event) => !_isPastEvent(event)),
              )..sort((a, b) => a.date.compareTo(b.date)))
          .map((events) => events.take(limit).toList()),
    );
  }

  Future<void> cleanupPastEvents() async {
    try {
      await _supabase.rpc('cleanup_past_events');
    } catch (_) {
      // Older databases may not have the cleanup function yet. Keep the UI
      // clean locally until the migration is applied.
    }
  }

  // Add a new event through the server-authoritative idempotent mutation RPC.
  // Reusing [requestId] after a timeout returns the original event instead of
  // inserting a second row.
  Future<EventMutationResult> addEvent(
    EventModel event, {
    String? requestId,
  }) async {
    return _writeEvent(
      event,
      requestId: requestId ?? const Uuid().v4(),
    );
  }

  Future<EventMutationResult> _writeEvent(
    EventModel event, {
    String? eventId,
    String? requestId,
  }) async {
    final normalizedUrl = EventLink.normalize(event.eventUrl);
    if (event.eventUrl?.trim().isNotEmpty == true && normalizedUrl == null) {
      throw const FormatException('Event links must be public HTTPS links.');
    }

    final response = await _supabase.rpc(
      'save_event_idempotent',
      params: {
        'p_request_id': requestId,
        'p_event_id': eventId,
        'p_church_id': event.churchId,
        'p_title': event.title,
        'p_description': event.description,
        'p_start_at': event.date.toUtc().toIso8601String(),
        'p_time_label': event.time,
        'p_location': event.location,
        'p_event_url': normalizedUrl,
        'p_duration_minutes': event.durationMinutes,
        'p_source_label': event.sourceLabel,
        'p_ministry_id': event.ministryId,
        'p_ministry_name': event.ministryName,
        'p_visible_to_all_churches': event.visibleToAllChurches,
      },
    );
    final payload = Map<String, dynamic>.from(response as Map);
    return EventMutationResult(
      event: EventModel.fromMap(
        Map<String, dynamic>.from(payload['event'] as Map),
      ),
      created: payload['created'] == true,
      reusedExisting: payload['reused_existing'] == true,
    );
  }

  // RSVP to an event
  Future<void> rsvpToEvent(
    String eventId,
    bool isJoining, {
    int reminderMinutes = 1440,
  }) async {
    await _supabase.rpc(
      'rsvp_event_with_reminder',
      params: {
        'target_event_id': eventId,
        'is_joining': isJoining,
        'reminder_minutes': reminderMinutes,
      },
    );
  }

  Future<List<EventRsvpDetail>> fetchRsvpDetails(String eventId) async {
    final rows = await _supabase.rpc(
      'get_event_rsvp_details',
      params: {'target_event_id': eventId},
    );
    if (rows is! List) return const [];

    return rows
        .map((row) => EventRsvpDetail.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  List<EventModel> _normalizeEvents(
    List<dynamic> data,
    String churchId, {
    required bool includeSharedEvents,
  }) {
    final events = data
        .map((doc) => EventModel.fromMap(Map<String, dynamic>.from(doc)))
        .where((event) {
      final isOwnChurch = event.churchId == churchId;
      final canShow = includeSharedEvents
          ? !isOwnChurch && event.visibleToAllChurches
          : isOwnChurch;
      return canShow && !_isPastEvent(event);
    }).toList();
    final deduplicated = deduplicateEvents(events)
      ..sort((a, b) => a.date.compareTo(b.date));
    return deduplicated;
  }

  List<EventModel> _normalizePublicEvents(List<dynamic> data) {
    final events = data
        .map((doc) => EventModel.fromMap(Map<String, dynamic>.from(doc)))
        .where((event) => event.visibleToAllChurches && !_isPastEvent(event))
        .toList();
    final deduplicated = deduplicateEvents(events)
      ..sort((a, b) => a.date.compareTo(b.date));
    return deduplicated;
  }

  static List<EventModel> deduplicateEvents(Iterable<EventModel> source) {
    final byId = <String, EventModel>{};
    for (final event in source) {
      final existing = byId[event.id];
      if (existing == null || event.updatedAt.isAfter(existing.updatedAt)) {
        byId[event.id] = event;
      }
    }

    final byFingerprint = <String, EventModel>{};
    for (final event in byId.values) {
      final title = event.title.trim().toLowerCase().replaceAll(
            RegExp(r'\s+'),
            ' ',
          );
      final key = [
        event.churchId.trim(),
        event.ministryId?.trim() ?? '',
        title,
        event.date.toUtc().toIso8601String(),
      ].join('|');
      final existing = byFingerprint[key];
      if (existing == null || event.createdAt.isBefore(existing.createdAt)) {
        byFingerprint[key] = event;
      }
    }
    return byFingerprint.values.toList();
  }

  bool _isPastEvent(EventModel event) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final localEventDate = event.date.toLocal();
    final eventDay = DateTime(
      localEventDate.year,
      localEventDate.month,
      localEventDate.day,
    );
    return eventDay.isBefore(today);
  }
}
