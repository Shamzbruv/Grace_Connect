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
    };
  }

  bool get isRemote => method == 'remote';
}
