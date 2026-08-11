import 'dart:convert';

/// Durable on-site dwell state used by automatic attendance.
///
/// Android may pause callbacks while the app is backgrounded, so observation
/// gaps alone never reset a countdown. Leaving and returning only resets it
/// after multiple accurate outside observations establish a sustained exit.
class AttendanceDwellSession {
  const AttendanceDwellSession({
    required this.startedAt,
    required this.lastInsideAt,
    this.clearOutsideStartedAt,
    this.lastClearOutsideAt,
  });

  final DateTime startedAt;
  final DateTime lastInsideAt;
  final DateTime? clearOutsideStartedAt;
  final DateTime? lastClearOutsideAt;

  static AttendanceDwellSession? tryParse(
    String? raw, {
    required DateTime legacyObservedAt,
  }) {
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final startedAt = DateTime.tryParse(
          decoded['startedAt']?.toString() ?? '',
        );
        final lastInsideAt = DateTime.tryParse(
          decoded['lastInsideAt']?.toString() ?? '',
        );
        if (startedAt != null && lastInsideAt != null) {
          return AttendanceDwellSession(
            startedAt: startedAt,
            lastInsideAt: lastInsideAt,
            clearOutsideStartedAt: DateTime.tryParse(
              decoded['clearOutsideStartedAt']?.toString() ?? '',
            ),
            lastClearOutsideAt: DateTime.tryParse(
              decoded['lastClearOutsideAt']?.toString() ?? '',
            ),
          );
        }
      }
    } catch (_) {
      // Fall through to the legacy ISO timestamp format.
    }

    final legacyStartedAt = DateTime.tryParse(raw);
    if (legacyStartedAt == null) return null;
    final legacyAge = legacyObservedAt.difference(legacyStartedAt);
    final canSafelyMigrate =
        !legacyAge.isNegative && legacyAge <= const Duration(minutes: 30);
    return AttendanceDwellSession(
      startedAt: legacyStartedAt,
      lastInsideAt: canSafelyMigrate ? legacyObservedAt : legacyStartedAt,
    );
  }

  bool isValidAt(DateTime observedAt) {
    const clockTolerance = Duration(minutes: 1);
    if (startedAt.isAfter(observedAt.add(clockTolerance)) ||
        lastInsideAt.isAfter(observedAt.add(clockTolerance))) {
      return false;
    }
    if (lastInsideAt.isBefore(startedAt)) return false;

    final outsideStartedAt = clearOutsideStartedAt;
    final outsideLastSeenAt = lastClearOutsideAt;
    if ((outsideStartedAt == null) != (outsideLastSeenAt == null)) return false;
    if (outsideStartedAt != null && outsideLastSeenAt != null) {
      if (outsideStartedAt.isBefore(startedAt) ||
          outsideLastSeenAt.isBefore(outsideStartedAt) ||
          outsideLastSeenAt.isAfter(observedAt.add(clockTolerance))) {
        return false;
      }
    }
    return true;
  }

  /// An inside observation never resets a valid dwell merely because Android
  /// paused callbacks. Only sustained, accurate outside observations can do
  /// that. This is what lets a countdown survive navigation and process gaps.
  AttendanceDwellSession observedInsideAt(DateTime observedAt) {
    if (!isValidAt(observedAt)) {
      return AttendanceDwellSession(
        startedAt: observedAt,
        lastInsideAt: observedAt,
      );
    }

    return AttendanceDwellSession(
      startedAt: startedAt,
      lastInsideAt: observedAt,
    );
  }

  AttendanceDwellSession observedClearlyOutsideAt(
    DateTime observedAt, {
    required Duration maximumEvidenceGap,
  }) {
    if (!isValidAt(observedAt)) return this;

    final previousStart = clearOutsideStartedAt;
    final previousObservation = lastClearOutsideAt;
    final continuesEvidence = previousStart != null &&
        previousObservation != null &&
        !observedAt.isBefore(previousObservation) &&
        observedAt.difference(previousObservation) <= maximumEvidenceGap;

    return AttendanceDwellSession(
      startedAt: startedAt,
      lastInsideAt: lastInsideAt,
      clearOutsideStartedAt: continuesEvidence ? previousStart : observedAt,
      lastClearOutsideAt: observedAt,
    );
  }

  bool hasSustainedClearOutsideEvidence(Duration requiredDuration) {
    final outsideStartedAt = clearOutsideStartedAt;
    final outsideLastSeenAt = lastClearOutsideAt;
    if (outsideStartedAt == null || outsideLastSeenAt == null) return false;
    return outsideLastSeenAt.difference(outsideStartedAt) >= requiredDuration;
  }

  Duration dwellAt(DateTime observedAt) {
    final duration = observedAt.difference(startedAt);
    return duration.isNegative ? Duration.zero : duration;
  }

  String encode() => jsonEncode({
        'startedAt': startedAt.toUtc().toIso8601String(),
        'lastInsideAt': lastInsideAt.toUtc().toIso8601String(),
        if (clearOutsideStartedAt != null)
          'clearOutsideStartedAt':
              clearOutsideStartedAt!.toUtc().toIso8601String(),
        if (lastClearOutsideAt != null)
          'lastClearOutsideAt': lastClearOutsideAt!.toUtc().toIso8601String(),
      });
}
