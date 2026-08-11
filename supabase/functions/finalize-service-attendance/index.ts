import {
  handleOptions,
  jsonResponse,
  requireCronSecret,
  serviceClient,
} from "../_shared/grace.ts";

type ServiceScheduleRow = {
  serviceId?: string;
  churchId?: string;
  name?: string;
  dayOfWeek?: number;
  endTime?: string;
  checkInClosesMinutesAfter?: number;
  attendanceEnabled?: boolean;
};

type MemberRow = {
  id?: string;
  uid?: string;
  fullName?: string;
  photoUrl?: string;
  joinDate?: string;
  roles?: string[];
  appPrivileges?: string[];
};

type AttendanceRow = {
  user_id?: string;
  present?: boolean;
  status?: string;
  method?: string;
  timestamp?: string;
};

const leaderRoles = new Set([
  "pastor",
  "senior_pastor",
  "assistant_pastor",
  "acting_pastor",
  "admin",
  "church_admin",
  "administrator",
  "secretary",
  "church_secretary",
  "sunday_school_lead",
  "sunday_school_leader",
  "sunday_school_superintendent",
  "sunday_school_teacher",
  "head_usher",
]);

const leaderPrivileges = new Set([
  "viewAttendanceInsights",
  "manualCheckIn",
  "manageSchedule",
  "manageSchedules",
  "manageSundaySchool",
]);

function normalizeRole(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_|_$/g, "");
}

function parseTimeToMinutes(value?: string): number | null {
  const match = String(value ?? "").match(/^(\d{1,2}):(\d{2})/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

function jamaicaDateInfo(daysBack = 0) {
  const base = new Date(Date.now() - daysBack * 24 * 60 * 60 * 1000);
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Jamaica",
    weekday: "short",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(base);
  const value = (type: string) =>
    parts.find((part) => part.type === type)?.value ?? "";
  const weekdayMap: Record<string, number> = {
    Mon: 1,
    Tue: 2,
    Wed: 3,
    Thu: 4,
    Fri: 5,
    Sat: 6,
    Sun: 7,
  };
  const isoDate = `${value("year")}-${value("month")}-${value("day")}`;
  const minuteOfDay = Number(value("hour")) * 60 + Number(value("minute"));
  const startUtc = new Date(`${isoDate}T05:00:00.000Z`);
  const endUtc = new Date(startUtc);
  endUtc.setUTCDate(endUtc.getUTCDate() + 1);
  return {
    isoDate,
    dayOfWeek: weekdayMap[value("weekday")] ?? 7,
    minuteOfDay,
    startUtc,
    endUtc,
    daysBack,
  };
}

function serviceClosedAtUtc(
  isoDate: string,
  schedule: ServiceScheduleRow,
): Date | null {
  const endMinutes = parseTimeToMinutes(schedule.endTime);
  if (endMinutes == null) return null;
  const closeMinutes = endMinutes +
    Number(schedule.checkInClosesMinutesAfter ?? 30);
  const closedAt = new Date(`${isoDate}T05:00:00.000Z`);
  closedAt.setUTCMinutes(closedAt.getUTCMinutes() + closeMinutes);
  return closedAt;
}

function scheduleIsPastDue(
  info: ReturnType<typeof jamaicaDateInfo>,
  schedule: ServiceScheduleRow,
): boolean {
  const endMinutes = parseTimeToMinutes(schedule.endTime);
  if (endMinutes == null) return false;
  const closeMinutes = endMinutes +
    Number(schedule.checkInClosesMinutesAfter ?? 30);
  return info.daysBack > 0 || info.minuteOfDay > closeMinutes;
}

function memberUserId(member: MemberRow): string {
  const uid = String(member.uid ?? "").trim();
  return uid || String(member.id ?? "").trim();
}

function memberJoinDate(member: MemberRow): Date | null {
  const parsed = new Date(String(member.joinDate ?? ""));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function isSundaySchool(schedule: ServiceScheduleRow): boolean {
  return String(schedule.name ?? "").toLowerCase().includes("sunday school");
}

function isLeader(member: MemberRow): boolean {
  const roles = Array.isArray(member.roles) ? member.roles : [];
  const privileges = Array.isArray(member.appPrivileges)
    ? member.appPrivileges
    : [];
  return roles.some((role) => leaderRoles.has(normalizeRole(String(role)))) ||
    privileges.some((privilege) => leaderPrivileges.has(String(privilege)));
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function sendSundaySchoolReport(
  client: ReturnType<typeof serviceClient>,
  churchId: string,
  serviceId: string,
  serviceDate: string,
  leaders: MemberRow[],
): Promise<number> {
  const leaderIds = Array.from(
    new Set(
      leaders.map(memberUserId).filter((userId) => uuidPattern.test(userId)),
    ),
  );
  if (leaderIds.length === 0) return 0;

  const { data: created, error } = await client.rpc(
    "send_attendance_finalized_report",
    {
      p_church_id: churchId,
      p_service_id: serviceId,
      p_service_date: serviceDate,
      p_leader_ids: leaderIds,
    },
  );
  if (error) {
    console.error(
      `Could not create Sunday School report for ${churchId}/${serviceId}/${serviceDate}:`,
      error,
    );
    return 0;
  }
  return Number(created ?? 0);
}

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "POST required." }, 405);
  }

  const forbidden = requireCronSecret(request, "ATTENDANCE_CRON_SECRET");
  if (forbidden) return forbidden;

  const client = serviceClient();
  const body = await request.json().catch(() => ({})) as Record<
    string,
    unknown
  >;
  const requestedChurchId = String(body.church_id ?? "").trim();

  let churchIds: string[] = [];
  if (requestedChurchId) {
    churchIds = [requestedChurchId];
  } else {
    const { data: membershipChurchRows } = await client
      .from("church_memberships")
      .select("church_id")
      .eq("membership_status", "active");
    const { data: scheduleChurchRows } = await client
      .from("service_schedules")
      .select("churchId")
      .eq("attendanceEnabled", true);
    churchIds = Array.from(
      new Set([
        ...(membershipChurchRows ?? []).map((row) =>
          String(row.church_id ?? "").trim()
        ),
        ...(scheduleChurchRows ?? []).map((row) =>
          String(row.churchId ?? "").trim()
        ),
      ].filter(Boolean)),
    );
  }

  // Catch up after outages or a missing cron run instead of permanently
  // skipping members who did not sign in on older service days.
  const targetDates = Array.from(
    { length: 15 },
    (_, daysBack) => jamaicaDateInfo(daysBack),
  );
  let servicesChecked = 0;
  let servicesFinalized = 0;
  let absencesCreated = 0;
  let reportsCreated = 0;
  let careAlertsUpdated = 0;

  for (const churchId of churchIds) {
    const { data: membershipRows } = await client
      .from("church_memberships")
      .select("user_id")
      .eq("church_id", churchId)
      .eq("membership_status", "active");

    const memberIds = Array.from(
      new Set(
        (membershipRows ?? []).map((row) => String(row.user_id ?? "").trim())
          .filter(Boolean),
      ),
    );

    const memberSelect =
      "id, uid, fullName, photoUrl, joinDate, roles, appPrivileges";
    const { data: legacyMembers, error: legacyMemberError } = await client
      .from("users")
      .select(memberSelect)
      .eq("placeId", churchId);
    const { data: membersById, error: memberByIdError } = memberIds.length === 0
      ? { data: [] as MemberRow[], error: null }
      : await client.from("users").select(memberSelect).in("id", memberIds);
    const { data: membersByUid, error: memberByUidError } =
      memberIds.length === 0
        ? { data: [] as MemberRow[], error: null }
        : await client.from("users").select(memberSelect).in("uid", memberIds);

    if (legacyMemberError && memberByIdError && memberByUidError) continue;

    const membersByUserId = new Map<string, MemberRow>();
    for (
      const member of [
        ...(legacyMembers ?? []),
        ...(membersById ?? []),
        ...(membersByUid ?? []),
      ] as MemberRow[]
    ) {
      const userId = memberUserId(member);
      if (userId) membersByUserId.set(userId, member);
    }
    const churchMembers = Array.from(membersByUserId.values());
    if (churchMembers.length === 0) continue;
    const sundaySchoolLeaders = churchMembers.filter(isLeader);
    for (const info of targetDates) {
      const { data: schedules, error: scheduleError } = await client
        .from("service_schedules")
        .select("*")
        .eq("churchId", churchId)
        .eq("dayOfWeek", info.dayOfWeek)
        .eq("attendanceEnabled", true);
      if (scheduleError) continue;

      for (const schedule of (schedules ?? []) as ServiceScheduleRow[]) {
        servicesChecked++;
        const serviceId = String(schedule.serviceId ?? "").trim();
        if (!serviceId || !scheduleIsPastDue(info, schedule)) continue;

        const { data: finalized, error: finalizedError } = await client
          .from("attendance_finalized_services")
          .select("church_id, report_sent_at")
          .eq("church_id", churchId)
          .eq("service_id", serviceId)
          .eq("service_date", info.isoDate)
          .maybeSingle();
        if (finalizedError) continue;
        if (finalized) {
          if (isSundaySchool(schedule) && !finalized.report_sent_at) {
            reportsCreated += await sendSundaySchoolReport(
              client,
              churchId,
              serviceId,
              info.isoDate,
              sundaySchoolLeaders,
            );
          }
          continue;
        }

        const { data: attendanceRows, error: attendanceError } = await client
          .from("attendance")
          .select("user_id, present, status, method")
          .eq("church_id", churchId)
          .eq("service_id", serviceId)
          .gte("timestamp", info.startUtc.toISOString())
          .lt("timestamp", info.endUtc.toISOString());
        if (attendanceError) continue;

        const attendanceByUserId = new Map<string, AttendanceRow>();
        for (const row of (attendanceRows ?? []) as AttendanceRow[]) {
          const userId = String(row.user_id ?? "").trim();
          if (userId) attendanceByUserId.set(userId, row);
        }

        let presentCount = 0;
        let lateCount = 0;
        let remoteCount = 0;
        let absentCount = 0;
        const absentRows: Record<string, unknown>[] = [];
        const timestamp =
          serviceClosedAtUtc(info.isoDate, schedule)?.toISOString() ??
            new Date().toISOString();

        for (const member of churchMembers) {
          const primaryUserId = memberUserId(member);
          const alternateUserId = String(member.id ?? "").trim();
          if (!primaryUserId) continue;
          const joinedAt = memberJoinDate(member);
          if (joinedAt && joinedAt >= info.endUtc) continue;
          const attendance = attendanceByUserId.get(primaryUserId) ||
            (alternateUserId
              ? attendanceByUserId.get(alternateUserId)
              : undefined);

          if (!attendance) {
            absentCount++;
            absentRows.push({
              user_id: primaryUserId,
              church_id: churchId,
              service_id: serviceId,
              timestamp,
              method: "auto_absent",
              present: false,
              status: "absent",
              service_name: schedule.name ?? "Church Service",
            });
            continue;
          }

          const status = String(attendance.status ?? "");
          const method = String(attendance.method ?? "");
          if (attendance.present === false || status === "absent") {
            absentCount++;
          } else if (method === "remote" || status === "remote_verified") {
            remoteCount++;
          } else if (status === "late") {
            lateCount++;
          } else {
            presentCount++;
          }
        }

        if (absentRows.length > 0) {
          const { data: insertedCount, error: insertError } = await client.rpc(
            "insert_absent_attendance_rows",
            { p_rows: absentRows },
          );
          // Never mark a service finalized if its absences were not saved;
          // otherwise that service can never be repaired by a later cron run.
          if (insertError) continue;
          absencesCreated += Number(insertedCount ?? 0);
        }

        const { data: markerInserted, error: finalizeError } = await client.rpc(
          "finalize_attendance_service",
          {
            p_church_id: churchId,
            p_service_id: serviceId,
            p_service_date: info.isoDate,
            p_service_name: schedule.name ?? "Church Service",
          },
        );
        // Do not send duplicate reports or count a service as finalized when
        // its durable finalization marker could not be saved.
        if (finalizeError || markerInserted !== true) continue;
        servicesFinalized++;

        if (isSundaySchool(schedule)) {
          reportsCreated += await sendSundaySchoolReport(
            client,
            churchId,
            serviceId,
            info.isoDate,
            sundaySchoolLeaders,
          );
        }
      }
    }

    const { data: refreshedAlertCount, error: alertRefreshError } = await client
      .rpc("refresh_attendance_priority_list", {
        p_church_id: churchId,
        p_threshold_weeks: null,
      });
    if (!alertRefreshError) {
      careAlertsUpdated += Number(refreshedAlertCount ?? 0);
    }
  }

  return jsonResponse({
    ok: true,
    churches_checked: churchIds.length,
    services_checked: servicesChecked,
    services_finalized: servicesFinalized,
    absences_created: absencesCreated,
    reports_created: reportsCreated,
    care_alerts_updated: careAlertsUpdated,
  });
});
