import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/utils/church_time.dart';
import 'package:grace_connect/models/attendance_record.dart';
import 'package:grace_connect/models/service_schedule.dart';
import 'package:grace_connect/services/attendance_reminder_plan.dart';

void main() {
  test('screenshot arrival and schedule are different instants in church time', () {
    final record = AttendanceRecord.fromMap({
      'timestamp': '2026-09-13T13:51:09Z',
      'service_timezone': 'America/Jamaica',
      'scheduled_start_at': '2026-09-13T13:30:00Z',
      'confirmed_at': '2026-09-13T14:14:59Z',
      'service_date': '2026-09-13', 'present': true,
      'status': 'late', 'minutes_late': 21,
    });
    expect(record.displayTimestamp.hour, 8);
    expect(record.displayTimestamp.minute, 51);
    expect(record.displayScheduledStart!.hour, 8);
    expect(record.displayScheduledStart!.minute, 30);
    expect(record.displayConfirmedAt!.hour, 9);
    expect(record.displayConfirmedAt!.minute, 14);
    expect(record.minutesLate, 21);
  });
  test('same service wall clock follows New York daylight saving changes', () {
    final clock = ChurchTime('America/New_York');
    expect(clock.at(DateTime.utc(2026, 3, 1), 9), DateTime.utc(2026, 3, 1, 14));
    expect(clock.at(DateTime.utc(2026, 3, 8), 9), DateTime.utc(2026, 3, 8, 13));
    expect(clock.at(DateTime.utc(2026, 11, 1), 9), DateTime.utc(2026, 11, 1, 14));
  });
  test('fractional offsets and date-line dates do not follow the device clock', () {
    final instant = DateTime.utc(2026, 9, 13, 11);
    expect(ChurchTime('Asia/Kolkata').local(instant).minute, 30);
    expect(ChurchTime('Pacific/Kiritimati').dateKey(instant), '2026-09-14');
    expect(ChurchTime('America/Jamaica').dateKey(instant), '2026-09-13');
  });
  test('reminders preserve local service start across a DST weekend', () {
    const service = ServiceSchedule(serviceId: 's', churchId: 'c', name: 'Service',
      dayOfWeek: 7, startTime: '09:00', endTime: '11:00');
    final plans = AttendanceReminderPlan.upcoming(now: DateTime.utc(2026, 3, 1, 12),
      userId: 'u', schedules: [service], timeZone: 'America/New_York');
    expect(plans.map((p) => p.at), contains(DateTime.utc(2026, 3, 1, 14)));
    expect(plans.map((p) => p.at), contains(DateTime.utc(2026, 3, 8, 13)));
    expect(plans.map((p) => p.at), isNot(contains(DateTime.utc(2026, 3, 8, 14))));
  });
  test('confirmed first service never suppresses second-service reminders', () {
    const school = ServiceSchedule(serviceId: 'school', churchId: 'c', name: 'School',
      dayOfWeek: 7, startTime: '08:30', endTime: '09:40');
    const main = ServiceSchedule(serviceId: 'main', churchId: 'c', name: 'Main',
      dayOfWeek: 7, startTime: '09:50', endTime: '13:00');
    final plans = AttendanceReminderPlan.upcoming(now: DateTime.utc(2026, 9, 13, 14, 20),
      userId: 'u', schedules: [school, main], timeZone: 'America/Jamaica',
      confirmedOccurrences: {'school|2026-09-13'});
    expect(plans.first.title, 'Main starts soon');
    expect(plans.first.at, DateTime.utc(2026, 9, 13, 14, 35));
  });
}
