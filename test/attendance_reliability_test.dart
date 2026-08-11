import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/services/attendance_dwell_session.dart';

void main() {
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

    expect(
        manifest, contains('android.permission.FOREGROUND_SERVICE_LOCATION'));
    expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
    expect(service, contains('foregroundNotificationConfig'));
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
    expect(
      migration,
      contains('on conflict ("churchId", "userId") where status = \'open\''),
    );
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
}
