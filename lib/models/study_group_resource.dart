class StudyGroupResource {
  final String id;
  final String groupId;
  final String authorId;
  final String title;
  final String description;
  final String category;
  final String resourceUrl;
  final String storagePath;
  final bool approved;
  final DateTime? createdAt;

  const StudyGroupResource({
    required this.id,
    required this.groupId,
    required this.authorId,
    this.title = '',
    this.description = '',
    this.category = 'Other',
    this.resourceUrl = '',
    this.storagePath = '',
    this.approved = true,
    this.createdAt,
  });

  factory StudyGroupResource.fromMap(Map<String, dynamic> data) {
    return StudyGroupResource(
      id: _string(data['id']),
      groupId: _string(data['group_id'] ?? data['groupId']),
      authorId: _string(data['author_id'] ?? data['authorId']),
      title: _string(data['title']),
      description: _string(data['description']),
      category: _string(data['category']).isEmpty
          ? 'Other'
          : _string(data['category']),
      resourceUrl: _string(data['resource_url']),
      storagePath: _string(data['storage_path']),
      approved: data['approved'] != false,
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
