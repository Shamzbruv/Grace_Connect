

class CounselingRequest {
  final String id;
  final String userId;
  final String churchId;
  final String
      category; // e.g., 'Marriage', 'Grief', 'Spiritual', 'Addiction', 'Other'
  final String urgency; // 'Low', 'Medium', 'High'
  final String preferredContactMethod; // 'Phone', 'Email', 'In-Person'
  final String description;
  final String status; // 'pending', 'scheduled', 'completed', 'cancelled'
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final String? assignedToHelperId; // ID of the pastor/counselor

  CounselingRequest({
    required this.id,
    required this.userId,
    required this.churchId,
    required this.category,
    required this.urgency,
    required this.preferredContactMethod,
    required this.description,
    this.status = 'pending',
    required this.createdAt,
    this.scheduledAt,
    this.assignedToHelperId,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'churchId': churchId,
      'category': category,
      'urgency': urgency,
      'preferredContactMethod': preferredContactMethod,
      'description': description,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'scheduledAt': scheduledAt?.toIso8601String(),
      'assignedToHelperId': assignedToHelperId,
    };
  }

  factory CounselingRequest.fromMap(Map<String, dynamic> data) {
    return CounselingRequest(
      id: data['id'] ?? '',
      userId: data['userId'] ?? '',
      churchId: data['churchId'] ?? '',
      category: data['category'] ?? 'Other',
      urgency: data['urgency'] ?? 'Low',
      preferredContactMethod: data['preferredContactMethod'] ?? 'Email',
      description: data['description'] ?? '',
      status: data['status'] ?? 'pending',
      createdAt: data['createdAt'] != null ? DateTime.parse(data['createdAt']) : DateTime.now(),
      scheduledAt: data['scheduledAt'] != null ? DateTime.parse(data['scheduledAt']) : null,
      assignedToHelperId: data['assignedToHelperId'],
    );
  }
}
