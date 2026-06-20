class EventModel {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String time;
  final String location;
  final String churchId;
  final String organizerId;
  final String sourceLabel;
  final String? ministryId;
  final String ministryName;
  final bool visibleToAllChurches;
  final DateTime createdAt;
  final List<String> attendees;

  EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    this.location = '',
    required this.churchId,
    required this.organizerId,
    this.sourceLabel = 'Church Event',
    this.ministryId,
    this.ministryName = '',
    this.visibleToAllChurches = false,
    DateTime? createdAt,
    this.attendees = const [],
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'time': time,
      'location': location,
      'churchId': churchId,
      'organizerId': organizerId,
      'sourceLabel': sourceLabel,
      'ministry_id': ministryId,
      'ministry_name': ministryName,
      'visible_to_all_churches': visibleToAllChurches,
      'createdAt': createdAt.toIso8601String(),
      'attendees': attendees,
    };
  }

  factory EventModel.fromMap(Map<String, dynamic> data) {
    return EventModel(
      id: data['id'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      date:
          data['date'] != null ? DateTime.parse(data['date']) : DateTime.now(),
      time: data['time'] ?? '',
      location: data['location'] ?? '',
      churchId: data['churchId'] ?? '',
      organizerId: data['organizerId'] ?? '',
      sourceLabel: data['sourceLabel'] ?? 'Church Event',
      ministryId: data['ministry_id']?.toString(),
      ministryName: data['ministry_name']?.toString() ?? '',
      visibleToAllChurches: data['visible_to_all_churches'] == true ||
          data['visibleToAllChurches'] == true,
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'])
          : DateTime.now(),
      attendees: List<String>.from(data['attendees'] ?? []),
    );
  }
}

class EventRsvpDetail {
  const EventRsvpDetail({
    required this.userId,
    required this.fullName,
    required this.email,
    required this.churchId,
    required this.churchName,
    required this.isOtherChurch,
  });

  final String userId;
  final String fullName;
  final String email;
  final String churchId;
  final String churchName;
  final bool isOtherChurch;

  factory EventRsvpDetail.fromMap(Map<String, dynamic> data) {
    return EventRsvpDetail(
      userId: data['user_id']?.toString() ?? '',
      fullName: data['full_name']?.toString() ?? 'Member',
      email: data['email']?.toString() ?? '',
      churchId: data['church_id']?.toString() ?? '',
      churchName: data['church_name']?.toString() ?? '',
      isOtherChurch: data['is_other_church'] == true,
    );
  }
}
