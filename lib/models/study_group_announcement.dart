class StudyGroupAnnouncement {
  final String id;
  final String groupId;
  final String authorId;
  final String title;
  final String body;
  final bool pinned;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  const StudyGroupAnnouncement({
    required this.id,
    required this.groupId,
    required this.authorId,
    this.title = '',
    this.body = '',
    this.pinned = false,
    this.expiresAt,
    this.createdAt,
  });

  factory StudyGroupAnnouncement.fromMap(Map<String, dynamic> data) {
    return StudyGroupAnnouncement(
      id: _string(data['id']),
      groupId: _string(data['group_id'] ?? data['groupId']),
      authorId: _string(data['author_id'] ?? data['authorId']),
      title: _string(data['title']),
      body: _string(data['body']),
      pinned: data['pinned'] == true,
      expiresAt: _parseDate(data['expires_at']),
      createdAt: _parseDate(data['created_at']),
    );
  }

  static String _string(dynamic value) => value?.toString() ?? '';

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
