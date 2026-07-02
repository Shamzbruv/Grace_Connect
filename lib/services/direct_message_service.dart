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
  static const Duration _realtimeQuietTimeout = Duration(seconds: 18);

  String get _currentUid => _supabase.auth.currentUser?.id ?? '';

  Future<List<DirectConversation>> fetchConversations() async {
    final rows = await _supabase
        .from('direct_conversations')
        .select()
        .order('last_message_at', ascending: false)
        .limit(100);
    return _normalizeConversations(rows);
  }

  Stream<List<DirectConversation>> watchConversations() async* {
    var lastKnown = <DirectConversation>[];

    try {
      lastKnown = await fetchConversations();
      yield lastKnown;
    } catch (error) {
      debugPrint('Could not load inbox before realtime: $error');
    }

    try {
      await for (final conversations in _watchConversationsRealtime().timeout(
        _realtimeQuietTimeout,
        onTimeout: (sink) => sink.add(lastKnown),
      )) {
        lastKnown = conversations;
        yield conversations;
      }
    } catch (error) {
      debugPrint('Inbox realtime unavailable, keeping last known data: $error');
      yield lastKnown;
    }
  }

  Stream<List<DirectConversation>> _watchConversationsRealtime() {
    return _supabase
        .from('direct_conversations')
        .stream(primaryKey: ['id'])
        .order('last_message_at', ascending: false)
        .map(_normalizeConversations);
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

  Stream<DirectMessage?> watchLatestVisibleMessage(String conversationId) {
    return watchMessages(conversationId).map(
      (messages) => messages.isEmpty ? null : messages.last,
    );
  }

  Future<DirectConversation> getOrCreateConversation({
    required UserProfile currentUser,
    required UserProfile otherUser,
  }) async {
    if (currentUser.uid == otherUser.uid) {
      throw Exception('You cannot message yourself.');
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
      final rpcConversation =
          await _tryGetOrCreateConversationViaRpc(otherUser.uid);
      if (rpcConversation != null) {
        return rpcConversation;
      }
    } on PostgrestException catch (error) {
      throw Exception(_conversationErrorMessage(error));
    }

    final sameChurch = currentUser.churchId.trim().isNotEmpty &&
        currentUser.churchId == otherUser.churchId;
    if (!otherUser.allowMessages && !sameChurch) {
      throw Exception('This member is not accepting messages right now.');
    }

    try {
      final inserted = await _supabase
          .from('direct_conversations')
          .insert({
            'church_id': currentUser.churchId.isNotEmpty
                ? currentUser.churchId
                : otherUser.churchId,
            'member_ids': [currentUser.uid, otherUser.uid],
            'participant_key': key,
            'created_by': currentUser.uid,
            'last_message_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select()
          .single();

      return DirectConversation.fromMap(inserted);
    } on PostgrestException catch (error) {
      if (error.code != '23505') {
        throw Exception(_conversationErrorMessage(error));
      }

      final conversation = await _supabase
          .from('direct_conversations')
          .select()
          .eq('participant_key', key)
          .single();
      return DirectConversation.fromMap(conversation);
    }
  }

  Future<DirectConversation?> _tryGetOrCreateConversationViaRpc(
    String otherUserId,
  ) async {
    try {
      final data = await _supabase.rpc(
        'get_or_create_direct_conversation',
        params: {'other_user_id': otherUserId},
      );
      if (data is Map<String, dynamic>) {
        return DirectConversation.fromMap(data);
      }
      if (data is Map) {
        return DirectConversation.fromMap(Map<String, dynamic>.from(data));
      }
      if (data is List && data.isNotEmpty) {
        return DirectConversation.fromMap(
          Map<String, dynamic>.from(data.first),
        );
      }
    } on PostgrestException catch (error) {
      if (_isMissingFunctionError(error)) return null;
      rethrow;
    }
    return null;
  }

  bool _isMissingFunctionError(PostgrestException error) {
    final message = error.message.toLowerCase();
    return error.code == 'PGRST202' ||
        (message.contains('get_or_create_direct_conversation') ||
                message.contains('get_direct_conversation_peer')) &&
            message.contains('not found');
  }

  String _conversationErrorMessage(PostgrestException error) {
    final message = error.message.toLowerCase();
    if (message.contains('operator does not exist: uuid = text') ||
        message.contains('schema cache') ||
        message.contains('get_or_create_direct_conversation')) {
      return 'Messaging access was out of date. Refresh the app and try again. If this person is outside your church, send a Bible Nudge first and wait for them to accept it.';
    }
    if (message.contains('row-level security') ||
        message.contains('violates row-level security') ||
        error.code == '42501') {
      return 'Messaging is blocked by the current database policy. Apply the latest Supabase migration, then try again.';
    }
    return error.message;
  }

  Future<DirectConversation> getOrCreateConversationWithUserId({
    required UserProfile currentUser,
    required String otherUserId,
  }) async {
    if (currentUser.uid == otherUserId) {
      throw Exception('You cannot message yourself.');
    }

    try {
      final rpcConversation =
          await _tryGetOrCreateConversationViaRpc(otherUserId);
      if (rpcConversation != null) return rpcConversation;
    } on PostgrestException catch (error) {
      throw Exception(_conversationErrorMessage(error));
    }

    final otherUser = await UserService().getUserProfile(otherUserId);
    if (otherUser == null) {
      throw Exception('Member profile was not found.');
    }
    return getOrCreateConversation(
      currentUser: currentUser,
      otherUser: otherUser,
    );
  }

  Future<UserProfile?> getConversationPeer(
    DirectConversation conversation,
    String currentUserId,
  ) async {
    final viewerId = _currentUid.isNotEmpty ? _currentUid : currentUserId;
    final directPeerId = conversation.otherMemberId(viewerId);
    if (directPeerId.isNotEmpty) {
      final directProfile = await UserService().getUserProfile(directPeerId);
      if (directProfile != null) return directProfile;
    }

    try {
      final data = await _supabase.rpc(
        'get_direct_conversation_peer',
        params: {'target_conversation_id': conversation.id},
      );
      final map = _mapFromRpcResult(data);
      if (map != null) return UserProfile.fromMap(map);
    } on PostgrestException catch (error) {
      if (!_isMissingFunctionError(error)) {
        debugPrint('Could not resolve conversation peer: $error');
      }
    } catch (error) {
      debugPrint('Could not resolve conversation peer: $error');
    }

    final fallbackPeerId = directPeerId.isNotEmpty
        ? directPeerId
        : conversation.memberIds.firstWhere(
            (id) => id != viewerId,
            orElse: () => '',
          );
    if (fallbackPeerId.isEmpty) return null;

    return UserProfile(
      uid: fallbackPeerId,
      email: '',
      fullName: 'Member',
      phoneNumber: '',
      placeId: conversation.churchId,
      placeName: '',
      roles: const ['Member'],
      joinDate: DateTime.now(),
      allowMessages: true,
    );
  }

  Map<String, dynamic>? _mapFromRpcResult(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  Future<void> sendMessage({
    required String conversationId,
    required String text,
    String? mediaUrl,
    String? mediaPath,
    String mediaType = 'text',
    int? durationSeconds,
    Map<String, dynamic>? replyContext,
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
    final cleanReplyContext = sanitizeReplyContext(replyContext);
    final payload = {
      'id': const Uuid().v4(),
      'conversation_id': conversationId,
      'sender_id': uid,
      'text': cleanText,
      'media_url': cleanMediaUrl,
      'media_path': mediaPath,
      'media_type': mediaType,
      'duration_seconds': durationSeconds,
      'reply_context': cleanReplyContext,
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

    final preview = _previewForMessage(
      cleanText,
      mediaType,
      replyContext: cleanReplyContext,
    );
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
    if (message.mediaPath?.trim().isNotEmpty == true) {
      try {
        await _supabase.storage
            .from(_chatMediaBucket)
            .remove([message.mediaPath!.trim()]);
      } catch (error) {
        debugPrint('Message deleted, but media cleanup failed: $error');
      }
    }
    await _refreshConversationPreview(message.conversationId);
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

  List<DirectConversation> _normalizeConversations(List<dynamic> rows) {
    final conversationsById = <String, DirectConversation>{};
    for (final row in rows) {
      final conversation =
          DirectConversation.fromMap(Map<String, dynamic>.from(row));
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
  }

  String _previewForMessage(
    String text,
    String mediaType, {
    Map<String, dynamic> replyContext = const {},
  }) {
    if (replyContext['type'] == 'community_story') {
      return text.isEmpty ? 'Replied to a status' : 'Status reply: $text';
    }
    if (text.isNotEmpty) return text;
    return switch (mediaType) {
      'image' => 'Photo',
      'video' => 'Video',
      'voice' || 'audio' => 'Voice message',
      _ => 'Attachment',
    };
  }

  String previewForMessage(DirectMessage message) {
    return _previewForMessage(
      message.text.trim(),
      message.mediaType,
      replyContext: message.replyContext,
    );
  }

  Future<void> _refreshConversationPreview(String conversationId) async {
    if (conversationId.isEmpty) return;

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final rows = await _supabase
          .from('direct_messages')
          .select()
          .eq('conversation_id', conversationId)
          .or('expires_at.is.null,expires_at.gt.$now')
          .order('created_at', ascending: false)
          .limit(1);

      if (rows.isNotEmpty) {
        final latest = DirectMessage.fromMap(
          Map<String, dynamic>.from(rows.first),
        );
        await _supabase.from('direct_conversations').update({
          'last_message': previewForMessage(latest),
          'last_sender_id': latest.senderId,
          'last_message_at': latest.createdAt.toUtc().toIso8601String(),
        }).eq('id', conversationId);
        return;
      }

      final conversation = await _supabase
          .from('direct_conversations')
          .select('created_at')
          .eq('id', conversationId)
          .maybeSingle();
      final createdAt = DateTime.tryParse(
            conversation?['created_at']?.toString() ?? '',
          ) ??
          DateTime.now().toUtc();

      await _supabase.from('direct_conversations').update({
        'last_message': null,
        'last_sender_id': null,
        'last_message_at': createdAt.toUtc().toIso8601String(),
      }).eq('id', conversationId);
    } catch (error) {
      debugPrint('Could not refresh conversation preview: $error');
    }
  }

  bool _isMissingColumnError(PostgrestException error) {
    final message = error.message.toLowerCase();
    return error.code == 'PGRST204' ||
        message.contains('column') && message.contains('schema cache');
  }

  @visibleForTesting
  static Map<String, dynamic> sanitizeReplyContext(
    Map<String, dynamic>? replyContext,
  ) {
    final cleanReplyContext = <String, dynamic>{};
    if (replyContext != null) {
      replyContext.forEach((key, value) {
        cleanReplyContext[key] = _mutableJsonValue(value);
      });
      cleanReplyContext.removeWhere((_, value) => value == null);
    }
    return cleanReplyContext;
  }

  static dynamic _mutableJsonValue(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.fromEntries(
        value.entries.map(
          (entry) => MapEntry(
            entry.key.toString(),
            _mutableJsonValue(entry.value),
          ),
        ),
      )..removeWhere((_, nestedValue) => nestedValue == null);
    }
    if (value is List) {
      return value
          .map(_mutableJsonValue)
          .where((item) => item != null)
          .toList();
    }
    return value;
  }
}
