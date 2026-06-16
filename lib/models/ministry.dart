class Ministry {
  const Ministry({
    required this.id,
    required this.churchId,
    required this.name,
    required this.description,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String churchId;
  final String name;
  final String description;
  final String status;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status == 'active';

  factory Ministry.fromMap(Map<String, dynamic> data) {
    return Ministry(
      id: data['id']?.toString() ?? '',
      churchId: data['church_id']?.toString() ?? '',
      name: data['name']?.toString() ?? 'Ministry',
      description: data['description']?.toString() ?? '',
      status: data['status']?.toString() ?? 'active',
      createdBy: data['created_by']?.toString() ?? '',
      createdAt: DateTime.tryParse(data['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(data['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class MinistryManager {
  const MinistryManager({
    required this.id,
    required this.ministryId,
    required this.ministryName,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userPhotoUrl,
    required this.roleTitle,
    required this.canCreateEvents,
    required this.canPublishAnnouncements,
    required this.assignedBy,
    required this.assignedAt,
    this.revokedAt,
  });

  final String id;
  final String ministryId;
  final String ministryName;
  final String userId;
  final String userName;
  final String userEmail;
  final String userPhotoUrl;
  final String roleTitle;
  final bool canCreateEvents;
  final bool canPublishAnnouncements;
  final String assignedBy;
  final DateTime assignedAt;
  final DateTime? revokedAt;

  bool get isActive => revokedAt == null;

  factory MinistryManager.fromMap(Map<String, dynamic> data) {
    return MinistryManager(
      id: data['id']?.toString() ?? '',
      ministryId: data['ministry_id']?.toString() ?? '',
      ministryName: data['ministry_name']?.toString() ?? '',
      userId: data['user_id']?.toString() ?? '',
      userName: data['user_name']?.toString() ?? 'Member',
      userEmail: data['user_email']?.toString() ?? '',
      userPhotoUrl: data['user_photo_url']?.toString() ?? '',
      roleTitle: data['role_title']?.toString() ?? 'Ministry Manager',
      canCreateEvents: data['can_create_events'] != false,
      canPublishAnnouncements: data['can_publish_announcements'] != false,
      assignedBy: data['assigned_by']?.toString() ?? '',
      assignedAt: DateTime.tryParse(data['assigned_at']?.toString() ?? '') ??
          DateTime.now(),
      revokedAt: DateTime.tryParse(data['revoked_at']?.toString() ?? ''),
    );
  }
}
