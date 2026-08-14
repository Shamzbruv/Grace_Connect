import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/event_model.dart';

enum EventCalendarSyncStatus {
  created,
  updated,
  unchanged,
  permissionDenied,
  unavailable,
}

class EventCalendarService {
  EventCalendarService({DeviceCalendar? calendar})
      : _calendar = calendar ?? DeviceCalendar.instance;

  final DeviceCalendar _calendar;

  static String _eventIdKey(String userId, String eventId) =>
      'event_calendar_native_id_v1_${userId.trim()}_${eventId.trim()}';

  static String _versionKey(String userId, String eventId) =>
      'event_calendar_version_v1_${userId.trim()}_${eventId.trim()}';

  static String _reminderKey(String userId, String eventId) =>
      'event_calendar_reminder_v1_${userId.trim()}_${eventId.trim()}';

  Future<bool> hasCalendarCopy(String userId, String eventId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_eventIdKey(userId, eventId))?.isNotEmpty == true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the reminder previously chosen for this event, or [fallback]
  /// when the user has not synced it yet. Keeping this preference prevents a
  /// later manual refresh from silently changing a two-hour reminder to one
  /// day.
  Future<int> savedReminderMinutes(
    String userId,
    String eventId, {
    int fallback = 1440,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_reminderKey(userId, eventId)) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  /// Requests access only after the screen has shown Grace Connect's own
  /// explanation. Full access is needed to keep a previously-added entry in
  /// sync when an organizer edits the event.
  Future<CalendarPermissionStatus> requestSyncPermission() {
    return _calendar.requestPermissions(level: CalendarAccessLevel.full);
  }

  Future<EventCalendarSyncStatus> sync(
    EventModel event, {
    required String userId,
    required int reminderMinutes,
    bool requestPermission = true,
  }) async {
    try {
      final permission = requestPermission
          ? await requestSyncPermission()
          : await _calendar.hasPermissions();
      if (permission != CalendarPermissionStatus.granted) {
        return EventCalendarSyncStatus.permissionDenied;
      }

      final prefs = await SharedPreferences.getInstance();
      final idKey = _eventIdKey(userId, event.id);
      final versionKey = _versionKey(userId, event.id);
      final nativeId = prefs.getString(idKey)?.trim();
      final version = _calendarVersion(event, reminderMinutes);

      if (nativeId?.isNotEmpty == true &&
          prefs.getString(versionKey) == version) {
        return EventCalendarSyncStatus.unchanged;
      }

      final start = event.date.toLocal();
      final end = event.endDate.toLocal();
      final description = _calendarDescription(event);
      final link = event.eventUrl?.trim();
      final reminders = <Duration>[Duration(minutes: reminderMinutes)];

      if (nativeId?.isNotEmpty == true) {
        try {
          await _calendar.updateEvent(
            eventId: nativeId!,
            title: event.title,
            startDate: start,
            endDate: end,
            description: Patch.set(description),
            location: event.location.trim().isEmpty
                ? const Patch.clear()
                : Patch.set(event.location.trim()),
            url: link == null || link.isEmpty
                ? const Patch.clear()
                : Patch.set(link),
            reminders: Patch.set(reminders),
          );
          await prefs.setString(versionKey, version);
          await prefs.setInt(
            _reminderKey(userId, event.id),
            reminderMinutes,
          );
          return EventCalendarSyncStatus.updated;
        } on DeviceCalendarException catch (error) {
          if (error.errorCode != DeviceCalendarError.notFound) rethrow;
          await prefs.remove(idKey);
          await prefs.remove(versionKey);
        }
      }

      final createdId = await _calendar.createEvent(
        title: event.title,
        startDate: start,
        endDate: end,
        description: description,
        location: event.location.trim().isEmpty ? null : event.location.trim(),
        url: link == null || link.isEmpty ? null : link,
        reminders: reminders,
      );
      await prefs.setString(idKey, createdId);
      await prefs.setString(versionKey, version);
      await prefs.setInt(_reminderKey(userId, event.id), reminderMinutes);
      return EventCalendarSyncStatus.created;
    } on DeviceCalendarException catch (error) {
      if (error.errorCode == DeviceCalendarError.permissionDenied ||
          error.errorCode == DeviceCalendarError.permissionsNotDeclared) {
        return EventCalendarSyncStatus.permissionDenied;
      }
      return EventCalendarSyncStatus.unavailable;
    } catch (_) {
      return EventCalendarSyncStatus.unavailable;
    }
  }

  Future<EventCalendarSyncStatus> remove(
    String eventId, {
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final idKey = _eventIdKey(userId, eventId);
    final versionKey = _versionKey(userId, eventId);
    final reminderKey = _reminderKey(userId, eventId);
    final nativeId = prefs.getString(idKey)?.trim();
    if (nativeId == null || nativeId.isEmpty) {
      return EventCalendarSyncStatus.unchanged;
    }

    try {
      final permission = await _calendar.hasPermissions();
      if (permission != CalendarPermissionStatus.granted) {
        return EventCalendarSyncStatus.permissionDenied;
      }
      await _calendar.deleteEvent(eventId: nativeId);
    } on DeviceCalendarException catch (error) {
      if (error.errorCode != DeviceCalendarError.notFound) {
        return error.errorCode == DeviceCalendarError.permissionDenied
            ? EventCalendarSyncStatus.permissionDenied
            : EventCalendarSyncStatus.unavailable;
      }
    } catch (_) {
      return EventCalendarSyncStatus.unavailable;
    }

    await prefs.remove(idKey);
    await prefs.remove(versionKey);
    await prefs.remove(reminderKey);
    return EventCalendarSyncStatus.updated;
  }

  Future<void> syncOutdated(
    Iterable<EventModel> events, {
    required String userId,
  }) async {
    try {
      final permission = await _calendar.hasPermissions();
      if (permission != CalendarPermissionStatus.granted) return;
      final prefs = await SharedPreferences.getInstance();

      for (final event in events) {
        if (!await hasCalendarCopy(userId, event.id)) continue;
        final reminderMinutes =
            prefs.getInt(_reminderKey(userId, event.id)) ?? 1440;
        await sync(
          event,
          userId: userId,
          reminderMinutes: reminderMinutes,
          requestPermission: false,
        );
      }
    } catch (_) {
      // Background maintenance never prompts and never disrupts the event
      // feed when calendar services are unavailable on this device.
    }
  }

  static String _calendarDescription(EventModel event) {
    final link = event.eventUrl?.trim();
    if (link == null || link.isEmpty) return event.description;
    return '${event.description}\n\nEvent link: $link';
  }

  static String _calendarVersion(EventModel event, int reminderMinutes) => [
        event.updatedAt.toUtc().toIso8601String(),
        event.title,
        event.description,
        event.date.toUtc().toIso8601String(),
        event.durationMinutes,
        event.location,
        event.eventUrl ?? '',
        reminderMinutes,
      ].join('|');
}
