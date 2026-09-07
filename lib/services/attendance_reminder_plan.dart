import '../models/service_schedule.dart';

class AttendanceReminderPlan {
  const AttendanceReminderPlan({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;

  /// Stable across processes, unlike an object identity or a timestamp ID.
  static int notificationId(String userId, String serviceId, int phase) {
    var hash = 2166136261;
    for (final unit in 'attendance|$userId|$serviceId|$phase'.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  static List<AttendanceReminderPlan> upcoming({
    required DateTime now,
    required String userId,
    required Iterable<ServiceSchedule> schedules,
    Set<String> confirmedOccurrences = const {},
  }) {
    final utc = now.toUtc();
    final jamaica = utc.subtract(const Duration(hours: 5));
    final day = DateTime.utc(jamaica.year, jamaica.month, jamaica.day, 5);
    final plans = <int, AttendanceReminderPlan>{};
    for (var offset = 0; offset <= 15; offset++) {
      final date = day.add(Duration(days: offset));
      final dateKey = '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      for (final schedule in schedules) {
        if (!schedule.attendanceEnabled ||
            schedule.dayOfWeek != date.weekday ||
            confirmedOccurrences.contains('${schedule.serviceId}|$dateKey')) {
          continue;
        }
        final parts = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?$')
            .firstMatch(schedule.startTime.trim());
        final endParts = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?$')
            .firstMatch(schedule.endTime.trim());
        if (parts == null || endParts == null) continue;
        final start = date.add(Duration(
            hours: int.parse(parts[1]!), minutes: int.parse(parts[2]!)));
        var end = date.add(Duration(
            hours: int.parse(endParts[1]!), minutes: int.parse(endParts[2]!)));
        if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
        final lead = schedule.checkInOpensMinutesBefore.clamp(0, 15).toInt();
        final phases = <int, DateTime>{
          if (lead > 0) 0: start.subtract(Duration(minutes: lead)),
          1: start,
          if (start.add(const Duration(minutes: 10)).isBefore(end))
            2: start.add(const Duration(minutes: 10)),
        };
        final name = schedule.name.isEmpty ? 'Church service' : schedule.name;
        for (final phase in phases.entries) {
          if (!phase.value.isAfter(utc.add(const Duration(seconds: 5)))) {
            continue;
          }
          final id = notificationId(
              userId, '${schedule.serviceId}|$dateKey', phase.key);
          plans.putIfAbsent(
              id,
              () => AttendanceReminderPlan(
                    id: id,
                    at: phase.value,
                    title: phase.key == 0
                        ? '$name starts soon'
                        : '$name is underway',
                    body: phase.key == 0
                        ? 'At church already? Tap to sign in early without waiting for automatic check-in.'
                        : 'Attendance not confirmed yet? Tap to sign in at church. Your verified arrival time will be recorded.',
                  ));
        }
      }
    }
    final sorted = plans.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    return sorted.take(24).toList();
  }
}
