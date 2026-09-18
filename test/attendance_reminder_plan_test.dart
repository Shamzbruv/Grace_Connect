import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/service_schedule.dart';
import 'package:grace_connect/services/attendance_reminder_plan.dart';

void main() {
  const school = ServiceSchedule(
      serviceId: 'school',
      churchId: 'church',
      name: 'Sunday School',
      dayOfWeek: 7,
      startTime: '08:30',
      endTime: '10:00');
  test('reminds before, at start and while service is underway', () {
    final plan = AttendanceReminderPlan.upcoming(
        now: DateTime.parse('2026-09-06T07:00:00-05:00'),
        userId: 'member',
        timeZone: 'America/Jamaica',
        schedules: [school]);
    expect(plan.take(3).map((p) => p.at), [
      DateTime.parse('2026-09-06T08:15:00-05:00'),
      DateTime.parse('2026-09-06T08:30:00-05:00'),
      DateTime.parse('2026-09-06T08:40:00-05:00'),
    ]);
  });
  test('confirmed attendance advances all remaining prompts to next week', () {
    final plan = AttendanceReminderPlan.upcoming(
        now: DateTime.parse('2026-09-06T08:20:00-05:00'),
        userId: 'member',
        timeZone: 'America/Jamaica',
        schedules: [school],
        confirmedOccurrences: {'school|2026-09-06'});
    expect(plan, hasLength(6));
    expect(plan.every((p) => p.at.day == 13 || p.at.day == 20), isTrue);
  });
  test('opening during a service retains the upcoming fallback prompt', () {
    final plan = AttendanceReminderPlan.upcoming(
        now: DateTime.parse('2026-09-06T08:35:00-05:00'),
        userId: 'member',
        timeZone: 'America/Jamaica',
        schedules: [school]);
    expect(plan.first.at, DateTime.parse('2026-09-06T08:40:00-05:00'));
    expect(plan.first.title, contains('underway'));
  });
  test('no early reminder when the church opens check-in only at start', () {
    const service = ServiceSchedule(
        serviceId: 'service',
        churchId: 'church',
        name: 'Service',
        dayOfWeek: 7,
        startTime: '08:30',
        endTime: '10:00',
        checkInOpensMinutesBefore: 0);
    final plan = AttendanceReminderPlan.upcoming(
        now: DateTime.parse('2026-09-06T07:00:00-05:00'),
        userId: 'member',
        timeZone: 'America/Jamaica',
        schedules: [service]);
    expect(plan, hasLength(6));
    expect(plan.first.at, DateTime.parse('2026-09-06T08:30:00-05:00'));
  });
  test('a short service receives no prompt after it has ended', () {
    const service = ServiceSchedule(
        serviceId: 'short',
        churchId: 'church',
        name: 'Service',
        dayOfWeek: 7,
        startTime: '08:30',
        endTime: '08:35');
    final plan = AttendanceReminderPlan.upcoming(
        now: DateTime.parse('2026-09-06T07:00:00-05:00'),
        userId: 'member',
        timeZone: 'America/Jamaica',
        schedules: [service]);
    expect(plan, hasLength(6));
  });
  test('early reminder can fall on the day before a midnight service', () {
    const service = ServiceSchedule(
        serviceId: 'night',
        churchId: 'church',
        name: 'Service',
        dayOfWeek: 7,
        startTime: '00:05',
        endTime: '01:00');
    final plan = AttendanceReminderPlan.upcoming(
        now: DateTime.parse('2026-09-05T23:40:00-05:00'),
        userId: 'member',
        timeZone: 'America/Jamaica',
        schedules: [service]);
    expect(plan.first.at, DateTime.parse('2026-09-05T23:50:00-05:00'));
  });
  test('later weeks use independent IDs so rescheduling cannot revive today',
      () {
    final plan = AttendanceReminderPlan.upcoming(
        now: DateTime.parse('2026-09-06T07:00:00-05:00'),
        userId: 'member',
        timeZone: 'America/Jamaica',
        schedules: [school]);
    expect(plan, hasLength(9));
    expect(plan.map((p) => p.id).toSet(), hasLength(9));
  });
  test('notification identity is stable and separated by member and phase', () {
    expect(AttendanceReminderPlan.notificationId('a', 's', 0),
        AttendanceReminderPlan.notificationId('a', 's', 0));
    expect(AttendanceReminderPlan.notificationId('a', 's', 0),
        isNot(AttendanceReminderPlan.notificationId('b', 's', 0)));
    expect(AttendanceReminderPlan.notificationId('a', 's', 0),
        isNot(AttendanceReminderPlan.notificationId('a', 's', 1)));
  });
}
