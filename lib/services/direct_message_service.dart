import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/direct_conversation.dart';
import '../models/direct_message.dart';
import '../models/user_profile.dart';
import 'user_service.dart';

class DirectMessageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _chatMediaBucket = 'chat_media';

  String get _currentUid => _supabase.auth.currentUser?.id ?? '';

  Stream<List<DirectConversation>> watchConversations() {
    return _supabase
        .from('direct_conversations')
        .stream(primaryKey: ['id'])
        .order('last_message_at', ascending: false)
        .map((rows) {
          final conversationsById = <String, DirectConversation>{};
          for (final row in rows) {
            final conversation = DirectConversation.fromMap(row);
            if (conversation.id.isNotEmpty) {
              conversationsById[conversation.id] = conversation;
            }
          }
          final conversations = conversationsById.values
              .where((conversation) => !conversation.isHiddenFor(_currentUid))
              .toList();
          conversations.sort((a, b) {
            final aDate = a.lastMessageAt ?? a.createdAt;
            final bDate = b.lastMessageAt ?? b.createdAt;
            return bDate.compareTo(aDate);
          });
          return conversations;
        });
  }

  Stream<int> watchUnreadCount() {
    final uid = _currentUid;
    if (uid.isEmpty) return const Stream<int>.empty();

    return _supabase
        .from('direct_messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map((rows) => rows
            .map((row) => DirectMessage.fromMap(row))
            .where((message) =>
                !message.isRead &&
                !message.isExpired &&
                !message.isDeletedFor(uid) &&
                message.senderId != uid)
            .length);
  }

  Stream<int> watchUnreadCountForConversation(String conversationId) {
    final uid = _currentUid;
    if (uid.isEmpty) return const Stream<int>.empty();

    return watchMessages(conversationId).map((messages) => messages
        .where((message) => !message.isRead && message.senderId != uid)
        .length);
  }

  Future<void> cleanupVanishingContent() async {
    try {
      await _supabase.rpc('cleanup_vanishing_content');
    } catch (error) {
      debugPrint('Chat cleanup skipped: $error');
    }
  }

  Stream<List<DirectMessage>> watchMessages(String conversationId) {
    return _supabase
        .from('direct_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map((rows) {
          final messagesById = <String, DirectMessage>{};
          for (final row in rows) {
            final message = DirectMessage.fromMap(row);
            if (message.id.isNotEmpty &&
                !message.isExpired &&
                !message.isDeletedFor(_currentUid)) {
              messagesById[message.id] = message;
            }
          }
          final messages = messagesById.values.toList();
          messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return messages;
        });
  }

  Future<DirectConversation> getOrCreateConversation({
    required UserProfile currentUser,
    required UserProfile otherUser,
  }) async {
    if (currentUser.uid == otherUser.uid) {
      throw Exception('You cannot message yourself.');
    }
    if (currentUser.churchId.isEmpty ||
        currentUser.churchId != otherUser.churchId) {
      throw Exception('Messages can only be started inside your church.');
    }
    if (!otherUser.allowMessages) {
      throw Exception('This member is not accepting messages right now.');
    }

    final key = _participantKey(currentUser.uid, otherUser.uid);
    final existing = await _supabase
        .from('direct_conversations')
        .select()
        .eq('participant_key', key)
        .maybeSingle();

    if (existing != null) {
      return DirectConversation.fromMap(existing);
    }

    try {
      final inserted = await _supabase
          .from('direct_conversations')
          .insert({
            'church_id': currentUser.churchId,
            'member_ids': [currentUser.uid, otherUser.uid],
            'participant_key': key,
            'created_by': currentUser.uid,
            'last_message_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select()
          .single();

      return DirectConversation.fromMap(inserted);
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;

      final conversation = await _supabase
          .from('direct_conversations')
          .select()
          .eq('participant_key', key)
          .single();
      return DirectConversation.fromMap(conversation);
    }
  }

  Future<DirectConversation> getOrCreateConversationWithUserId({
    required UserProfile currentUser,
    required String otherUserId,
  }) async {
    final otherUser = await UserService().getUserProfile(otherUserId);
    if (otherUser == null) {
      throw Exception('Member profile was not found.');
    }
    return getOrCreateConversation(
      currentUser: currentUser,
      otherUser: otherUser,
    );
  }

  Future<void> sendMessage({
    required String conversationId,
    required String text,
    String? mediaUrl,
    String? mediaPath,
    String mediaType = 'text',
    int? durationSeconds,
  }) async {
    final uid = _currentUid;
    final cleanText = text.trim();
    final cleanMediaUrl = mediaUrl?.trim();
    if (uid.isEmpty ||
        (cleanText.isEmpty &&
            (cleanMediaUrl == null || cleanMediaUrl.isEmpty))) {
      return;
    }

    final now = DateTime.now().toUtc();
    final expiresAt = now.add(const Duration(days: 30));
    final payload = {
      'id': const Uuid().v4(),
      'conversation_id': conversationId,
      'sender_id': uid,
      'text': cleanText,
      'media_url': cleanMediaUrl,
      'media_path': mediaPath,
      'media_type': mediaType,
      'duration_seconds': durationSeconds,
      'created_at': now.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
    };

    try {
      await _supabase.from('direct_messages').insert(payload);
    } on PostgrestException catch (error) {
      if (!_isMissingColumnError(error) || cleanText.isEmpty) rethrow;
      await _supabase.from('direct_messages').insert({
        'id': payload['id'],
        'conversation_id': conversationId,
        'sender_id': uid,
        'text': cleanText,
        'created_at': now.toIso8601String(),
      });
    }

    final preview = _previewForMessage(cleanText, mediaType);
    try {
      await _supabase.from('direct_conversations').update({
        'last_message': preview,
        'last_sender_id': uid,
        'last_message_at': now.toIso8601String(),
        'hidden_for': const <String>[],
      }).eq('id', conversationId);
    } on PostgrestException catch (error) {
      if (!_isMissingColumnError(error)) rethrow;
      await _supabase.from('direct_conversations').update({
        'last_message': preview,
        'last_sender_id': uid,
        'last_message_at': now.toIso8601String(),
      }).eq('id', conversationId);
    }
  }

  Future<String> uploadChatMediaBytes(
    Uint8List bytes,
    String path, {
    String? contentType,
  }) async {
    await _supabase.storage.from(_chatMediaBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            contentType: contentType,
            upsert: false,
          ),
        );
    return _supabase.storage.from(_chatMediaBucket).getPublicUrl(path);
  }

  Future<void> markConversationDelivered(String conversationId) async {
    final uid = _currentUid;
    if (uid.isEmpty) return;

    try {
      await _supabase
          .from('direct_messages')
          .update({'delivered_at': DateTime.now().toUtc().toIso8601String()})
          .eq('conversation_id', conversationId)
          .neq('sender_id', uid)
          .filter('delivered_at', 'is', null);
    } on PostgrestException catch (error) {
      if (!_isMissingColumnError(error)) {
        debugPrint('Could not mark direct messages delivered: $error');
      }
    } catch (error) {
      debugPrint('Could not mark direct messages delivered: $error');
    }
  }

  Future<void> markConversationRead(String conversationId) async {
    final uid = _currentUid;
    if (uid.isEmpty) return;

    try {
      final unreadRows = await _supabase
          .from('direct_messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', uid)
          .eq('is_read', false);
      final unreadMessageIds = unreadRows
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .toList();

      final now = DateTime.now().toUtc().toIso8601String();
      try {
        await _supabase
            .from('direct_messages')
            .update({
              'is_read': true,
              'delivered_at': now,
              'read_at': now,
            })
            .eq('conversation_id', conversationId)
            .neq('sender_id', uid)
            .eq('is_read', false);
      } on PostgrestException catch (error) {
        if (!_isMissingColumnError(error)) rethrow;
        await _supabase
            .from('direct_messages')
            .update({'is_read': true})
            .eq('conversation_id', conversationId)
            .neq('sender_id', uid)
            .eq('is_read', false);
      }

      if (unreadMessageIds.isNotEmpty) {
        await _supabase
            .from('notifications')
            .update({'is_read': true})
            .eq('user_id', uid)
            .eq('type', 'direct_message')
            .inFilter('entity_id', unreadMessageIds);
      }
    } catch (error) {
      debugPrint('Could not mark direct messages read: $error');
    }
  }

  Future<void> deleteMessageForMe(DirectMessage message) async {
    final uid = _currentUid;
    if (uid.isEmpty) return;

    final nextDeletedFor = {...message.deletedFor, uid}.toList();
    await _supabase
        .from('direct_messages')
        .update({'deleted_for': nextDeletedFor}).eq('id', message.id);
  }

  Future<void> deleteMessageForEveryone(DirectMessage message) async {
    final uid = _currentUid;
    if (uid.isEmpty || message.senderId != uid) return;

    await _supabase.from('direct_messages').delete().eq('id', message.id);
  }

  Future<void> deleteConversationForMe(DirectConversation conversation) async {
    final uid = _currentUid;
    if (uid.isEmpty) return;

    final nextHiddenFor = {...conversation.hiddenFor, uid}.toList();
    try {
      await _supabase
          .from('direct_conversations')
          .update({'hidden_for': nextHiddenFor}).eq('id', conversation.id);
    } on PostgrestException catch (error) {
      if (!_isMissingColumnError(error)) rethrow;
    }
  }

  Future<bool> hasBlockBetween(String firstUserId, String secondUserId) async {
    if (firstUserId.isEmpty || secondUserId.isEmpty) return false;

    final rows = await _supabase
        .from('user_blocks')
        .select('id')
        .or('and(blocker_id.eq.$firstUserId,blocked_user_id.eq.$secondUserId),and(blocker_id.eq.$secondUserId,blocked_user_id.eq.$firstUserId)')
        .limit(1);
    return rows.isNotEmpty;
  }

  String _participantKey(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}:${sorted[1]}';
  }

  String _previewForMessage(String text, String mediaType) {
    if (text.isNotEmpty) return text;
    return switch (mediaType) {
      'image' => 'Photo',
      'video' => 'Video',
      'voice' || 'audio' => 'Voice message',
      _ => 'Attachment',
    };
  }

  bool _isMissingColumnError(PostgrestException error) {
    final message = error.message.toLowerCase();
    return error.code == 'PGRST204' ||
        message.contains('column') && message.contains('schema cache');
  }
}
