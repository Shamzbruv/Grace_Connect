class StudyGroupMembership {
  final String id;
  final String groupId;
  final String userId;
  final String membershipStatus;
  final String groupRole;
  final String invitedBy;
  final DateTime? requestedAt;
  final DateTime? approvedAt;
  final String approvedBy;
  final DateTime? joinedAt;
  final DateTime? lastOpenedAt;
  final String notificationLevel;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const StudyGroupMembership({
    required this.id,
    required this.groupId,
    required this.userId,
    this.membershipStatus = 'active',
    this.groupRole = 'member',
    this.invitedBy = '',
    this.requestedAt,
    this.approvedAt,
    this.approvedBy = '',
    this.joinedAt,
    this.lastOpenedAt,
    this.notificationLevel = 'all',
    this.createdAt,
    this.updatedAt,
  });

  factory StudyGroupMembership.fromMap(Map<String, dynamic> data) {
    return StudyGroupMembership(
      id: _string(data['id']),
      groupId: _string(data['group_id'] ?? data['groupId']),
      userId: _string(data['user_id'] ?? data['userId']),
      membershipStatus: _string(data['membership_status']).isEmpty
          ? 'active'
          : _string(data['membership_status']),
      groupRole: _string(data['group_role']).isEmpty
          ? 'member'
          : _string(data['group_role']),
      invitedBy: _string(data['invited_by']),
      requestedAt: _parseDate(data['requested_at']),
      approvedAt: _parseDate(data['approved_at']),
      approvedBy: _string(data['approved_by']),
      joinedAt: _parseDate(data['joined_at']),
      lastOpenedAt: _parseDate(data['last_opened_at']),
      notificationLevel: _string(data['notification_level']).isEmpty
          ? 'all'
          : _string(data['notification_level']),
      createdAt: _parseDate(data['created_at']),
      updatedAt: _parseDate(data['updated_at']),
    );
  }

  bool get isActive => membershipStatus == 'active';
  bool get isPending => membershipStatus == 'pending';
  bool get isInvited => membershipStatus == 'invited';
  bool get isAdmin => groupRole == 'admin' || groupRole == 'co_leader';
  bool get isLeader => groupRole == 'leader';

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
