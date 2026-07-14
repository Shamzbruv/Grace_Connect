class StudyReadingPlan {
  final String id;
  final String groupId;
  final String title;
  final String description;
  final String translation;
  final DateTime? startDate;
  final DateTime? endDate;
  final String createdBy;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const StudyReadingPlan({
    required this.id,
    required this.groupId,
    required this.title,
    this.description = '',
    this.translation = 'KJV',
    this.startDate,
    this.endDate,
    this.createdBy = '',
    this.status = 'active',
    this.createdAt,
    this.updatedAt,
  });

  factory StudyReadingPlan.fromMap(Map<String, dynamic> data) {
    return StudyReadingPlan(
      id: _string(data['id']),
      groupId: _string(data['group_id'] ?? data['groupId']),
      title: _string(data['title']),
      description: _string(data['description']),
      translation: _string(data['translation']).isEmpty
          ? 'KJV'
          : _string(data['translation']),
      startDate: _parseDate(data['start_date'] ?? data['startDate']),
      endDate: _parseDate(data['end_date'] ?? data['endDate']),
      createdBy: _string(data['created_by'] ?? data['createdBy']),
      status:
          _string(data['status']).isEmpty ? 'active' : _string(data['status']),
      createdAt: _parseDate(data['created_at']),
      updatedAt: _parseDate(data['updated_at']),
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
