class StudyReadingProgress {
  final String id;
  final String assignmentId;
  final String userId;
  final String status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String reflection;
  final String privacy;

  const StudyReadingProgress({
    required this.id,
    required this.assignmentId,
    required this.userId,
    this.status = 'not_started',
    this.startedAt,
    this.completedAt,
    this.reflection = '',
    this.privacy = 'group_summary',
  });

  factory StudyReadingProgress.fromMap(Map<String, dynamic> data) {
    return StudyReadingProgress(
      id: _string(data['id']),
      assignmentId: _string(data['assignment_id'] ?? data['assignmentId']),
      userId: _string(data['user_id'] ?? data['userId']),
      status: _string(data['status']).isEmpty
          ? 'not_started'
          : _string(data['status']),
      startedAt: _parseDate(data['started_at']),
      completedAt: _parseDate(data['completed_at']),
      reflection: _string(data['reflection']),
      privacy: _string(data['privacy']).isEmpty
          ? 'group_summary'
          : _string(data['privacy']),
    );
  }

  bool get isCompleted => status == 'completed';

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
