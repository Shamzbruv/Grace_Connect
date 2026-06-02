

class VolunteerNeed {
  final String id;
  final String churchId;
  final String title;
  final String description;
  final String ministry;
  final DateTime date;
  final int slotsNeeded;
  final List<String> slotsFilled; // List of userIds who signed up
  final String createdBy;
  final String status; // 'open', 'closed'
  final DateTime createdAt;

  VolunteerNeed({
    required this.id,
    required this.churchId,
    required this.title,
    required this.description,
    this.ministry = 'General',
    required this.date,
    required this.slotsNeeded,
    this.slotsFilled = const [],
    required this.createdBy,
    this.status = 'open',
    required this.createdAt,
  });

  factory VolunteerNeed.fromMap(Map<String, dynamic> data) {
    return VolunteerNeed(
      id: data['id'] ?? '',
      churchId: data['churchId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      ministry: data['ministry'] ?? 'General',
      date: data['date'] != null ? DateTime.parse(data['date']) : DateTime.now(),
      slotsNeeded: data['slotsNeeded'] ?? 1,
      slotsFilled: List<String>.from(data['slotsFilled'] ?? []),
      createdBy: data['createdBy'] ?? '',
      status: data['status'] ?? 'open',
      createdAt: data['createdAt'] != null ? DateTime.parse(data['createdAt']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'churchId': churchId,
      'title': title,
      'description': description,
      'ministry': ministry,
      'date': date.toIso8601String(),
      'slotsNeeded': slotsNeeded,
      'slotsFilled': slotsFilled,
      'createdBy': createdBy,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
