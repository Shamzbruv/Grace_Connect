class Announcement {
  final String id;
  final String churchId;
  final String authorId;
  final String authorName;
  final String title;
  final String body;
  final String priority;
  final String? ministryId;
  final String ministryName;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? scheduledAt;
  final String? linkUrl;
  final String? locationName;
  final String? locationAddress;
  final double? locationLatitude;
  final double? locationLongitude;
  final String? googlePlaceId;

  const Announcement({
    required this.id,
    required this.churchId,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.body,
    required this.priority,
    this.ministryId,
    this.ministryName = '',
    required this.createdAt,
    this.expiresAt,
    this.scheduledAt,
    this.linkUrl,
    this.locationName,
    this.locationAddress,
    this.locationLatitude,
    this.locationLongitude,
    this.googlePlaceId,
  });

  factory Announcement.fromMap(Map<String, dynamic> data) {
    return Announcement(
      id: data['id']?.toString() ?? '',
      churchId: data['church_id']?.toString() ?? '',
      authorId: data['author_id']?.toString() ?? '',
      authorName: data['author_name']?.toString() ?? 'Grace Connect',
      title: data['title']?.toString() ?? 'Announcement',
      body: data['body']?.toString() ?? '',
      priority: data['priority']?.toString() ?? 'normal',
      ministryId: data['ministry_id']?.toString(),
      ministryName: data['ministry_name']?.toString() ?? '',
      createdAt: DateTime.tryParse(data['created_at']?.toString() ?? '') ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(data['expires_at']?.toString() ?? ''),
      scheduledAt: DateTime.tryParse(data['scheduled_at']?.toString() ?? ''),
      linkUrl: data['link_url']?.toString(),
      locationName: data['location_name']?.toString(),
      locationAddress: data['location_address']?.toString(),
      locationLatitude: (data['location_latitude'] as num?)?.toDouble(),
      locationLongitude: (data['location_longitude'] as num?)?.toDouble(),
      googlePlaceId: data['google_place_id']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    final data = <String, dynamic>{
      'church_id': churchId,
      'author_id': authorId,
      'author_name': authorName,
      'title': title,
      'body': body,
      'priority': priority,
      'ministry_id': ministryId,
      'ministry_name': ministryName,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
      'link_url': linkUrl,
      'location_name': locationName,
      'location_address': locationAddress,
      'location_latitude': locationLatitude,
      'location_longitude': locationLongitude,
      'google_place_id': googlePlaceId,
    };

    if (id.isNotEmpty) {
      data['id'] = id;
    }

    return data;
  }
}
