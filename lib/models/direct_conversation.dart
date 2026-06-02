class DirectConversation {
  const DirectConversation({
    required this.id,
    required this.churchId,
    required this.memberIds,
    required this.participantKey,
    required this.createdBy,
    required this.createdAt,
    this.lastMessage,
    this.lastSenderId,
    this.lastMessageAt,
    this.hiddenFor = const [],
  });

  final String id;
  final String churchId;
  final List<String> memberIds;
  final String participantKey;
  final String createdBy;
  final DateTime createdAt;
  final String? lastMessage;
  final String? lastSenderId;
  final DateTime? lastMessageAt;
  final List<String> hiddenFor;

  bool isHiddenFor(String userId) => hiddenFor.contains(userId);

  factory DirectConversation.fromMap(Map<String, dynamic> data) {
    return DirectConversation(
      id: data['id']?.toString() ?? '',
      churchId: data['church_id'] ?? data['churchId'] ?? '',
      memberIds:
          List<String>.from(data['member_ids'] ?? data['memberIds'] ?? []),
      participantKey: data['participant_key'] ?? data['participantKey'] ?? '',
      createdBy: data['created_by'] ?? data['createdBy'] ?? '',
      createdAt: _parseDate(data['created_at'] ?? data['createdAt']),
      lastMessage: data['last_message'] ?? data['lastMessage'],
      lastSenderId: data['last_sender_id'] ?? data['lastSenderId'],
      lastMessageAt:
          _nullableDate(data['last_message_at'] ?? data['lastMessageAt']),
      hiddenFor: _parseStringList(data['hidden_for'] ?? data['hiddenFor']),
    );
  }

  String otherMemberId(String currentUserId) {
    return memberIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
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

  static List<String> _parseStringList(dynamic value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    return const [];
  }
}
