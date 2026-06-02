import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/prayer_request.dart';

class PrayerService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _collection = 'prayer_requests';

  // Submit Request
  Future<void> submitRequest(PrayerRequest request) async {
    final String docId = const Uuid().v4();
    final newRequest = PrayerRequest(
      id: docId,
      userId: request.userId,
      churchId: request.churchId,
      userName: request.userName,
      title: request.title,
      content: request.content,
      isAnonymous: request.isAnonymous,
      isPrivate: request.isPrivate,
      status: 'active',
      createdAt: DateTime.now(),
      prayedBy: [],
    );
    await _supabase.from(_collection).insert(newRequest.toMap());
  }

  // Get My Requests
  Stream<List<PrayerRequest>> getMyRequests(String userId) {
    return _supabase
        .from(_collection)
        .stream(primaryKey: ['id'])
        .eq('userId', userId)
        .order('createdAt', ascending: false)
        .map((docs) => docs.map((doc) => PrayerRequest.fromMap(doc)).toList());
  }

  Stream<List<PrayerRequest>> getChurchRequests(String churchId) {
    return _supabase
        .from(_collection)
        .stream(primaryKey: ['id'])
        .eq('churchId', churchId)
        .order('createdAt', ascending: false)
        .map((docs) => docs.map((doc) => PrayerRequest.fromMap(doc)).toList());
  }

  Future<void> updateStatus(String requestId, String status) async {
    await _supabase
        .from(_collection)
        .update({'status': status}).eq('id', requestId);
  }

  // Mark as Prayed (Team/Community)
  Future<void> prayForRequest(String requestId, String userId) async {
    final data = await _supabase
        .from(_collection)
        .select('prayedBy')
        .eq('id', requestId)
        .maybeSingle();
    if (data != null) {
      List<dynamic> prayedBy = data['prayedBy'] ?? [];
      if (!prayedBy.contains(userId)) {
        prayedBy.add(userId);
        await _supabase
            .from(_collection)
            .update({'prayedBy': prayedBy}).eq('id', requestId);
      }
    }
  }
}
