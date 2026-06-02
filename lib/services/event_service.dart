import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/event_model.dart';

class EventService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _collection = 'events';

  // Get stream of events for a specific church
  Stream<List<EventModel>> getEvents(String churchId) {
    return _supabase
        .from(_collection)
        .stream(primaryKey: ['id'])
        .eq('churchId', churchId)
        .order('date', ascending: true)
        .map((docs) => docs.map((doc) => EventModel.fromMap(doc)).toList());
  }

  // Get upcoming events (limited)
  Stream<List<EventModel>> getUpcomingEvents(String churchId, {int limit = 3}) {
    final now = DateTime.now().toIso8601String();
    return _supabase
        .from(_collection)
        .stream(primaryKey: ['id'])
        .eq('churchId', churchId)
        .order('date', ascending: true)
        .map((docs) => docs
            .where((doc) => (doc['date'] as String).compareTo(now) >= 0)
            .map((doc) => EventModel.fromMap(doc))
            .toList())
        .map((events) => events.take(limit).toList());
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
}
