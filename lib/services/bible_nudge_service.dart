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

    final senderChurch = sender.churchId.trim();
    final recipientChurch = recipient.churchId.trim();
    if (senderChurch.isEmpty ||
        recipientChurch.isEmpty ||
        senderChurch == recipientChurch) {
      throw Exception(
        'Bible Nudge is only for members of two different churches. It does not unlock private messages.',
      );
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
    await _sendPush(nudge.id, event: 'request');
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

    await _sendPush(nudge.id, event: accepted ? 'accepted' : 'declined');
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

  Future<void> _sendPush(String nudgeId, {required String event}) async {
    if (nudgeId.trim().isEmpty) return;
    try {
      final response = await _supabase.functions.invoke(
        'send-bible-nudge-push',
        body: {'nudgeId': nudgeId.trim(), 'event': event},
      ).timeout(const Duration(seconds: 12));
      if (response.data case final Map data when data['ok'] == false) {
        debugPrint('Bible Nudge push queued with warning: $data');
      }
    } catch (error) {
      debugPrint('Bible Nudge push skipped: $error');
    }
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
}
