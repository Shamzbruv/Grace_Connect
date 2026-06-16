class BibleNudge {
  const BibleNudge({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    required this.recipientName,
    required this.churchId,
    required this.message,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String recipientId;
  final String recipientName;
  final String churchId;
  final String message;
  final String status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  factory BibleNudge.fromMap(Map<String, dynamic> data) {
    return BibleNudge(
      id: data['id']?.toString() ?? '',
      senderId: data['sender_id']?.toString() ?? '',
      senderName: data['sender_name'] ?? 'Someone',
      recipientId: data['recipient_id']?.toString() ?? '',
      recipientName: data['recipient_name'] ?? 'Member',
      churchId: data['church_id'] ?? '',
      message: data['message'] ?? '',
      status: data['status'] ?? 'pending',
      createdAt: DateTime.tryParse(data['created_at']?.toString() ?? '') ??
          DateTime.now(),
      respondedAt: DateTime.tryParse(data['responded_at']?.toString() ?? ''),
    );
  }
}
