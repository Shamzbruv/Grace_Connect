

class PrayerTask {
  final String id;
  final String churchId;
  final String requestId; // Link to original prayer request
  final String assignedToUid;
  final String assignedToRole; // e.g. 'Prayer Warrior'
  final String assignedByUid;
  final String assignedByRole;
  final String status; // assigned, acknowledged, prayed, closed
  final DateTime assignedAt;
  final DateTime? acknowledgedAt;
  final DateTime? prayedAt;
  final DateTime? closedAt;
  final List<String> notes;
  final String requesterUid;
  final String priority;

  PrayerTask({
    required this.id,
    required this.churchId,
    required this.requestId,
    required this.assignedToUid,
    required this.assignedToRole,
    required this.assignedByUid,
    required this.assignedByRole,
    required this.status,
    required this.assignedAt,
    this.acknowledgedAt,
    this.prayedAt,
    this.closedAt,
    this.notes = const [],
    required this.requesterUid,
    this.priority = 'normal',
  });

  factory PrayerTask.fromMap(Map<String, dynamic> map, String id) {
    return PrayerTask(
      id: id,
      churchId: map['churchId'] ?? '',
      requestId: map['requestId'] ?? '',
      assignedToUid: map['assignedToUid'] ?? '',
      assignedToRole: map['assignedToRole'] ?? '',
      assignedByUid: map['assignedByUid'] ?? '',
      assignedByRole: map['assignedByRole'] ?? '',
      status: map['status'] ?? 'assigned',
      assignedAt: map['assignedAt'] != null ? DateTime.parse(map['assignedAt']).toLocal() : DateTime.now(),
      acknowledgedAt: map['acknowledgedAt'] != null
          ? DateTime.parse(map['acknowledgedAt']).toLocal()
          : null,
      prayedAt: map['prayedAt'] != null
          ? DateTime.parse(map['prayedAt']).toLocal()
          : null,
      closedAt: map['closedAt'] != null
          ? DateTime.parse(map['closedAt']).toLocal()
          : null,
      notes: List<String>.from(map['notes'] ?? []),
      requesterUid: map['requesterUid'] ?? '',
      priority: map['priority'] ?? 'normal',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'churchId': churchId,
      'requestId': requestId,
      'assignedToUid': assignedToUid,
      'assignedToRole': assignedToRole,
      'assignedByUid': assignedByUid,
      'assignedByRole': assignedByRole,
      'status': status,
      'assignedAt': assignedAt.toIso8601String(),
      'acknowledgedAt': acknowledgedAt?.toIso8601String(),
      'prayedAt': prayedAt?.toIso8601String(),
      'closedAt': closedAt?.toIso8601String(),
      'notes': notes,
      'requesterUid': requesterUid,
      'priority': priority,
    };
  }
}
