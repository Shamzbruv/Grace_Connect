class StudyGroup {
  final String id;
  final String name;
  final String topic;
  final String description;
  final String leaderId;
  final String leaderName;
  final List<String> adminIds;
  final List<String> memberIds;
  final String schedule; // e.g. "Fridays 7PM"
  final String churchId;
  final DateTime createdAt;
  final bool allowMemberMessages;
  final bool isPrivate;
  final bool requireJoinApproval;

  StudyGroup({
    required this.id,
    required this.name,
    required this.topic,
    required this.description,
    required this.leaderId,
    required this.leaderName,
    this.adminIds = const [],
    required this.memberIds,
    required this.schedule,
    required this.churchId,
    required this.createdAt,
    this.allowMemberMessages = true,
    this.isPrivate = false,
    this.requireJoinApproval = false,
  });

  factory StudyGroup.fromMap(Map<String, dynamic> data) {
    return StudyGroup(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      topic: data['topic'] ?? '',
      description: data['description'] ?? '',
      leaderId: data['leaderId'] ?? '',
      leaderName: data['leaderName'] ?? 'Unknown',
      adminIds: List<String>.from(data['adminIds'] ?? []),
      memberIds: List<String>.from(data['memberIds'] ?? []),
      schedule: data['schedule'] ?? '',
      churchId: data['churchId'] ?? '',
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'])
          : DateTime.now(),
      allowMemberMessages: data['allowMemberMessages'] ?? true,
      isPrivate: data['isPrivate'] ?? false,
      requireJoinApproval: data['requireJoinApproval'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'topic': topic,
      'description': description,
      'leaderId': leaderId,
      'leaderName': leaderName,
      'adminIds': adminIds,
      'memberIds': memberIds,
      'schedule': schedule,
      'churchId': churchId,
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'allowMemberMessages': allowMemberMessages,
      'isPrivate': isPrivate,
      'requireJoinApproval': requireJoinApproval,
    };
  }

  StudyGroup copyWith({
    String? id,
    String? name,
    String? topic,
    String? description,
    String? leaderId,
    String? leaderName,
    List<String>? adminIds,
    List<String>? memberIds,
    String? schedule,
    String? churchId,
    DateTime? createdAt,
    bool? allowMemberMessages,
    bool? isPrivate,
    bool? requireJoinApproval,
  }) {
    return StudyGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      topic: topic ?? this.topic,
      description: description ?? this.description,
      leaderId: leaderId ?? this.leaderId,
      leaderName: leaderName ?? this.leaderName,
      adminIds: adminIds ?? this.adminIds,
      memberIds: memberIds ?? this.memberIds,
      schedule: schedule ?? this.schedule,
      churchId: churchId ?? this.churchId,
      createdAt: createdAt ?? this.createdAt,
      allowMemberMessages: allowMemberMessages ?? this.allowMemberMessages,
      isPrivate: isPrivate ?? this.isPrivate,
      requireJoinApproval: requireJoinApproval ?? this.requireJoinApproval,
    );
  }
}
