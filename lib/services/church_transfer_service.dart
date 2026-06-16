import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/church_model.dart';
import '../models/church_transfer_request.dart';
import '../models/user_profile.dart';
import 'church_service.dart';

class ChurchTransferService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ChurchService _churchService = ChurchService();

  bool canManageTransfers(UserProfile? user) {
    if (user == null) return false;
    final roles = user.roles.map(_normalizeRole).toSet();
    return roles.contains('pastor') ||
        roles.contains('senior_pastor') ||
        roles.contains('assistant_pastor') ||
        roles.contains('acting_pastor');
  }

  Stream<List<ChurchTransferRequest>> watchMyRequests(String userId) {
    return _supabase
        .from('church_transfer_requests')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map(
          (rows) =>
              rows.map((row) => ChurchTransferRequest.fromMap(row)).toList(),
        );
  }

  Stream<List<ChurchTransferRequest>> watchPastorQueue(String churchId) {
    return _supabase
        .from('church_transfer_requests')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map(
          (rows) => rows
              .map((row) => ChurchTransferRequest.fromMap(row))
              .where((request) =>
                  request.currentChurchId == churchId ||
                  request.targetChurchId == churchId)
              .toList(),
        );
  }

  Future<ChurchTransferRequest> createRequest({
    required UserProfile user,
    required Church targetChurch,
    required String reason,
    required String contactPhone,
  }) async {
    final currentChurch = await _churchService.getChurch(user.churchId);
    final targetChurchId = targetChurch.placeId.isNotEmpty
        ? targetChurch.placeId
        : targetChurch.id;

    final row = await _supabase
        .from('church_transfer_requests')
        .insert({
          'user_id': user.uid,
          'user_name': user.fullName.isEmpty ? user.email : user.fullName,
          'user_email': user.email,
          'current_church_id': user.churchId,
          'current_church_name': currentChurch?.name ?? user.placeName,
          'target_church_id': targetChurchId,
          'target_church_name': targetChurch.name,
          'reason': reason.trim(),
          'contact_phone': contactPhone.trim(),
          'status': 'submitted',
        })
        .select()
        .single();

    return ChurchTransferRequest.fromMap(row);
  }

  Future<void> updateRequest({
    required ChurchTransferRequest request,
    required String status,
    required String notes,
    bool targetPastorNote = false,
  }) async {
    final data = <String, dynamic>{
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (targetPastorNote) {
      data['target_pastor_notes'] = notes.trim();
    } else {
      data['pastor_notes'] = notes.trim();
    }

    await _supabase
        .from('church_transfer_requests')
        .update(data)
        .eq('id', request.id);
  }

  Future<void> cancelRequest(String requestId) async {
    try {
      await _supabase.from('church_transfer_requests').update({
        'status': 'cancelled',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);
    } catch (error) {
      debugPrint('Could not cancel transfer request: $error');
      rethrow;
    }
  }

  String _normalizeRole(String role) {
    return role
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
