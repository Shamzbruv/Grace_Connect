export type AttendanceFinalizationSchedule = {
  startTime?: string;
  endTime?: string;
  checkInClosesMinutesAfter?: number;
  minimumDwellMinutes?: number;
};

export const ATTENDANCE_DELIVERY_BUFFER_MINUTES = 15;

function boundedInteger(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const parsed = Number(value ?? fallback);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(minimum, Math.min(maximum, Math.trunc(parsed)));
}

export function parseAttendanceTimeToSeconds(
  value?: string,
): number | null {
  const match = String(value ?? "").trim().match(
    /^([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?$/,
  );
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  const second = Number(match[3] ?? 0);
  if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
  if (
    !Number.isInteger(second) || hour < 0 || hour > 23 || minute < 0 ||
    minute > 59 || second < 0 || second > 59
  ) return null;
  return hour * 3600 + minute * 60 + second;
}

export function serviceClosedAtUtc(
  isoDate: string,
  schedule: AttendanceFinalizationSchedule,
): Date | null {
  const startSeconds = parseAttendanceTimeToSeconds(schedule.startTime);
  const endSeconds = parseAttendanceTimeToSeconds(schedule.endTime);
  if (startSeconds == null || endSeconds == null) return null;
  const overnightSeconds = endSeconds <= startSeconds ? 24 * 60 * 60 : 0;
  const closeSeconds = endSeconds + overnightSeconds + boundedInteger(
        schedule.checkInClosesMinutesAfter,
        30,
        0,
        240,
      ) * 60;
  const closedAt = new Date(`${isoDate}T05:00:00.000Z`);
  if (Number.isNaN(closedAt.getTime())) return null;
  closedAt.setUTCSeconds(closedAt.getUTCSeconds() + closeSeconds);
  return closedAt;
}

// The closeout job must leave enough time for someone who entered one moment
// before check-in closed to complete the configured dwell, plus Android's
// background callback delivery allowance. Until then, absence is not final.
export function serviceReadyToFinalizeAtUtc(
  isoDate: string,
  schedule: AttendanceFinalizationSchedule,
): Date | null {
  const closedAt = serviceClosedAtUtc(isoDate, schedule);
  if (closedAt == null) return null;
  const dwellMinutes = boundedInteger(
    schedule.minimumDwellMinutes,
    10,
    1,
    60,
  );
  return new Date(
    closedAt.getTime() +
      (dwellMinutes + ATTENDANCE_DELIVERY_BUFFER_MINUTES) * 60_000,
  );
}

export function attendanceServiceIsPastDue(
  isoDate: string,
  schedule: AttendanceFinalizationSchedule,
  now: Date = new Date(),
): boolean {
  const readyAt = serviceReadyToFinalizeAtUtc(isoDate, schedule);
  return readyAt != null && now.getTime() > readyAt.getTime();
}
