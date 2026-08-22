class DirectMessageRequest {
  const DirectMessageRequest({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.reason,
    required this.intendedMessage,
    required this.status,
    required this.createdAt,
    this.senderChurchId,
    this.recipientChurchId,
    this.responseMessage,
    this.conversationId,
    this.deliveredMessageId,
    this.respondedAt,
  });

  final String id;
  final String senderId;
  final String recipientId;
  final String? senderChurchId;
  final String? recipientChurchId;
  final String reason;
  final String intendedMessage;
  final String status;
  final String? responseMessage;
  final String? conversationId;
  final String? deliveredMessageId;
  final DateTime createdAt;
  final DateTime? respondedAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDenied => status == 'denied';
  bool get isCancelled => status == 'cancelled';

  bool isIncomingFor(String userId) => recipientId == userId;
  bool isOutgoingFor(String userId) => senderId == userId;

  DateTime? get retryAvailableAt => isDenied && respondedAt != null
      ? respondedAt!.add(const Duration(days: 30))
      : null;

  factory DirectMessageRequest.fromMap(Map<String, dynamic> data) {
    return DirectMessageRequest(
      id: data['id']?.toString() ?? '',
      senderId: data['sender_id']?.toString() ?? '',
      recipientId: data['recipient_id']?.toString() ?? '',
      senderChurchId: _nullableText(data['sender_church_id']),
      recipientChurchId: _nullableText(data['recipient_church_id']),
      reason: data['reason']?.toString() ?? '',
      intendedMessage: data['intended_message']?.toString() ?? '',
      status: data['status']?.toString() ?? 'pending',
      responseMessage: _nullableText(data['response_message']),
      conversationId: _nullableText(data['conversation_id']),
      deliveredMessageId: _nullableText(data['delivered_message_id']),
      createdAt: _date(data['created_at']) ?? DateTime.now(),
      respondedAt: _date(data['responded_at']),
    );
  }

  static String? _nullableText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _date(dynamic value) {
    if (value is DateTime) return value.toLocal();
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}

class DirectMessageRequestDecision {
  const DirectMessageRequestDecision({
    required this.request,
    required this.deduplicated,
    this.conversationId,
    this.messageId,
  });

  final DirectMessageRequest request;
  final String? conversationId;
  final String? messageId;
  final bool deduplicated;

  factory DirectMessageRequestDecision.fromMap(Map<String, dynamic> data) {
    final requestData = data['request'];
    if (requestData is! Map) {
      throw const FormatException('Message request response was incomplete.');
    }
    return DirectMessageRequestDecision(
      request: DirectMessageRequest.fromMap(
        Map<String, dynamic>.from(requestData),
      ),
      conversationId: _nullableText(data['conversation_id']),
      messageId: _nullableText(data['message_id']),
      deduplicated: data['deduplicated'] == true,
    );
  }

  static String? _nullableText(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
