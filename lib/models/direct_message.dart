class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    required this.isRead,
    this.mediaUrl,
    this.mediaPath,
    this.mediaType = 'text',
    this.durationSeconds,
    this.deliveredAt,
    this.readAt,
    this.deletedFor = const [],
    this.expiresAt,
    this.replyContext = const {},
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final bool isRead;
  final String? mediaUrl;
  final String? mediaPath;
  final String mediaType;
  final int? durationSeconds;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final List<String> deletedFor;
  final DateTime? expiresAt;
  final Map<String, dynamic> replyContext;

  bool get hasMedia => mediaUrl?.isNotEmpty == true;
  bool get isDelivered => deliveredAt != null || isRead || readAt != null;
  bool get isSeen => readAt != null || isRead;
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool isDeletedFor(String userId) => deletedFor.contains(userId);

  factory DirectMessage.fromMap(Map<String, dynamic> data) {
    return DirectMessage(
      id: data['id']?.toString() ?? '',
      conversationId:
          data['conversation_id']?.toString() ?? data['conversationId'] ?? '',
      senderId: data['sender_id'] ?? data['senderId'] ?? '',
      text: data['text'] ?? '',
      createdAt: _parseDate(data['created_at'] ?? data['createdAt']),
      isRead: data['is_read'] ?? data['isRead'] ?? false,
      mediaUrl: data['media_url'] ?? data['mediaUrl'],
      mediaPath: data['media_path'] ?? data['mediaPath'],
      mediaType: (data['media_type'] ?? data['mediaType'] ?? 'text').toString(),
      durationSeconds:
          _parseInt(data['duration_seconds'] ?? data['durationSeconds']),
      deliveredAt: _nullableDate(data['delivered_at'] ?? data['deliveredAt']),
      readAt: _nullableDate(data['read_at'] ?? data['readAt']),
      deletedFor: _parseStringList(data['deleted_for'] ?? data['deletedFor']),
      expiresAt: _nullableDate(data['expires_at'] ?? data['expiresAt']),
      replyContext: _parseMap(data['reply_context'] ?? data['replyContext']),
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is String) {
      return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
    }
    return DateTime.now();
  }

  static DateTime? _nullableDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    return const [];
  }

  static Map<String, dynamic> _parseMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }
}
