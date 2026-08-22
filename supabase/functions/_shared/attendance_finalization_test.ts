import {
  ATTENDANCE_DELIVERY_BUFFER_MINUTES,
  attendanceServiceIsPastDue,
  parseAttendanceTimeToSeconds,
  serviceClosedAtUtc,
  serviceReadyToFinalizeAtUtc,
} from "./attendance_finalization.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("closeout waits for dwell completion and delivery grace", () => {
  const schedule = {
    startTime: "18:00",
    endTime: "19:00",
    checkInClosesMinutesAfter: 30,
    minimumDwellMinutes: 10,
  };

  assert(
    serviceClosedAtUtc("2026-08-21", schedule)?.toISOString() ===
      "2026-08-22T00:30:00.000Z",
    "normal close time",
  );
  assert(
    serviceReadyToFinalizeAtUtc("2026-08-21", schedule)?.toISOString() ===
      "2026-08-22T00:55:00.000Z",
    "close + dwell + delivery buffer",
  );
  assert(
    !attendanceServiceIsPastDue(
      "2026-08-21",
      schedule,
      new Date("2026-08-22T00:45:00.000Z"),
    ),
    "the old 7:45 PM closeout must still wait",
  );
  assert(
    attendanceServiceIsPastDue(
      "2026-08-21",
      schedule,
      new Date("2026-08-22T00:55:00.001Z"),
    ),
    "service becomes due after the complete safety window",
  );
  assert(
    !attendanceServiceIsPastDue(
      "2026-08-21",
      schedule,
      new Date("2026-08-22T00:55:00.000Z"),
    ),
    "the exact ready boundary is still protected",
  );
  assert(ATTENDANCE_DELIVERY_BUFFER_MINUTES === 15, "delivery buffer");
});

Deno.test("overnight schedules close on the following Jamaica date", () => {
  const overnight = {
    startTime: "23:00",
    endTime: "01:00",
    checkInClosesMinutesAfter: 30,
    minimumDwellMinutes: 10,
  };

  assert(
    serviceClosedAtUtc("2026-08-21", overnight)?.toISOString() ===
      "2026-08-22T06:30:00.000Z",
    "overnight close must advance one day",
  );
  assert(
    serviceReadyToFinalizeAtUtc("2026-08-21", overnight)?.toISOString() ===
      "2026-08-22T06:55:00.000Z",
    "overnight finalization window",
  );
});

Deno.test("time parsing is exact and malformed schedules never finalize", () => {
  assert(parseAttendanceTimeToSeconds("9:05") === 32_700, "one-digit hour");
  assert(parseAttendanceTimeToSeconds("09:05:30") === 32_730, "seconds");
  assert(parseAttendanceTimeToSeconds("24:00") === null, "invalid hour");
  assert(parseAttendanceTimeToSeconds("09:5") === null, "invalid minute");
  assert(parseAttendanceTimeToSeconds("09:05 garbage") === null, "suffix");
  assert(
    serviceReadyToFinalizeAtUtc("2026-08-21", {
      startTime: "bad",
      endTime: "19:00",
    }) === null,
    "malformed schedule",
  );
  assert(
    serviceClosedAtUtc("not-a-date", {
      startTime: "18:00",
      endTime: "19:00",
    }) === null,
    "malformed service date",
  );
  assert(
    serviceClosedAtUtc("2026-08-21", {
      startTime: "18:00:30",
      endTime: "19:00:30",
      checkInClosesMinutesAfter: 0,
    })?.toISOString() === "2026-08-22T00:00:30.000Z",
    "seconds agree with PostgreSQL time parsing",
  );
});

Deno.test("numeric schedule settings are clamped to database bounds", () => {
  const schedule = {
    startTime: "18:00",
    endTime: "19:00",
    checkInClosesMinutesAfter: 999,
    minimumDwellMinutes: -50,
  };
  assert(
    serviceReadyToFinalizeAtUtc("2026-08-21", schedule)?.toISOString() ===
      "2026-08-22T04:16:00.000Z",
    "240-minute close clamp + 1-minute dwell + 15-minute delivery",
  );
});
