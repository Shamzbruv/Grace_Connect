import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/attendance_record.dart';

AttendanceRecord _record({
  required String serviceId,
  required String timestamp,
  String? serviceDate,
  bool present = true,
  String method = 'manual_geofence',
  int? minutesEarly,
}) =>
    AttendanceRecord.fromMap({
      'id': serviceId,
      'service_id': serviceId,
      'timestamp': timestamp,
      'service_date': serviceDate,
      'present': present,
      'method': method,
      'status': present ? 'on_time' : 'absent',
      if (minutesEarly != null) 'minutes_early': minutesEarly,
    });

void main() {
  test('a day retains attendance for every service in either history order',
      () {
    final school = _record(
      serviceId: 'sunday-school',
      timestamp: '2026-09-06T08:15:00-05:00',
      serviceDate: '2026-09-06',
    );
    final service = _record(
      serviceId: 'sunday-service',
      timestamp: '2026-09-06T13:30:00-05:00',
      serviceDate: '2026-09-06',
      present: false,
    );

    for (final records in [
      [school, service],
      [service, school],
    ]) {
      final day = groupAttendanceByDay(records)[DateTime(2026, 9, 6)]!;
      expect(day.map((record) => record.serviceId),
          unorderedEquals(['sunday-school', 'sunday-service']));
      expect(day.where((record) => record.present), hasLength(1));
      expect(day.where((record) => !record.present), hasLength(1));
    }
  });

  test('an after-midnight check-in belongs to its scheduled service date', () {
    final record = _record(
      serviceId: 'night-service',
      timestamp: '2026-09-07T00:05:00-05:00',
      serviceDate: '2026-09-06',
    );

    expect(record.attendanceDate, DateTime(2026, 9, 6));
    expect(record.toMap()['service_date'], '2026-09-06');
    expect(groupAttendanceByDay([record]).keys, [DateTime(2026, 9, 6)]);
  });

  test(
      'legacy attendance uses its local check-in day when service date is absent',
      () {
    final record = _record(
      serviceId: 'legacy-service',
      timestamp: '2026-09-06T13:00:00Z',
    );
    final local = record.timestamp;
    expect(record.attendanceDate, DateTime(local.year, local.month, local.day));
    expect(record.toMap().containsKey('service_date'), isFalse);
    expect(record.isEarly, isFalse);
  });

  test('early label uses verified server metadata and keeps on-time analytics',
      () {
    final early = _record(
      serviceId: 'sunday-school',
      timestamp: '2026-09-06T08:15:00-05:00',
      minutesEarly: 15,
    );
    expect(early.isEarly, isTrue);
    expect(early.status, 'on_time');
    expect(early.minutesEarly, 15);
    expect(early.toMap().containsKey('minutes_early'), isFalse,
        reason: 'the server computes early credit; clients cannot submit it');

    final absent = _record(
      serviceId: 'sunday-school',
      timestamp: '2026-09-06T08:15:00-05:00',
      present: false,
      minutesEarly: 15,
    );
    final remote = _record(
      serviceId: 'sunday-school',
      timestamp: '2026-09-06T08:15:00-05:00',
      method: 'remote',
      minutesEarly: 15,
    );
    expect(absent.isEarly, isFalse);
    expect(remote.isEarly, isFalse);
  });
}
