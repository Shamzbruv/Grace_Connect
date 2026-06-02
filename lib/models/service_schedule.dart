class ServiceSchedule {
  final String serviceId;
  final String churchId;
  final String name;
  final int dayOfWeek; // 1 = Monday, 7 = Sunday (following DateTime.weekday)
  final String startTime; // HH:MM 24h format
  final String endTime; // HH:MM 24h format
  final String recurrence; // weekly for now; stored for future expansion
  final bool attendanceEnabled;
  final int checkInOpensMinutesBefore;
  final int checkInClosesMinutesAfter;
  final int minimumDwellMinutes;

  const ServiceSchedule({
    required this.serviceId,
    required this.churchId,
    required this.name,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.recurrence = 'weekly',
    this.attendanceEnabled = true,
    this.checkInOpensMinutesBefore = 30,
    this.checkInClosesMinutesAfter = 30,
    this.minimumDwellMinutes = 10,
  });

  factory ServiceSchedule.fromMap(Map<String, dynamic> data) {
    return ServiceSchedule(
      serviceId: data['serviceId'] ?? '',
      churchId: data['churchId'] ?? '',
      name: data['name'] ?? '',
      dayOfWeek: data['dayOfWeek'] ?? 7,
      startTime: data['startTime'] ?? '09:00',
      endTime: data['endTime'] ?? '11:00',
      recurrence: data['recurrence'] ?? 'weekly',
      attendanceEnabled: data['attendanceEnabled'] ?? true,
      checkInOpensMinutesBefore:
          _parseInt(data['checkInOpensMinutesBefore'], 30),
      checkInClosesMinutesAfter:
          _parseInt(data['checkInClosesMinutesAfter'], 30),
      minimumDwellMinutes: _parseInt(data['minimumDwellMinutes'], 10),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'serviceId': serviceId,
      'churchId': churchId,
      'name': name,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
      'recurrence': recurrence,
      'attendanceEnabled': attendanceEnabled,
      'checkInOpensMinutesBefore': checkInOpensMinutesBefore,
      'checkInClosesMinutesAfter': checkInClosesMinutesAfter,
      'minimumDwellMinutes': minimumDwellMinutes,
    };
  }

  static int _parseInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}
