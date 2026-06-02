class PrayerRequest {
  final String id;
  final String userId;
  final String churchId;
  final String userName; // Display name (or 'Anonymous')
  final String title;
  final String content;
  final bool isAnonymous;
  final bool isPrivate; // Only visible to prayer team/pastors
  final String status; // 'submitted', 'acknowledged', 'prayed', 'closed'
  final DateTime createdAt;
  final List<String> prayedBy; // List of userIds who prayed

  PrayerRequest({
    required this.id,
    required this.userId,
    required this.churchId,
    required this.userName,
    this.title = 'Prayer Request',
    required this.content,
    this.isAnonymous = false,
    this.isPrivate = true,
    this.status = 'submitted',
    required this.createdAt,
    this.prayedBy = const [],
  });

  factory PrayerRequest.fromMap(Map<String, dynamic> data) {
    return PrayerRequest(
      id: data['id'] ?? '',
      userId: data['userId'] ?? '',
      churchId: data['churchId'] ?? '',
      userName: data['userName'] ?? 'Anonymous',
      title: data['title'] ?? 'Prayer Request',
      content: data['content'] ?? data['description'] ?? '',
      isAnonymous: data['isAnonymous'] ?? false,
      isPrivate: data['isPrivate'] ?? true,
      status: data['status'] ?? 'active',
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'])
          : DateTime.now(),
      prayedBy: List<String>.from(data['prayedBy'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'churchId': churchId,
      'userName': userName,
      'title': title,
      'content': content,
      'description': content,
      'isAnonymous': isAnonymous,
      'isPrivate': isPrivate,
      'status': status,
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'prayedBy': prayedBy,
    };
  }
}
