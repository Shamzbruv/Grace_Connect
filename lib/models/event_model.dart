class EventModel {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String time;
  final String location;
  final String? eventUrl;
  final int durationMinutes;
  final String churchId;
  final String organizerId;
  final String sourceLabel;
  final String? ministryId;
  final String ministryName;
  final bool visibleToAllChurches;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> attendees;

  EventModel({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    this.location = '',
    this.eventUrl,
    this.durationMinutes = 60,
    required this.churchId,
    required this.organizerId,
    this.sourceLabel = 'Church Event',
    this.ministryId,
    this.ministryName = '',
    this.visibleToAllChurches = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.attendees = const [],
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  DateTime get endDate => date.add(Duration(minutes: durationMinutes));

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'time': time,
      'location': location,
      'event_url': eventUrl,
      'duration_minutes': durationMinutes,
      'churchId': churchId,
      'organizerId': organizerId,
      'sourceLabel': sourceLabel,
      'ministry_id': ministryId,
      'ministry_name': ministryName,
      'visible_to_all_churches': visibleToAllChurches,
      'createdAt': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
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
      eventUrl: _optionalString(data['event_url'] ?? data['eventUrl']),
      durationMinutes: _safeDuration(data['duration_minutes']),
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
      updatedAt: data['updated_at'] != null
          ? DateTime.parse(data['updated_at'])
          : data['createdAt'] != null
              ? DateTime.parse(data['createdAt'])
              : DateTime.now(),
      attendees: List<String>.from(data['attendees'] ?? []),
    );
  }

  static String? _optionalString(dynamic value) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static int _safeDuration(dynamic value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null || parsed < 15 || parsed > 1440) return 60;
    return parsed;
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
