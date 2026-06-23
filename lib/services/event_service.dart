import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/event_model.dart';
import 'supabase_resilience.dart';

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

  Future<void> updateEvent(EventModel event) async {
    await _supabase.from(_collection).update({
      'title': event.title,
      'description': event.description,
      'date': event.date.toIso8601String(),
      'time': event.time,
      'location': event.location,
      'sourceLabel': event.sourceLabel,
      'ministry_id': event.ministryId,
      'ministry_name': event.ministryName,
      'visible_to_all_churches': event.visibleToAllChurches,
    }).eq('id', event.id);
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
          .map((docs) => docs
              .map((doc) => EventModel.fromMap(doc))
              .where((event) => !_isPastEvent(event))
              .toList())
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

  // Add a new event
  Future<void> addEvent(EventModel event) async {
    final String docId = event.id.isEmpty ? const Uuid().v4() : event.id;

    final newEvent = EventModel(
      id: docId,
      title: event.title,
      description: event.description,
      date: event.date,
      time: event.time,
      location: event.location,
      churchId: event.churchId,
      organizerId: event.organizerId,
      sourceLabel: event.sourceLabel,
      ministryId: event.ministryId,
      ministryName: event.ministryName,
      visibleToAllChurches: event.visibleToAllChurches,
      createdAt: event.createdAt,
      attendees: event.attendees,
    );

    if (event.id.isEmpty) {
      await _supabase.from(_collection).insert(newEvent.toMap());
    } else {
      await _supabase
          .from(_collection)
          .update(newEvent.toMap())
          .eq('id', docId);
    }
  }

  // RSVP to an event
  Future<void> rsvpToEvent(
      String eventId, String userId, bool isJoining) async {
    await _supabase.rpc(
      'rsvp_event',
      params: {
        'target_event_id': eventId,
        'is_joining': isJoining,
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
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return events;
  }

  bool _isPastEvent(EventModel event) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay =
        DateTime(event.date.year, event.date.month, event.date.day);
    return eventDay.isBefore(today);
  }
}
