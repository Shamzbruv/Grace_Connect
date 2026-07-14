import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/counseling_request_model.dart';
import 'package:flutter/foundation.dart';

class CounselingService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String _collection = 'counseling_requests';

  // Submit Request
  Future<void> submitRequest(CounselingRequest request) async {
    try {
      // Use the ID from the model if provided, or let Firestore generate one if empty/placeholder
      // Since model requires ID, we assume it might be empty string initially or generated before calling
      final String docId = const Uuid().v4();

      final newRequest = CounselingRequest(
        id: docId,
        userId: request.userId,
        churchId: request.churchId,
        category: request.category,
        urgency: request.urgency,
        preferredContactMethod: request.preferredContactMethod,
        description: request.description,
        status: 'pending',
        createdAt: DateTime.now(),
      );

      await _supabase.from(_collection).insert(newRequest.toMap());
    } catch (e) {
      debugPrint('Error submitting counseling request: $e');
      rethrow;
    }
  }

  // Get My Requests
  Stream<List<CounselingRequest>> getMyRequests(String userId) {
    return _supabase
        .from(_collection)
        .stream(primaryKey: ['id'])
        .eq('userId', userId)
        .order('createdAt', ascending: false)
        .map((docs) {
          return docs.map((doc) => CounselingRequest.fromMap(doc)).toList();
        });
  }

  // Admin: Get All Pending Requests for Church
  Stream<List<CounselingRequest>> getChurchRequests(String churchId) {
    return _supabase
        .from(_collection)
        .stream(primaryKey: ['id'])
        .eq('churchId', churchId)
        .order('createdAt', ascending: false)
        .map((docs) {
          return docs.map((doc) => CounselingRequest.fromMap(doc)).toList();
        });
  }

  // Counselor: Get only requests assigned to them.
  Stream<List<CounselingRequest>> getAssignedRequests(
    String churchId,
    String helperId,
  ) {
    return _supabase
        .from(_collection)
        .stream(primaryKey: ['id'])
        .eq('churchId', churchId)
        .order('createdAt', ascending: false)
        .map((docs) {
          return docs
              .where((doc) => doc['assignedToHelperId'] == helperId)
              .map((doc) => CounselingRequest.fromMap(doc))
              .toList();
        });
  }

  // Admin: Update Status
  Future<void> updateStatus(String requestId, String status) async {
    await _supabase.from(_collection).update({
      'status': status,
    }).eq('id', requestId);
  }

  Future<void> deleteRequest(String requestId) async {
    if (requestId.trim().isEmpty) return;
    await _supabase.from(_collection).delete().eq('id', requestId.trim());
  }

  Future<void> assignHelper(String requestId, String? helperId) async {
    await _supabase.rpc('assign_counseling_helper', params: {
      'request_id': requestId,
      'helper_uid': helperId,
    });
  }
}
