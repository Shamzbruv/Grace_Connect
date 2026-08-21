import 'package:supabase_flutter/supabase_flutter.dart';

/// One finalized service's attendance breakdown, as recorded by the
/// server-side closeout (attendance_finalized_services). Pre-aggregated on
/// the backend -- this is a display model, not a place to recompute counts.
class ServiceAttendanceSummary {
  const ServiceAttendanceSummary({
    required this.serviceId,
    required this.serviceName,
    required this.serviceDate,
    required this.presentCount,
    required this.lateCount,
    required this.remoteCount,
    required this.absentCount,
  });

  factory ServiceAttendanceSummary.fromMap(Map<String, dynamic> map) {
    return ServiceAttendanceSummary(
      serviceId: map['service_id']?.toString() ?? '',
      serviceName: map['service_name']?.toString() ?? 'Service',
      serviceDate:
          DateTime.tryParse(map['service_date']?.toString() ?? '') ??
              DateTime.now(),
      presentCount: (map['present_count'] as num?)?.toInt() ?? 0,
      lateCount: (map['late_count'] as num?)?.toInt() ?? 0,
      remoteCount: (map['remote_count'] as num?)?.toInt() ?? 0,
      absentCount: (map['absent_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String serviceId;
  final String serviceName;
  final DateTime serviceDate;
  final int presentCount;
  final int lateCount;
  final int remoteCount;
  final int absentCount;

  int get attendedCount => presentCount + lateCount + remoteCount;
  int get expectedCount => attendedCount + absentCount;

  /// 0-100. Null when nobody was expected (avoids a misleading 0% or
  /// divide-by-zero on a service with no roster yet).
  double? get attendanceRate =>
      expectedCount == 0 ? null : (attendedCount / expectedCount) * 100;
}

class AttendanceAnalyticsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Most recent [limit] finalized services for a church, oldest first (the
  /// natural reading order for a trend chart).
  Future<List<ServiceAttendanceSummary>> recentServiceSummaries(
    String churchId, {
    int limit = 12,
  }) async {
    final rows = await _supabase
        .from('attendance_finalized_services')
        .select()
        .eq('church_id', churchId)
        .order('service_date', ascending: false)
        .limit(limit);

    return rows
        .map<ServiceAttendanceSummary>(ServiceAttendanceSummary.fromMap)
        .toList()
        .reversed
        .toList(growable: false);
  }
}
