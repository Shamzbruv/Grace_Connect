

class PriorityFollowUp {
  final String id;
  final String userId;
  final String userName;
  final String userPhotoUrl;
  final String churchId;
  final DateTime flaggedAt;
  final int absenceStreakWeeks;
  final DateTime? lastAttendedDate;
  final String status; // 'open', 'acknowledged', 'resolved'
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final List<String> notes;

  PriorityFollowUp({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhotoUrl,
    required this.churchId,
    required this.flaggedAt,
    required this.absenceStreakWeeks,
    this.lastAttendedDate,
    this.status = 'open',
    this.resolvedBy,
    this.resolvedAt,
    this.notes = const [],
  });

  factory PriorityFollowUp.fromMap(Map<String, dynamic> data) {
    return PriorityFollowUp(
      id: data['id'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Unknown',
      userPhotoUrl: data['userPhotoUrl'] ?? '',
      churchId: data['churchId'] ?? '',
      flaggedAt: data['flaggedAt'] != null ? DateTime.parse(data['flaggedAt']) : DateTime.now(),
      absenceStreakWeeks: data['absenceStreakWeeks'] ?? 0,
      lastAttendedDate: data['lastAttendedDate'] != null ? DateTime.parse(data['lastAttendedDate']) : null,
      status: data['status'] ?? 'open',
      resolvedBy: data['resolvedBy'],
      resolvedAt: data['resolvedAt'] != null ? DateTime.parse(data['resolvedAt']) : null,
      notes: List<String>.from(data['notes'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'userPhotoUrl': userPhotoUrl,
      'churchId': churchId,
      'flaggedAt': flaggedAt.toIso8601String(),
      'absenceStreakWeeks': absenceStreakWeeks,
      'lastAttendedDate': lastAttendedDate?.toIso8601String(),
      'status': status,
      'resolvedBy': resolvedBy,
      'resolvedAt': resolvedAt?.toIso8601String(),
      'notes': notes,
    };
  }
}
