

class StudyRequest {
  final String id;
  final String requesterId;
  final String requesterName;
  final String topic;
  final String description;
  final String preferredTime;
  final String status; // 'open', 'matched', 'completed'
  final String? partnerId;
  final String placeId;
  final DateTime createdAt;

  StudyRequest({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    required this.topic,
    required this.description,
    required this.preferredTime,
    this.status = 'open',
    this.partnerId,
    required this.placeId,
    required this.createdAt,
  });

  factory StudyRequest.fromMap(Map<String, dynamic> data) {
    return StudyRequest(
      id: data['id'] ?? '',
      requesterId: data['requesterId'] ?? '',
      requesterName: data['requesterName'] ?? '',
      topic: data['topic'] ?? '',
      description: data['description'] ?? '',
      preferredTime: data['preferredTime'] ?? '',
      status: data['status'] ?? 'open',
      partnerId: data['partnerId'],
      placeId: data['placeId'] ?? '',
      createdAt: data['createdAt'] != null ? DateTime.parse(data['createdAt']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'requesterId': requesterId,
      'requesterName': requesterName,
      'topic': topic,
      'description': description,
      'preferredTime': preferredTime,
      'status': status,
      'partnerId': partnerId,
      'placeId': placeId,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
