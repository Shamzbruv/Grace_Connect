import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:grace_connect/services/attendance_dwell_session.dart';
import 'package:grace_connect/services/attendance_service.dart';

void main() {
  test('Android auto-attendance requires background location readiness', () {
    const status = AttendanceSetupStatus(
      autoCheckInEnabled: true,
      locationServicesEnabled: true,
      permission: LocationPermission.whileInUse,
      hasChurchLocation: true,
      hasServiceSchedule: true,
      requiresBackgroundLocation: true,
    );

    expect(status.hasLocationPermission, isTrue);
    expect(status.hasAutoAttendanceLocationPermission, isFalse);
    expect(status.canMonitor, isFalse);
    expect(status.blockers.single, contains('Allow location all the time'));
  });

  test(
      'battery optimization restricting the app surfaces as a blocker even '
      'when every other check is green', () {
    // Every other signal can be green -- permission granted, geofence set,
    // schedule configured -- while Android still silently restricts this
    // app's background execution, which is what makes the geofence's
    // background delivery unreliable without ever showing up anywhere else
    // in this status. This must not be folded into canMonitor (the geofence
    // really is still registered and can still fire), only surfaced as an
    // actionable warning.
    const restricted = AttendanceSetupStatus(
      autoCheckInEnabled: true,
      locationServicesEnabled: true,
      permission: LocationPermission.always,
      hasChurchLocation: true,
      hasServiceSchedule: true,
      requiresBackgroundLocation: true,
      batteryOptimizationIgnored: false,
    );
    expect(restricted.canMonitor, isTrue);
    expect(
      restricted.blockers.single,
      contains('Battery optimization is still restricting this app'),
    );

    const unrestricted = AttendanceSetupStatus(
      autoCheckInEnabled: true,
      locationServicesEnabled: true,
      permission: LocationPermission.always,
      hasChurchLocation: true,
      hasServiceSchedule: true,
      requiresBackgroundLocation: true,
      batteryOptimizationIgnored: true,
    );
    expect(unrestricted.blockers, isEmpty);

    // Not applicable on iOS/web (requiresBackgroundLocation false) or before
    // the check has run (null) -- neither should ever be reported as a
    // blocker the member has to act on.
    const notApplicable = AttendanceSetupStatus(
      autoCheckInEnabled: true,
      locationServicesEnabled: true,
      permission: LocationPermission.whileInUse,
      hasChurchLocation: true,
      hasServiceSchedule: true,
    );
    expect(notApplicable.blockers, isEmpty);
  });

  group('durable attendance dwell', () {
    const maximumEvidenceGap = Duration(seconds: 90);
    const requiredOutsideDuration = Duration(minutes: 2);
    final startedAt = DateTime.utc(2026, 8, 8, 14);

    test('survives serialization and repeated inside observations', () {
      final initial = AttendanceDwellSession(
        startedAt: startedAt,
        lastInsideAt: startedAt,
      );
      final restored = AttendanceDwellSession.tryParse(
        initial.encode(),
        legacyObservedAt: startedAt.add(const Duration(seconds: 45)),
      );

      final observed = restored!.observedInsideAt(
        startedAt.add(const Duration(seconds: 45)),
      );

      expect(observed.startedAt, startedAt);
      expect(observed.lastInsideAt, startedAt.add(const Duration(seconds: 45)));
      expect(
        observed.dwellAt(startedAt.add(const Duration(minutes: 10))),
        const Duration(minutes: 10),
      );
    });

    test('preserves dwell across long Android callback and process gaps', () {
      final initial = AttendanceDwellSession(
        startedAt: startedAt,
        lastInsideAt: startedAt,
      );
      final nextObservation = startedAt.add(const Duration(minutes: 30));

      final resumed = initial.observedInsideAt(nextObservation);

      expect(resumed.startedAt, startedAt);
      expect(resumed.lastInsideAt, nextObservation);
    });

    test('resets only after sustained clear-outside evidence', () {
      final initial = AttendanceDwellSession(
        startedAt: startedAt,
        lastInsideAt: startedAt,
      );
      final firstOutside = initial.observedClearlyOutsideAt(
        startedAt.add(const Duration(minutes: 1)),
        maximumEvidenceGap: maximumEvidenceGap,
      );
      final secondOutside = firstOutside.observedClearlyOutsideAt(
        startedAt.add(const Duration(minutes: 2)),
        maximumEvidenceGap: maximumEvidenceGap,
      );
      final sustainedOutside = secondOutside.observedClearlyOutsideAt(
        startedAt.add(const Duration(minutes: 3)),
        maximumEvidenceGap: maximumEvidenceGap,
      );

      expect(
        secondOutside.hasSustainedClearOutsideEvidence(
          requiredOutsideDuration,
        ),
        isFalse,
      );
      expect(
        sustainedOutside.hasSustainedClearOutsideEvidence(
          requiredOutsideDuration,
        ),
        isTrue,
      );
    });

    test('restarts outside evidence after a callback gap', () {
      final initial = AttendanceDwellSession(
        startedAt: startedAt,
        lastInsideAt: startedAt,
      );
      final firstOutside = initial.observedClearlyOutsideAt(
        startedAt.add(const Duration(minutes: 1)),
        maximumEvidenceGap: maximumEvidenceGap,
      );
      final afterGap = firstOutside.observedClearlyOutsideAt(
        startedAt.add(const Duration(minutes: 3)),
        maximumEvidenceGap: maximumEvidenceGap,
      );

      expect(
        afterGap.clearOutsideStartedAt,
        startedAt.add(const Duration(minutes: 3)),
      );
      expect(
        afterGap.hasSustainedClearOutsideEvidence(requiredOutsideDuration),
        isFalse,
      );
    });

    test('persists outside evidence and clears it on an inside reading', () {
      final outside = AttendanceDwellSession(
        startedAt: startedAt,
        lastInsideAt: startedAt,
      ).observedClearlyOutsideAt(
        startedAt.add(const Duration(minutes: 1)),
        maximumEvidenceGap: maximumEvidenceGap,
      );
      final restored = AttendanceDwellSession.tryParse(
        outside.encode(),
        legacyObservedAt: startedAt.add(const Duration(minutes: 1)),
      );
      final backInside = restored!.observedInsideAt(
        startedAt.add(const Duration(minutes: 2)),
      );

      expect(restored.clearOutsideStartedAt, isNotNull);
      expect(backInside.startedAt, startedAt);
      expect(backInside.clearOutsideStartedAt, isNull);
      expect(backInside.lastClearOutsideAt, isNull);
    });

    test('migrates recent legacy timestamps without resetting them', () {
      final observedAt = startedAt.add(const Duration(minutes: 1));
      final migrated = AttendanceDwellSession.tryParse(
        startedAt.toIso8601String(),
        legacyObservedAt: observedAt,
      );

      expect(migrated, isNotNull);
      expect(migrated!.startedAt, startedAt);
      expect(migrated.lastInsideAt, observedAt);
    });

    test('rejects corrupt state and restarts future-clock state', () {
      expect(
        AttendanceDwellSession.tryParse(
          'not-json-or-a-date',
          legacyObservedAt: startedAt,
        ),
        isNull,
      );

      final future = AttendanceDwellSession(
        startedAt: startedAt.add(const Duration(hours: 1)),
        lastInsideAt: startedAt.add(const Duration(hours: 1)),
      );
      final restarted = future.observedInsideAt(startedAt);
      expect(restarted.startedAt, startedAt);
    });
  });

  test('attendance release and backend reliability guards remain wired', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final service =
        File('lib/services/attendance_service.dart').readAsStringSync();
    final finalizer = File(
      'supabase/functions/finalize-service-attendance/index.ts',
    ).readAsStringSync();
    final mapPicker = File(
      'lib/screens/attendance/church_location_picker_screen.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260805180000_attendance_reliability.sql',
    ).readAsStringSync();
    final idRepair = File(
      'supabase/migrations/20260814150000_attendance_alert_id_repair.sql',
    ).readAsStringSync();
    final gradle = File('android/app/build.gradle').readAsStringSync();

    expect(manifest, contains('ACCESS_BACKGROUND_LOCATION'));
    expect(manifest, contains('NativeGeofenceBroadcastReceiver'));
    expect(
      manifest,
      isNot(contains('android.permission.FOREGROUND_SERVICE_LOCATION')),
    );
    expect(service, isNot(contains('foregroundNotificationConfig')));
    expect(service, contains('NativeGeofenceManager.instance.createGeofence'));
    expect(service, contains('attendanceGeofenceTriggered'));
    expect(service, contains('GeofenceEvent.dwell'));
    expect(service, contains('requestAutoAttendancePermissions'));
    expect(service, contains('getRegisteredGeofenceIds'));
    expect(
      service,
      contains('restarts Android\'s dwell countdown'),
    );
    expect(service, contains("select('minimumDwellMinutes')"));
    expect(service, contains('_nativeGeofenceId(churchId, minutes)'));
    expect(gradle, contains('compileSdkVersion 36'));
    expect(gradle, contains('targetSdkVersion 36'));
    expect(service, contains('_recoverFromLocationStreamError(e);'));
    expect(
      service,
      contains('_monitoringRestartTimer = Timer(delay, () {'),
    );
    expect(service, contains('if (!_monitoringRequested) return;'));
    expect(service, contains('unawaited(initialize().catchError'));
    expect(service, contains('_monitoringRestartAttempts++;'));
    expect(service, contains('Duration(seconds: 5)'));
    expect(service, contains('Duration(minutes: 1)'));
    expect(service, contains("rpc('record_my_attendance'"));
    expect(service, contains(".select('id, present')"));
    expect(service, contains('decoded[\'present\'] == true'));
    expect(migration,
        contains('attendance_one_record_per_member_service_day_idx'));
    expect(migration, contains("existing.method = 'auto_absent'"));
    expect(migration, contains("'on_time', 'late', 'remote_verified'"));
    expect(
      migration,
      contains('Attendance method and status do not match.'),
    );
    expect(migration, contains('pg_advisory_xact_lock(hashtextextended('));
    expect(migration, contains('with attendance_totals as'));
    expect(migration, contains('set present_count = totals.present_count'));
    expect(migration, contains('late_count = totals.late_count'));
    expect(migration, contains('remote_count = totals.remote_count'));
    expect(migration, contains('absent_count = totals.absent_count'));
    expect(
      migration,
      contains("notification.entity_table = 'attendance_finalized_services'"),
    );
    expect(
      migration,
      contains("notification.entity_id = concat("),
    );
    expect(migration, contains('send_attendance_finalized_report'));
    expect(migration, contains('finalize_attendance_service'));
    expect(migration, contains('refresh_attendance_priority_list'));

    // A member who was genuinely on time but whose auto-detection silently
    // failed (background delivery delay, or they had to fall back to manual
    // sign-in) must be graded on when they actually arrived, not on when the
    // dwell countdown finished or when they happened to notice and tap the
    // button. Both the automatic and manual paths must pass the true
    // first-observed-on-site timestamp through to _markPresent instead of
    // leaving it to default to DateTime.now().
    expect(
      service,
      contains('checkedInAt: entryTime,'),
      reason: 'the automatic geofence path must grade lateness against the '
          'true dwell-entry time, not against when the dwell requirement '
          'happened to finish',
    );
    expect(
      service,
      contains('checkedInAt: arrivalTime,'),
      reason: 'manual sign-in must grade lateness against the already-'
          'tracked first-observed-on-site time, not against "now"',
    );

    // A single high-accuracy-only GPS request regularly fails indoors (a
    // church's roofing blocks the signal), and used to surface as a
    // misleading "check your connection" error. A real fallback chain is
    // required, not just a friendlier error message on the same single
    // attempt.
    expect(service, contains('LocationAccuracy.medium'));
    expect(service, contains('LocationAccuracy.reduced'));
    expect(
      service,
      contains('could not get a location fix. GPS can be unreliable indoors'),
    );
    expect(
      migration,
      contains('on conflict ("churchId", "userId") where status = \'open\''),
    );
    expect(idRepair, contains('alter column id set default gen_random_uuid()'));
    expect(idRepair, contains('where id is null'));
    expect(finalizer, contains('const targetDates = Array.from('));
    expect(finalizer, contains('{ length: 15 }'));
    expect(finalizer, contains('insert_absent_attendance_rows'));
    expect(finalizer, contains('"finalize_attendance_service"'));
    expect(finalizer, contains('"send_attendance_finalized_report"'));
    expect(finalizer, contains('const uid = String(member.uid ?? "").trim()'));
    expect(
      finalizer,
      contains('if (finalizeError || markerInserted !== true) continue'),
    );
    expect(mapPicker, contains('await _moveCameraToSelectedPosition();'));
  });

  test(
      'iOS auto-attendance requires "Always" location the same as Android, '
      'and the disclosure dialog explains why, how, and the cost of '
      'declining on both platforms', () {
    final service =
        File('lib/services/attendance_service.dart').readAsStringSync();
    final screen = File('lib/screens/attendance/attendance_screen.dart')
        .readAsStringSync();

    // iOS runs auto-attendance on a continuous Geolocator position stream,
    // not Android's native geofence -- but that stream is paused by iOS the
    // instant the app backgrounds unless location access is "Always". The
    // old code only enforced/required this on Android, so iOS could
    // "start monitoring" on While-Using-App access and then silently stop
    // the moment the phone locked -- indistinguishable from being broken.
    expect(service, contains('bool get _needsAlwaysLocationPermission => !kIsWeb;'));
    expect(
      service,
      isNot(contains(
          'if (_usesNativeAndroidGeofence && permission != LocationPermission.always)')),
      reason: 'the Always-permission gate must cover iOS too, not only Android',
    );
    expect(
      service,
      contains(
          'if (_needsAlwaysLocationPermission &&\n        permission != LocationPermission.always)'),
    );
    expect(
      service,
      isNot(contains('if (_usesNativeAndroidGeofence) {\n      final foreground =')),
      reason: 'requestAutoAttendancePermissions must request Always on both '
          'platforms, not branch away from it on iOS',
    );
    expect(
      service,
      contains('requiresBackgroundLocation: _needsAlwaysLocationPermission,'),
    );

    // The disclosure dialog must cover both platforms (it used to be shown
    // on Android only), explain why the permission is needed, give real
    // step-by-step instructions for each OS, and be explicit that skipping
    // it just means manual sign-in every service -- not a silent failure.
    expect(
      screen,
      isNot(contains(
          'if (value && !kIsWeb && defaultTargetPlatform == TargetPlatform.android)')),
      reason: 'the disclosure dialog must show on iOS too, not Android only',
    );
    expect(screen, contains('final isIOS = defaultTargetPlatform == TargetPlatform.iOS;'));
    expect(screen, contains('"Allow While Using App"'));
    expect(screen, contains('"Always"'));
    expect(screen, contains('"While using the app"'));
    expect(screen, contains('"Allow all the time"'));
    expect(screen, contains('Precise Location'));
    expect(
      screen,
      contains('you\'ll just need to open the app and tap Manual Sign-In'),
    );
    // Declining used to do nothing visible at all.
    expect(
      screen,
      contains(
          'You\'ll need to open the app and tap Manual Sign-In yourself at every service.'),
    );
  });
}
