import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/direct_conversation.dart';
import '../models/direct_message.dart';
import '../models/direct_message_request.dart';
import '../models/user_profile.dart';
import 'notification_service.dart';
import 'user_service.dart';

class DirectMessageService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _chatMediaBucket = 'chat_media';
  static const Duration _realtimeQuietTimeout = Duration(seconds: 18);

  String get _currentUid => _supabase.auth.currentUser?.id ?? '';
  String get currentUserId => _currentUid;

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

  Future<List<DirectMessageRequest>> fetchMessageRequests() async {
    final rows = await _supabase
        .from('direct_message_requests')
        .select()
        .order('created_at', ascending: false)
        .limit(100);
    return _normalizeMessageRequests(rows);
  }

  Stream<List<DirectMessageRequest>> watchMessageRequests() async* {
    var lastKnown = <DirectMessageRequest>[];
    try {
      lastKnown = await fetchMessageRequests();
      yield lastKnown;
    } catch (error) {
      debugPrint('Could not load message requests before realtime: $error');
    }

    try {
      await for (final requests in _supabase
          .from('direct_message_requests')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .map(_normalizeMessageRequests)
          .timeout(
            _realtimeQuietTimeout,
            onTimeout: (sink) => sink.add(lastKnown),
          )) {
        lastKnown = requests;
        yield requests;
      }
    } catch (error) {
      debugPrint(
        'Message-request realtime unavailable, keeping last known data: $error',
      );
      yield lastKnown;
    }
  }

  Stream<int> watchPendingMessageRequestCount() {
    final uid = _currentUid;
    if (uid.isEmpty) return const Stream<int>.empty();
    return watchMessageRequests().map(
      (requests) => requests
          .where((request) => request.isPending && request.recipientId == uid)
          .length,
    );
  }

  Future<DirectMessageRequest?> getMessageRequest(String requestId) async {
    final cleanId = requestId.trim();
    if (cleanId.isEmpty) return null;
    final row = await _supabase
        .from('direct_message_requests')
        .select()
        .eq('id', cleanId)
        .maybeSingle();
    return row == null ? null : DirectMessageRequest.fromMap(row);
  }

  Future<DirectMessageRequest> sendMessageRequest({
    required UserProfile recipient,
    required String reason,
    required String intendedMessage,
  }) async {
    final cleanReason = reason.trim();
    final cleanMessage = intendedMessage.trim();
    if (_currentUid.isEmpty) {
      throw Exception('Sign in before sending a message request.');
    }
    if (recipient.uid.trim().isEmpty || recipient.uid == _currentUid) {
      throw Exception('Choose another person for this message request.');
    }
    if (cleanReason.length < 3) {
      throw Exception('Tell them why you would like to message.');
    }
    if (cleanMessage.isEmpty) {
      throw Exception('Write the first message you want them to receive.');
    }

    final requestId = const Uuid().v4();
    final data = await _supabase.rpc(
      'request_direct_message',
      params: {
        'recipient_user_id': recipient.uid,
        'request_reason': cleanReason,
        'first_message': cleanMessage,
        'client_request_id': requestId,
      },
    );
    final map = _mapFromRpcResult(data);
    if (map == null) {
      throw Exception('The message request could not be saved.');
    }
    final request = DirectMessageRequest.fromMap(map);
    await _sendMessageRequestPush(request.id, event: 'request');
    return request;
  }

  Future<DirectMessageRequestDecision> respondToMessageRequest({
    required DirectMessageRequest request,
    required bool accepted,
    String responseMessage = '',
  }) async {
    if (_currentUid.isEmpty || request.recipientId != _currentUid) {
      throw Exception('Only the recipient can answer this message request.');
    }
    final data = await _supabase.rpc(
      'respond_to_direct_message_request',
      params: {
        'target_request_id': request.id,
        'accept_request': accepted,
        'response_note': responseMessage.trim(),
      },
    );
    final map = _mapFromRpcResult(data);
    if (map == null) {
      throw Exception('The message request response was incomplete.');
    }
    final decision = DirectMessageRequestDecision.fromMap(map);
    await _sendMessageRequestPush(
      request.id,
      event: accepted ? 'accepted' : 'denied',
    );
    return decision;
  }

  Future<DirectMessageRequest> cancelMessageRequest(
    DirectMessageRequest request,
  ) async {
    if (_currentUid.isEmpty || request.senderId != _currentUid) {
      throw Exception('Only the sender can cancel this message request.');
    }
    final data = await _supabase.rpc(
      'cancel_direct_message_request',
      params: {'target_request_id': request.id},
    );
    final map = _mapFromRpcResult(data);
    if (map == null) {
      throw Exception('The message request could not be cancelled.');
    }
    return DirectMessageRequest.fromMap(map);
  }

  Future<UserProfile?> getMessageRequestPeer(
    DirectMessageRequest request,
  ) {
    final peerId = request.senderId == _currentUid
        ? request.recipientId
        : request.senderId;
    return UserService().getUserProfile(peerId);
  }

  Future<void> _sendMessageRequestPush(
    String requestId, {
    required String event,
  }) async {
    if (requestId.trim().isEmpty) return;
    try {
      final response = await _supabase.functions.invoke(
        'send-message-request-push',
        body: {'requestId': requestId.trim(), 'event': event},
      ).timeout(const Duration(seconds: 12));
      if (response.data case final Map data when data['ok'] == false) {
        debugPrint('Message-request push queued with warning: $data');
      }
    } catch (error) {
      // The transaction already created the in-app notification. Keep the
      // consent decision successful while surfacing push failures in logs.
      debugPrint('Message-request push skipped: $error');
    }
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

    try {
      final rpcConversation =
          await _tryGetOrCreateConversationViaRpc(otherUser.uid);
      if (rpcConversation != null) {
        return rpcConversation;
      }
    } on PostgrestException catch (error) {
      throw _conversationException(error);
    }
    throw Exception(
      'Messaging access is unavailable until the latest update is applied.',
    );
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

  Object _conversationException(PostgrestException error) {
    final message = error.message.toLowerCase();
    final details = error.details?.toString().toLowerCase() ?? '';
    if (message.contains('message request is required') ||
        details.contains('message_request_required')) {
      return MessageRequestRequiredException(error.message);
    }
    if (message.contains('send another request after') ||
        details.contains('message_request_cooldown')) {
      return MessageRequestCooldownException(error.message);
    }
    if (message.contains('operator does not exist: uuid = text') ||
        message.contains('schema cache') ||
        message.contains('get_or_create_direct_conversation')) {
      return Exception(
        'Messaging access is out of date. Refresh the app and try again.',
      );
    }
    if (message.contains('row-level security') ||
        message.contains('violates row-level security') ||
        error.code == '42501') {
      return Exception(
        'Messaging is blocked by the current privacy policy. Refresh and try again.',
      );
    }
    return Exception(error.message);
  }

  bool isMessageRequestRequiredError(Object error) =>
      error is MessageRequestRequiredException ||
      error.toString().toLowerCase().contains('message request is required');

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
      throw _conversationException(error);
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
    String? recipientUserId,
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

    final cleanRecipientUserId = recipientUserId?.trim() ?? '';
    if (cleanRecipientUserId.isNotEmpty && cleanRecipientUserId != uid) {
      unawaited(
        NotificationService().sendDirectMessagePush(
          recipientUserId: cleanRecipientUserId,
          senderName: _currentSenderDisplayName(),
          conversationId: conversationId,
          messageId: payload['id'].toString(),
          preview: preview,
        ),
      );
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

  List<DirectMessageRequest> _normalizeMessageRequests(List<dynamic> rows) {
    final byId = <String, DirectMessageRequest>{};
    for (final row in rows) {
      final request = DirectMessageRequest.fromMap(
        Map<String, dynamic>.from(row),
      );
      if (request.id.isNotEmpty) byId[request.id] = request;
    }
    final requests = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return requests;
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

  String _currentSenderDisplayName() {
    final user = _supabase.auth.currentUser;
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    for (final key in const ['full_name', 'fullName', 'name', 'display_name']) {
      final value = metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    return 'New message';
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

class MessageRequestRequiredException implements Exception {
  const MessageRequestRequiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MessageRequestCooldownException implements Exception {
  const MessageRequestCooldownException(this.message);

  final String message;

  @override
  String toString() => message;
}
