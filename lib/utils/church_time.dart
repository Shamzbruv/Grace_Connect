import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Converts instants using the church's IANA zone, independently of the phone.
/// Calendar construction (rather than adding 24 hours) also handles DST.
class ChurchTime {
  ChurchTime(String name) {
    if (!_initialized) {
      tzdata.initializeTimeZones();
      _initialized = true;
    }
    location = tz.getLocation(name.trim().isEmpty ? 'UTC' : name.trim());
  }

  static bool _initialized = false;
  late final tz.Location location;
  String get name => location.name;

  tz.TZDateTime local(DateTime instant) =>
      tz.TZDateTime.from(instant, location);

  DateTime at(DateTime date, int hour, [int minute = 0, int second = 0]) =>
      DateTime.fromMicrosecondsSinceEpoch(
        tz.TZDateTime(
          location, date.year, date.month, date.day, hour, minute, second,
        ).microsecondsSinceEpoch,
        isUtc: true,
      );

  DateTime startOfDay(DateTime instant) => at(local(instant), 0);

  String dateKey(DateTime instant) {
    final date = local(instant);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
