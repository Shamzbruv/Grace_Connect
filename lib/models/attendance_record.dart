class AttendanceRecord {
  final String id;
  final String userId;
  final String churchId;
  final String serviceId;
  final DateTime timestamp;
  final String method; // 'manual', 'qr', 'auto_geofence'
  final bool present;
  final String status; // 'on_time', 'late', 'absent'
  final int? minutesLate;
  final String? reasonForAbsence; // For remote attendance
  final String? engagementAnswer; // For remote attendance engagement
  final String? serviceName; // Added for display
  final DateTime? serviceDate;
  final int minutesEarly;

  AttendanceRecord({
    required this.id,
    required this.userId,
    required this.churchId,
    required this.serviceId,
    required this.timestamp,
    required this.method,
    required this.present,
    required this.status,
    this.minutesLate,
    this.reasonForAbsence,
    this.engagementAnswer,
    this.serviceName,
    this.serviceDate,
    this.minutesEarly = 0,
  });

  factory AttendanceRecord.fromMap(Map<String, dynamic> data) {
    return AttendanceRecord(
      id: data['id']?.toString() ?? '',
      userId: data['user_id'] ?? '',
      churchId: data['church_id'] ?? '',
      serviceId: data['service_id'] ?? '',
      timestamp: data['timestamp'] != null
          ? DateTime.parse(data['timestamp']).toLocal()
          : DateTime.now(),
      method: data['method'] ?? 'unknown',
      present: data['present'] ?? false,
      status: data['status'] ?? 'unknown',
      minutesLate: data['minutes_late'],
      reasonForAbsence: data['reason_for_absence'],
      engagementAnswer: data['engagement_answer'],
      serviceName: data['service_name'],
      serviceDate: DateTime.tryParse(data['service_date']?.toString() ?? ''),
      minutesEarly: (data['minutes_early'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'church_id': churchId,
      'service_id': serviceId,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'method': method,
      'present': present,
      'status': status,
      'minutes_late': minutesLate,
      'reason_for_absence': reasonForAbsence,
      'engagement_answer': engagementAnswer,
      'service_name': serviceName,
      if (serviceDate != null)
        'service_date': '${serviceDate!.year.toString().padLeft(4, '0')}-'
            '${serviceDate!.month.toString().padLeft(2, '0')}-'
            '${serviceDate!.day.toString().padLeft(2, '0')}',
    };
  }

  bool get isRemote => method == 'remote';

  bool get isEarly => present && !isRemote && minutesEarly > 0;

  // Check-ins and finalization can happen on either side of midnight. The
  // scheduled service date remains the day the attendance belongs to.
  DateTime get attendanceDate {
    final date = serviceDate ?? timestamp;
    return DateTime(date.year, date.month, date.day);
  }
}

Map<DateTime, List<AttendanceRecord>> groupAttendanceByDay(
    Iterable<AttendanceRecord> records) {
  final grouped = <DateTime, List<AttendanceRecord>>{};
  for (final record in records) {
    grouped.putIfAbsent(record.attendanceDate, () => []).add(record);
  }
  return grouped;
}
