class ChurchLocation {
  final String churchId;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String? placeId;
  final String timezone;

  const ChurchLocation({
    required this.churchId,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 100.0,
    this.placeId,
    this.timezone = 'UTC',
  });

  factory ChurchLocation.fromMap(Map<String, dynamic> data) {
    return ChurchLocation(
      churchId: data['churchId'] ?? '',
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      radiusMeters: (data['radiusMeters'] ?? 100.0).toDouble(),
      placeId: data['placeId'],
      timezone: data['timezone'] ?? 'UTC',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'churchId': churchId,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'placeId': placeId,
      'timezone': timezone,
    };
  }
}
