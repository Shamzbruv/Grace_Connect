import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:grace_connect/services/attendance_dwell_session.dart';
import 'package:grace_connect/services/attendance_service.dart';

void main() {
  test('approximate location cannot report attendance setup as ready', () {
    const status = AttendanceSetupStatus(
      autoCheckInEnabled: true,
      locationServicesEnabled: true,
      permission: LocationPermission.always,
      hasChurchLocation: true,
      hasServiceSchedule: true,
      requiresBackgroundLocation: true,
      preciseLocationEnabled: false,
    );
    expect(status.canMonitor, isFalse);
    expect(status.blockers, contains(contains('Enable precise location')));
  });

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
    expect(
      service,
      contains("record['user_id']?.toString() != currentUserId"),
      reason: 'an offline check-in must never cross accounts on a shared '
          'device because the RPC derives identity from current auth.uid()',
    );
    expect(service, contains('remaining.add(encoded);'));
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
    expect(finalizer, isNot(contains('insert_absent_attendance_rows')));
    expect(finalizer, contains('"finalize_attendance_service_v2"'));
    expect(finalizer, contains('"send_attendance_finalized_report"'));
    expect(
      finalizer,
      contains('return String(member.attendanceUserId ?? "").trim()'),
    );
    expect(finalizer, isNot(contains('legacyMembers')));
    expect(finalizer, isNot(contains('joinDate')));
    expect(
      finalizer,
      contains('if (finalizeError || closeout?.finalized !== true) continue'),
    );
    expect(mapPicker, contains('await _moveCameraToSelectedPosition();'));
  });

  test('presence, closeout, and overnight occurrence stay race safe', () {
    final service =
        File('lib/services/attendance_service.dart').readAsStringSync();
    final finalizer = File(
      'supabase/functions/finalize-service-attendance/index.ts',
    ).readAsStringSync();
    final helper = File(
      'supabase/functions/_shared/attendance_finalization.ts',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/'
      '20260822025758_attendance_presence_state_race_guard.sql',
    ).readAsStringSync();
    final worker = File(
      'android/app/src/main/kotlin/love/graceconnect/'
      'AttendanceGeofenceRefreshWorker.kt',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/love/graceconnect/MainActivity.kt',
    ).readAsStringSync();
    final gradle = File('android/app/build.gradle').readAsStringSync();

    // The foreground/UI path must continue observing Android location and
    // must commit the idempotent attendance write when the visible countdown
    // reaches zero. Re-entering the screen cannot overlap polls or restart it.
    expect(service, contains('_activeServicePollTimer = Timer.periodic('));
    expect(service, contains('if (_isPollingLocation || !_isMonitoring)'));
    expect(service, contains('_activeServicePollTimer?.cancel();'));
    expect(service, contains('if (canMarkPresent && autoCheckInEnabled)'));
    expect(service, contains("prefs.getBool('auto_check_in') ?? false"));
    expect(service, contains('serviceDateKey: serviceDateKey'));

    // A verified claim is user-bound, cached only after the RPC explicitly
    // accepts it, and is cancelled only after durable clear-outside evidence.
    expect(service,
        contains("final claimKey = '\$userId|\$churchId|\$serviceId|"));
    expect(service, contains("acceptedStatus == 'pending'"));
    expect(service, contains("acceptedStatus == 'confirmed'"));
    expect(
      service,
      contains('hasSustainedClearOutsideEvidence('),
    );
    expect(service, contains('await _cancelPresenceClaim('));
    expect(service, contains('_syncedPresenceClaims.clear();'));

    // A client-side direct insert used to bypass the same advisory lock used
    // by closeout. All writes now go through the hardened occurrence RPC.
    expect(
      service,
      isNot(contains(".from('attendance').insert")),
    );
    expect(service, contains("rpc('record_my_attendance'"));

    // Current + previous weekday resolution and a logical service date keep
    // post-midnight attendance attached to the service that began yesterday.
    expect(service, contains('previousWeekday'));
    expect(service, contains('if (!scheduledEnd.isAfter(scheduledStart))'));
    expect(service, contains('scheduledEnd.add(const Duration(days: 1))'));
    expect(service, contains('final logicalServiceDate = serviceDateKey'));
    expect(service, contains('prompt.serviceStartTime'));
    expect(service, contains('prompt.serviceDateKey'));

    // ENTER/DWELL are transition-based. Re-adding persisted geofences at the
    // opening of every check-in window gives an already-inside member an
    // initial ENTER even while Flutter is closed.
    expect(activity, contains('scheduleGeofenceRefreshes'));
    expect(service, contains('_scheduleAndroidGeofenceRefreshes(churchId)'));
    expect(worker, contains('NativeGeofenceApiImpl(applicationContext)'));
    expect(worker, contains('api.createGeofence(geofence)'));
    expect(worker, contains('suspendCancellableCoroutine<Unit>'));
    expect(
        worker,
        contains(
            'PeriodicWorkRequestBuilder<AttendanceGeofenceRefreshWorker>(7, TimeUnit.DAYS)'));
    expect(worker, contains('ExistingPeriodicWorkPolicy.UPDATE'));
    expect(gradle, contains('androidx.work:work-runtime-ktx'));

    // SQL owns the occurrence identity and the monotonic state transition.
    expect(migration, contains('add column if not exists service_date date'));
    expect(migration, contains('alter column service_date set not null'));
    expect(
      migration,
      contains(
        'attendance_one_record_per_member_service_occurrence_idx',
      ),
    );
    expect(
      migration,
      contains('drop index if exists public.'
          'attendance_one_record_per_member_service_day_idx'),
    );
    expect(migration, contains('enable row level security'));
    expect(
      migration,
      contains('revoke insert, update, delete on table public.attendance'),
    );
    expect(migration, contains('record_my_attendance_presence'));
    expect(migration, contains("now() - interval '75 minutes'"));
    expect(
      migration,
      contains(
        'Automatic attendance requires a completed server presence claim.',
      ),
    );
    expect(
      migration,
      contains('claim.first_inside_at\n        + make_interval'),
    );
    expect(
      migration,
      contains('and claim.service_date = new.service_date'),
    );
    expect(
      migration,
      contains('Confirmed attendance cannot be overwritten by closeout.'),
    );

    // Finalization is one transaction and derives identity/history only from
    // authoritative active memberships. Profile IDs and account joinDate are
    // not permitted to create duplicate or pre-membership absences.
    final atomicStart = migration.indexOf(
      'create or replace function public.finalize_attendance_service_v2',
    );
    final pendingCheck = migration.indexOf(
      "and claim.status = 'pending'",
      atomicStart,
    );
    final absenceInsert = migration.indexOf(
      'insert into public.attendance (',
      atomicStart,
    );
    final markerInsert = migration.indexOf(
      'insert into public.attendance_finalized_services (',
      atomicStart,
    );
    expect(atomicStart, greaterThanOrEqualTo(0));
    expect(pendingCheck, greaterThan(atomicStart));
    expect(absenceInsert, greaterThan(pendingCheck));
    expect(markerInsert, greaterThan(absenceInsert));
    final atomicEnd = migration.indexOf(
      '-- The scheduled Edge job is migrated to the atomic v2 RPC below.',
      atomicStart,
    );
    final atomicBody = migration.substring(atomicStart, atomicEnd);
    expect(atomicBody, contains("membership.membership_status = 'active'"));
    expect(atomicBody, contains('membership.user_id::text as user_id'));
    expect(atomicBody, contains('membership.reviewed_at'));
    expect(atomicBody, contains('membership.created_at'));
    expect(atomicBody, contains('membership.requested_at'));
    expect(atomicBody, isNot(contains('public.users')));
    expect(atomicBody, isNot(contains('joinDate')));
    expect(atomicBody, contains('attendance.service_date = p_service_date'));
    expect(
      migration,
      contains('revoke execute on function public.'
          'insert_absent_attendance_rows(jsonb)'),
    );

    // Edge and SQL intentionally use the same parser, overnight rule, dwell
    // range, delivery buffer, and strict post-boundary readiness check.
    expect(helper, contains(r'^([01]?\d|2[0-3]):([0-5]\d)'));
    expect(helper, contains('endSeconds <= startSeconds'));
    expect(helper, contains('ATTENDANCE_DELIVERY_BUFFER_MINUTES = 15'));
    expect(helper, contains('now.getTime() > readyAt.getTime()'));
    expect(finalizer, contains('attendanceServiceIsPastDue'));
    expect(finalizer, contains('finalize_attendance_service_v2'));
    expect(finalizer, isNot(contains('legacyMembers')));
    expect(finalizer, isNot(contains('joinDate')));

    final careAlertStart = migration.indexOf(
      'create or replace function public.refresh_attendance_priority_list',
    );
    final careAlertBody = migration.substring(careAlertStart);
    expect(careAlertStart, greaterThanOrEqualTo(0));
    expect(careAlertBody, contains('membership.user_id::text as user_id'));
    expect(careAlertBody, contains('membership.reviewed_at'));
    expect(careAlertBody, isNot(contains('u."placeId"')));
    expect(careAlertBody, isNot(contains('joinDate')));
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
    expect(service,
        contains('bool get _needsAlwaysLocationPermission => !kIsWeb;'));
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
      isNot(contains(
          'if (_usesNativeAndroidGeofence) {\n      final foreground =')),
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
    expect(screen,
        contains('final isIOS = defaultTargetPlatform == TargetPlatform.iOS;'));
    expect(screen, contains('"Allow While Using App"'));
    expect(screen, contains('"Always"'));
    expect(screen, contains('"While using the app"'));
    expect(screen, contains('"Allow all the time"'));
    expect(screen, contains('Precise Location'));
    // `screen` is the file's raw, unparsed source bytes (read via
    // File.readAsStringSync), not the compiled runtime string -- an
    // apostrophe in the source is literally written as \' (backslash then
    // quote) inside a single-quoted Dart string literal. Checking for it
    // with a normal 'you\'ll' literal here compiles down to a plain quote
    // with no backslash, which can never match the raw source's escaped
    // form. \\\' produces the literal two-character backslash+quote this
    // comparison actually needs.
    expect(
      screen,
      contains('you\\\'ll just need to open the app and tap Manual Sign-In'),
    );
    // Declining used to do nothing visible at all.
    expect(
      screen,
      contains(
          'You\\\'ll need to open the app and tap Manual Sign-In yourself at every service.'),
    );
  });
}
