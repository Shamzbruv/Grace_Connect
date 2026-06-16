import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bible_nudge.dart';
import '../models/user_profile.dart';

class BibleNudgeService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<BibleNudge> sendNudge({
    required UserProfile sender,
    required UserProfile recipient,
    String message = '',
  }) async {
    if (sender.uid == recipient.uid) {
      throw Exception('You cannot Bible Nudge yourself.');
    }

    final row = await _supabase
        .from('bible_nudges')
        .insert({
          'sender_id': sender.uid,
          'sender_name':
              sender.fullName.isEmpty ? sender.email : sender.fullName,
          'recipient_id': recipient.uid,
          'recipient_name':
              recipient.fullName.isEmpty ? recipient.email : recipient.fullName,
          'church_id': sender.churchId,
          'message': message.trim(),
          'status': 'pending',
        })
        .select()
        .single();

    final nudge = BibleNudge.fromMap(row);
    await _notify(
      targetUserId: recipient.uid,
      actorUserId: sender.uid,
      type: 'bible_nudge_request',
      title: 'Bible Nudge',
      body:
          '${sender.fullName.isEmpty ? 'Someone' : sender.fullName} wants to study the Bible with you.',
      placeId: sender.churchId,
      entityId: nudge.id,
    );
    return nudge;
  }

  Future<void> respondToNudge({
    required BibleNudge nudge,
    required bool accepted,
  }) async {
    final status = accepted ? 'accepted' : 'declined';
    if (accepted) {
      try {
        await _supabase.rpc(
          'accept_bible_nudge_and_grant_messages',
          params: {'target_nudge_id': nudge.id},
        );
      } on PostgrestException catch (error) {
        if (!_isMissingGrantFunction(error)) rethrow;
        await _updateNudgeStatus(nudge.id, status);
      }
    } else {
      await _updateNudgeStatus(nudge.id, status);
    }

    await _notify(
      targetUserId: nudge.senderId,
      actorUserId: nudge.recipientId,
      type: 'bible_nudge_response',
      title: accepted ? 'Bible Nudge accepted' : 'Bible Nudge declined',
      body: accepted
          ? '${nudge.recipientName} accepted. Send a message to plan Bible study.'
          : '${nudge.recipientName} declined the Bible Nudge.',
      placeId: nudge.churchId,
      entityId: nudge.id,
      route: accepted ? '/inbox' : '/notifications',
    );
  }

  Future<void> _updateNudgeStatus(String nudgeId, String status) async {
    await _supabase.from('bible_nudges').update({
      'status': status,
      'responded_at': DateTime.now().toIso8601String(),
    }).eq('id', nudgeId);
  }

  bool _isMissingGrantFunction(PostgrestException error) {
    final message = error.message.toLowerCase();
    return error.code == 'PGRST202' ||
        message.contains('accept_bible_nudge_and_grant_messages') &&
            message.contains('not found');
  }

  Future<BibleNudge?> getNudge(String nudgeId) async {
    if (nudgeId.isEmpty) return null;
    try {
      final row = await _supabase
          .from('bible_nudges')
          .select()
          .eq('id', nudgeId)
          .maybeSingle();
      if (row == null) return null;
      return BibleNudge.fromMap(row);
    } catch (error) {
      debugPrint('Could not fetch Bible Nudge: $error');
      return null;
    }
  }

  Future<void> _notify({
    required String targetUserId,
    required String actorUserId,
    required String type,
    required String title,
    required String body,
    required String placeId,
    required String entityId,
    String route = '/notifications',
  }) async {
    try {
      await _supabase.rpc(
        'create_notification',
        params: {
          'target_user_id': targetUserId,
          'actor_user_id': actorUserId,
          'notification_type': type,
          'notification_title': title,
          'notification_body': body,
          'notification_place_id': placeId,
          'notification_entity_table': 'bible_nudges',
          'notification_entity_id': entityId,
          'notification_route': route,
        },
      );
    } catch (error) {
      debugPrint('Bible Nudge notification skipped: $error');
    }
  }
}
