class StudyGroup {
  final String id;
  final String name;
  final String topic;
  final String description;
  final String leaderId;
  final String leaderName;
  final List<String> adminIds;
  final List<String> memberIds;
  final List<String> pendingMemberIds;
  final String schedule;
  final String churchId;
  final DateTime createdAt;
  final bool allowMemberMessages;
  final bool isPrivate;
  final bool requireJoinApproval;
  final String profilePhotoUrl;
  final String coverPhotoUrl;
  final String profilePhotoPath;
  final String coverPhotoPath;
  final String visibility;
  final String joinMode;
  final String status;
  final String groupType;
  final int? maxMembers;
  final String welcomeMessage;
  final String guidelines;
  final String currentBook;
  final int? currentChapter;
  final DateTime? studyStartDate;
  final DateTime? studyEndDate;
  final String meetingLocation;
  final String meetingLink;
  final DateTime? updatedAt;
  final DateTime? archivedAt;
  final String archivedBy;
  final String archiveReason;

  StudyGroup({
    required this.id,
    required this.name,
    required this.topic,
    required this.description,
    required this.leaderId,
    required this.leaderName,
    this.adminIds = const [],
    required this.memberIds,
    this.pendingMemberIds = const [],
    required this.schedule,
    required this.churchId,
    required this.createdAt,
    this.allowMemberMessages = true,
    this.isPrivate = false,
    this.requireJoinApproval = false,
    this.profilePhotoUrl = '',
    this.coverPhotoUrl = '',
    this.profilePhotoPath = '',
    this.coverPhotoPath = '',
    this.visibility = 'church',
    this.joinMode = 'approval',
    this.status = 'active',
    this.groupType = 'bible_study',
    this.maxMembers,
    this.welcomeMessage = '',
    this.guidelines = '',
    this.currentBook = '',
    this.currentChapter,
    this.studyStartDate,
    this.studyEndDate,
    this.meetingLocation = '',
    this.meetingLink = '',
    this.updatedAt,
    this.archivedAt,
    this.archivedBy = '',
    this.archiveReason = '',
  });

  factory StudyGroup.fromMap(Map<String, dynamic> data) {
    final legacyPrivate = _parseBool(data['isPrivate']);
    final legacyApproval = _parseBool(data['requireJoinApproval']);
    final visibility = _string(data['visibility']).isNotEmpty
        ? _string(data['visibility'])
        : legacyPrivate
            ? 'private'
            : 'church';
    final joinMode = _string(data['joinMode']).isNotEmpty
        ? _string(data['joinMode'])
        : legacyApproval
            ? 'approval'
            : 'open';

    return StudyGroup(
      id: _string(data['id']),
      name: _string(data['name']),
      topic: _string(data['topic']),
      description: _string(data['description']),
      leaderId: _string(data['leaderId']),
      leaderName: _string(data['leaderName']).isEmpty
          ? 'Unknown'
          : _string(data['leaderName']),
      adminIds: _stringList(data['adminIds']),
      memberIds: _stringList(data['memberIds']),
      pendingMemberIds: _stringList(data['pendingMemberIds']),
      schedule: _string(data['schedule']),
      churchId: _string(data['churchId']),
      createdAt: _parseDate(data['createdAt']) ?? DateTime.now(),
      allowMemberMessages: data['allowMemberMessages'] == null
          ? true
          : _parseBool(data['allowMemberMessages']),
      isPrivate: legacyPrivate,
      requireJoinApproval: legacyApproval,
      profilePhotoUrl: _string(data['profilePhotoUrl']),
      coverPhotoUrl: _string(data['coverPhotoUrl']),
      profilePhotoPath: _string(data['profilePhotoPath']),
      coverPhotoPath: _string(data['coverPhotoPath']),
      visibility: visibility,
      joinMode: joinMode,
      status:
          _string(data['status']).isEmpty ? 'active' : _string(data['status']),
      groupType: _string(data['groupType']).isEmpty
          ? 'bible_study'
          : _string(data['groupType']),
      maxMembers: _parseInt(data['maxMembers']),
      welcomeMessage: _string(data['welcomeMessage']),
      guidelines: _string(data['guidelines']),
      currentBook: _string(data['currentBook']),
      currentChapter: _parseInt(data['currentChapter']),
      studyStartDate: _parseDate(data['studyStartDate']),
      studyEndDate: _parseDate(data['studyEndDate']),
      meetingLocation: _string(data['meetingLocation']),
      meetingLink: _string(data['meetingLink']),
      updatedAt: _parseDate(data['updatedAt']),
      archivedAt: _parseDate(data['archived_at'] ?? data['archivedAt']),
      archivedBy: _string(data['archived_by'] ?? data['archivedBy']),
      archiveReason: _string(data['archive_reason'] ?? data['archiveReason']),
    );
  }

  bool get isArchived => status == 'archived';
  bool get isActive => status == 'active';
  bool get isChurchVisible => visibility == 'church';
  bool get isInvitationOnly =>
      visibility == 'invitation_only' || joinMode == 'invitation_only';
  bool get approvalRequired => joinMode == 'approval' || requireJoinApproval;
  bool get isOpenToJoin => joinMode == 'open' || joinMode == 'approval';
  int get memberCount =>
      {...memberIds, ...adminIds, if (leaderId.isNotEmpty) leaderId}.length;
  bool get hasMeeting => schedule.trim().isNotEmpty;

  String get displayStudy {
    if (currentBook.trim().isNotEmpty && currentChapter != null) {
      return '${currentBook.trim()} $currentChapter';
    }
    if (currentBook.trim().isNotEmpty) return currentBook.trim();
    if (topic.trim().isNotEmpty) return topic.trim();
    return 'Bible Study';
  }

  String get privacyLabel {
    return switch (visibility) {
      'private' => 'Private',
      'invitation_only' => 'Invitation Only',
      _ => 'Public to Church',
    };
  }

  String get joinModeLabel {
    return switch (joinMode) {
      'open' => 'Open',
      'invitation_only' => 'Invitation Only',
      'closed' => 'Closed',
      _ => 'Approval Required',
    };
  }

  double get progressValue {
    if (currentChapter == null || currentChapter! <= 0) return 0;
    return (currentChapter!.clamp(0, 16) / 16).toDouble();
  }

  String get progressLabel {
    if (currentBook.trim().isEmpty || currentChapter == null) {
      return 'Reading plan not set';
    }
    return '${currentBook.trim()} $currentChapter of 16 chapters';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'topic': topic,
      'description': description,
      'leaderId': leaderId,
      'leaderName': leaderName,
      'adminIds': adminIds,
      'memberIds': memberIds,
      'pendingMemberIds': pendingMemberIds,
      'schedule': schedule,
      'churchId': churchId,
      'createdAt': createdAt.toIso8601String(),
      'allowMemberMessages': allowMemberMessages,
      'isPrivate': visibility != 'church' || isPrivate,
      'requireJoinApproval':
          joinMode == 'approval' || joinMode == 'invitation_only',
      'profilePhotoUrl': profilePhotoUrl,
      'coverPhotoUrl': coverPhotoUrl,
      'profilePhotoPath': profilePhotoPath,
      'coverPhotoPath': coverPhotoPath,
      'visibility': visibility,
      'joinMode': joinMode,
      'status': status,
      'groupType': groupType,
      'maxMembers': maxMembers,
      'welcomeMessage': welcomeMessage,
      'guidelines': guidelines,
      'currentBook': currentBook,
      'currentChapter': currentChapter,
      'studyStartDate': studyStartDate?.toIso8601String(),
      'studyEndDate': studyEndDate?.toIso8601String(),
      'meetingLocation': meetingLocation,
      'meetingLink': meetingLink,
      'updatedAt': updatedAt?.toIso8601String(),
      'archived_at': archivedAt?.toIso8601String(),
      'archived_by': archivedBy,
      'archive_reason': archiveReason,
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
    List<String>? pendingMemberIds,
    String? schedule,
    String? churchId,
    DateTime? createdAt,
    bool? allowMemberMessages,
    bool? isPrivate,
    bool? requireJoinApproval,
    String? profilePhotoUrl,
    String? coverPhotoUrl,
    String? profilePhotoPath,
    String? coverPhotoPath,
    String? visibility,
    String? joinMode,
    String? status,
    String? groupType,
    int? maxMembers,
    String? welcomeMessage,
    String? guidelines,
    String? currentBook,
    int? currentChapter,
    DateTime? studyStartDate,
    DateTime? studyEndDate,
    String? meetingLocation,
    String? meetingLink,
    DateTime? updatedAt,
    DateTime? archivedAt,
    String? archivedBy,
    String? archiveReason,
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
      pendingMemberIds: pendingMemberIds ?? this.pendingMemberIds,
      schedule: schedule ?? this.schedule,
      churchId: churchId ?? this.churchId,
      createdAt: createdAt ?? this.createdAt,
      allowMemberMessages: allowMemberMessages ?? this.allowMemberMessages,
      isPrivate: isPrivate ?? this.isPrivate,
      requireJoinApproval: requireJoinApproval ?? this.requireJoinApproval,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
      profilePhotoPath: profilePhotoPath ?? this.profilePhotoPath,
      coverPhotoPath: coverPhotoPath ?? this.coverPhotoPath,
      visibility: visibility ?? this.visibility,
      joinMode: joinMode ?? this.joinMode,
      status: status ?? this.status,
      groupType: groupType ?? this.groupType,
      maxMembers: maxMembers ?? this.maxMembers,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      guidelines: guidelines ?? this.guidelines,
      currentBook: currentBook ?? this.currentBook,
      currentChapter: currentChapter ?? this.currentChapter,
      studyStartDate: studyStartDate ?? this.studyStartDate,
      studyEndDate: studyEndDate ?? this.studyEndDate,
      meetingLocation: meetingLocation ?? this.meetingLocation,
      meetingLink: meetingLink ?? this.meetingLink,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      archivedBy: archivedBy ?? this.archivedBy,
      archiveReason: archiveReason ?? this.archiveReason,
    );
  }

  static String _string(dynamic value) => value?.toString() ?? '';

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String && value.trim().isNotEmpty) {
      return int.tryParse(value);
    }
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
