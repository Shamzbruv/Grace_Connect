class Church {
  final String id;
  final String name;
  final String placeId;
  final String address;
  final String denomination;
  final String ownerUserId;
  final String timezone;
  final String status; // active, pending
  final DateTime createdAt;
  final String? parish;
  final double? latitude;
  final double? longitude;
  final Map<String, dynamic> policies; // Added policies for RBAC
  final String? liveStreamUrl;
  final bool isLive;
  final String about;
  final int? foundedYear;
  final String contactEmail;
  final String contactPhone;
  final String websiteUrl;
  final String serviceTimesNote;

  Church({
    required this.id,
    required this.name,
    required this.placeId,
    required this.address,
    required this.denomination,
    required this.ownerUserId,
    required this.timezone,
    required this.status,
    required this.createdAt,
    this.parish,
    this.latitude,
    this.longitude,
    this.policies = const {},
    this.liveStreamUrl,
    this.isLive = false,
    this.about = '',
    this.foundedYear,
    this.contactEmail = '',
    this.contactPhone = '',
    this.websiteUrl = '',
    this.serviceTimesNote = '',
  });

  factory Church.fromMap(Map<String, dynamic> data) {
    return Church(
      id: data['id'] ?? '',
      name: data['name'] ?? '',
      placeId: data['placeId'] ?? '',
      address: data['address'] ?? '',
      denomination: data['denomination'] ?? '',
      ownerUserId: data['ownerUserId']?.toString() ??
          data['owner_user_id']?.toString() ??
          '',
      timezone: data['timezone'] ?? 'UTC',
      status: data['status'] ?? 'pending',
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'])
          : DateTime.now(),
      parish: data['parish'],
      latitude: data['latitude']?.toDouble(),
      longitude: data['longitude']?.toDouble(),
      policies: Map<String, dynamic>.from(data['policies'] ?? {}),
      liveStreamUrl: data['liveStreamUrl'],
      isLive: data['isLive'] ?? false,
      about: data['about'] ?? '',
      foundedYear: data['founded_year'] is int
          ? data['founded_year'] as int
          : data['foundedYear'] is int
              ? data['foundedYear'] as int
              : int.tryParse(
                  (data['founded_year'] ?? data['foundedYear'] ?? '')
                      .toString(),
                ),
      contactEmail: data['contact_email'] ?? data['contactEmail'] ?? '',
      contactPhone: data['contact_phone'] ?? data['contactPhone'] ?? '',
      websiteUrl: data['website_url'] ?? data['websiteUrl'] ?? '',
      serviceTimesNote:
          data['service_times_note'] ?? data['serviceTimesNote'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'placeId': placeId,
      'address': address,
      'denomination': denomination,
      'ownerUserId': ownerUserId,
      'timezone': timezone,
      'id': id,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'parish': parish,
      'latitude': latitude,
      'longitude': longitude,
      'policies': policies,
      'liveStreamUrl': liveStreamUrl,
      'isLive': isLive,
      'about': about,
      'founded_year': foundedYear,
      'contact_email': contactEmail,
      'contact_phone': contactPhone,
      'website_url': websiteUrl,
      'service_times_note': serviceTimesNote,
    };
  }
}
