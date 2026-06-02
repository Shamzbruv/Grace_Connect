import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/study_request.dart';

class StudyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> createRequest(StudyRequest request) async {
    final String docId = const Uuid().v4();
    final newReq = StudyRequest(
      id: docId,
      requesterId: request.requesterId,
      requesterName: request.requesterName,
      topic: request.topic,
      description: request.description,
      preferredTime: request.preferredTime,
      placeId: request.placeId,
      createdAt: request.createdAt,
    );
    await _supabase.from('study_requests').insert(newReq.toMap());
  }

  Stream<List<StudyRequest>> getOpenRequests(
      String placeId, String currentUserId) {
    return _supabase
        .from('study_requests')
        .stream(primaryKey: ['id'])
        .eq('placeId', placeId)
        .order('createdAt', ascending: false)
        .map((docs) {
      return docs
          .where((doc) => doc['status'] == 'open')
          .map((doc) => StudyRequest.fromMap(doc))
          .where(
              (req) => req.requesterId != currentUserId) // Exclude own requests
          .toList();
    });
  }

  Stream<List<StudyRequest>> getMySessions(String userId) {
    // Firestore doesn't support logical OR in matching simply, so we might need two queries or one combined if structure allows.
    // For simple MVP, we can fetch all requests involving user.
    // However, simplest is to filter client side or use two streams.
    // Let's use a simple approach: fetch where requesterId == userId OR partnerId == userId.
    // Actually, let's just fetch all 'study_requests' where requesterId == userId
    // AND separate query for partnerId == userId, then merge.

    // For now, let's just return requests I created for the "My Sessions" tab.
    // Enhancing to include matched...

    return _supabase
        .from('study_requests')
        .stream(primaryKey: ['id'])
        .eq('requesterId', userId)
        .order('createdAt', ascending: false)
        .map((docs) => docs
            .map((doc) => StudyRequest.fromMap(doc))
            .toList());
  }

  Future<void> acceptRequest(String requestId, String partnerId) async {
    await _supabase.from('study_requests').update({
      'status': 'matched',
      'partnerId': partnerId,
    }).eq('id', requestId);
  }
}
