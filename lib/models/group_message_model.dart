class GroupMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String senderPhotoUrl;
  final String text;
  final DateTime timestamp;

  GroupMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderPhotoUrl = '',
    required this.text,
    required this.timestamp,
  });

  factory GroupMessage.fromMap(Map<String, dynamic> data) {
    return GroupMessage(
      id: data['id'] ?? '',
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      senderPhotoUrl: data['senderPhotoUrl'] ?? '',
      text: data['text'] ?? '',
      timestamp: data['timestamp'] != null
          ? DateTime.parse(data['timestamp'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderPhotoUrl': senderPhotoUrl,
      'text': text,
      'id': id,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
