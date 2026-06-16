import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/family_relationship.dart';
import '../models/user_profile.dart';

class FamilyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Stream<List<FamilyRelationship>> watchFamilyLinks({
    required String currentUserId,
    required String churchId,
  }) {
    return _supabase
        .from('family_relationships')
        .stream(primaryKey: ['id'])
        .eq('requester_place_id', churchId)
        .order('requested_at', ascending: false)
        .map((rows) => rows
            .map((row) => FamilyRelationship.fromMap(row))
            .where((relationship) =>
                relationship.requesterId == currentUserId ||
                relationship.relatedUserId == currentUserId)
            .toList());
  }

  Future<List<FamilyMemberSummary>> searchMembers({
    required String query,
    required String churchId,
    required String excludeUid,
  }) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return [];

    final rows = await _supabase
        .from('users')
        .select('uid, id, fullName, photoUrl, placeId')
        .eq('placeId', churchId)
        .neq('uid', excludeUid)
        .ilike('fullName', '%$trimmed%')
        .order('fullName')
        .limit(10);

    return rows
        .map<FamilyMemberSummary>((row) => FamilyMemberSummary.fromMap(row))
        .where((member) => member.uid.isNotEmpty)
        .toList();
  }

  Future<List<FamilyRelationship>> visibleFamilyLinksForProfile({
    required String profileUserId,
  }) async {
    if (profileUserId.isEmpty) return [];

    dynamic rows;
    try {
      rows = await _supabase.rpc(
        'get_visible_family_relationships',
        params: {'profile_user_id': profileUserId},
      );
    } catch (error) {
      debugPrint('Family visibility RPC unavailable, using fallback: $error');
      rows = await _supabase
          .from('family_relationships')
          .select()
          .eq('status', 'accepted')
          .or('requester_id.eq.$profileUserId,related_user_id.eq.$profileUserId')
          .order('requested_at', ascending: false)
          .limit(20);
    }

    return (rows as List<dynamic>)
        .map((row) => FamilyRelationship.fromMap(row as Map<String, dynamic>))
        .where((relationship) => relationship.isAccepted)
        .toList();
  }

  Future<void> requestFamilyLink({
    required UserProfile requester,
    required FamilyMemberSummary relatedMember,
    required String relationshipType,
    String note = '',
  }) async {
    await _supabase.rpc('request_family_relationship', params: {
      'target_user_id': relatedMember.uid,
      'requested_relationship_type': relationshipType,
      'request_note': note.trim(),
    });
  }

  Future<void> respondToRequest({
    required String relationshipId,
    required bool approve,
  }) async {
    await _supabase.rpc(
      'respond_to_family_relationship',
      params: {
        'relationship_id': relationshipId,
        'approve': approve,
      },
    );
  }

  Future<void> cancelRequest(String relationshipId) async {
    try {
      await _supabase
          .from('family_relationships')
          .update({'status': 'cancelled'}).eq('id', relationshipId);
    } catch (e) {
      debugPrint('Failed to cancel family request: $e');
      rethrow;
    }
  }
}
