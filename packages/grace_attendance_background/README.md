# Grace Connect Android attendance worker

This private Flutter plugin registers `love.graceconnect/attendance` in every
Flutter engine. The attendance screen, native geofence callback and a scheduled
headless callback can all persist a follow-up check before their engine exits.
The Dart attendance service retains the church, schedule, location, dwell and
server-confirmation rules.

## Background execution

- Service opening/start timestamps become unique absolute one-time WorkManager
  requests. Each request schedules its next weekly occurrence. Reopening the
  app cannot postpone an existing request by changing its relative delay.
- Occurrence checks use a member/service/date key and absolute deadline. Only
  the earliest pending deadline is retained for that key; running work is not
  cancelled by a later scheduling or per-key cancellation request.
- Each worker creates one headless Flutter engine, runs
  `attendanceBackgroundCheck` in
  `package:grace_connect/services/attendance_service.dart`, and allows 90 seconds
  for `complete` on `love.graceconnect/attendance_background` with
  `{success: bool, retry: bool}`. Retriable failures get at most three retries.
- An independent daily reminder refresh runs without location permission, even
  when automatic check-in is off. Turning reminders off cancels that work.
- The engine and channel are always disposed. There is no continuous location
  foreground service, exact alarm or manufacturer-specific API.
- Boot/app-update recovery restores OS geofences with observed registration
  results. Normal scheduled checks leave native dwell fences intact.
- The pinned geofence dependency uses WorkManager `APPEND`. A failed/cancelled
  prerequisite can block later transitions, so recovery appends a successful
  worker with `APPEND_OR_REPLACE`. Scheduled attendance observations also run
  independently of that callback chain.

## Channel methods

| Method | Arguments |
| --- | --- |
| `configureAttendanceReminders` | `{enabled: bool}`; schedules/cancels daily reminder refresh |
| `scheduleGeofenceRefreshes` | `{epochMillis: List<int>}`; empty disables background checks |
| `scheduleAttendanceCheck` | `{epochMillis: int, key: String}` |
| `cancelAttendanceCheck` | `{key: String}`; preserves running work |
| `cancelAttendanceChecks` | Disables all scheduled attendance checks |
| `getBackgroundAttendanceStatus` | No arguments |

Diagnostics report enabled state, configured weekly slot count, last check time
and result, and last reboot/update registration time and result. Diagnostics do
not include coordinates or credentials. Registration diagnostics do not claim
that Android delivered a geofence transition or that attendance was confirmed.

## Validation

Run `./gradlew :grace_attendance_background:testDebugUnitTest` from `android/`.
The schedule regressions cover reopening before a service, delayed execution
across several weeks, duplicate dates and distinct check-in windows.

Device validation must cover a locked phone arriving before service opens,
remaining on site through dwell with the app closed, leaving during dwell,
reboot/app update, offline recovery, notification taps, and opting out. Verify
actual server confirmation and the original arrival timestamp. Test both the
reported Samsung Galaxy S21 Ultra and another supported Android device.

Android can defer WorkManager and background location under Doze/battery
restrictions. A requested timestamp is not a guaranteed execution timestamp;
service reminders and manual on-site sign-in remain required fallbacks.

- [Android geofence guidance](https://developer.android.com/develop/sensors-and-location/location/geofencing)
- [WorkManager request timing](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work)
- [Work chain failure semantics](https://developer.android.com/reference/androidx/work/ExistingWorkPolicy)
