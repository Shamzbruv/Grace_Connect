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
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'])
          : DateTime.now(),
      attendees: List<String>.from(data['attendees'] ?? []),
    );
  }
}
