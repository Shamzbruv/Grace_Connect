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
  roles?: string[];
  appPrivileges?: string[];
};

type AttendanceRow = {
  user_id?: string;
  present?: boolean;
  status?: string;
  method?: string;
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
  const value = (type: string) => parts.find((part) => part.type === type)?.value ?? "";
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
  const closeMinutes = endMinutes + Number(schedule.checkInClosesMinutesAfter ?? 30);
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
  const closeMinutes = endMinutes + Number(schedule.checkInClosesMinutesAfter ?? 30);
  return info.daysBack > 0 || info.minuteOfDay > closeMinutes;
}

function memberUserId(member: MemberRow): string {
  return String(member.uid ?? member.id ?? "").trim();
}

function isSundaySchool(schedule: ServiceScheduleRow): boolean {
  return String(schedule.name ?? "").toLowerCase().includes("sunday school");
}

function isLeader(member: MemberRow): boolean {
  const roles = Array.isArray(member.roles) ? member.roles : [];
  const privileges = Array.isArray(member.appPrivileges) ? member.appPrivileges : [];
  return roles.some((role) => leaderRoles.has(normalizeRole(String(role)))) ||
    privileges.some((privilege) => leaderPrivileges.has(String(privilege)));
}

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "POST required." }, 405);

  const forbidden = requireCronSecret(request, "ATTENDANCE_CRON_SECRET");
  if (forbidden) return forbidden;

  const client = serviceClient();
  const body = await request.json().catch(() => ({})) as Record<string, unknown>;
  const requestedChurchId = String(body.church_id ?? "").trim();

  let churchIds: string[] = [];
  if (requestedChurchId) {
    churchIds = [requestedChurchId];
  } else {
    const { data: churchRows } = await client
      .from("church_memberships")
      .select("church_id")
      .eq("membership_status", "active");
    churchIds = Array.from(
      new Set((churchRows ?? []).map((row) => String(row.church_id ?? "").trim()).filter(Boolean)),
    );
  }

  const targetDates = [jamaicaDateInfo(0), jamaicaDateInfo(1)];
  let servicesChecked = 0;
  let servicesFinalized = 0;
  let absencesCreated = 0;
  let reportsCreated = 0;

  for (const churchId of churchIds) {
    const { data: membershipRows, error: membershipError } = await client
      .from("church_memberships")
      .select("user_id")
      .eq("church_id", churchId)
      .eq("membership_status", "active");
    if (membershipError) continue;

    const memberIds = Array.from(
      new Set((membershipRows ?? []).map((row) => String(row.user_id ?? "").trim()).filter(Boolean)),
    );
    if (memberIds.length === 0) continue;

    const { data: members, error: memberError } = await client
      .from("users")
      .select("id, uid, roles, appPrivileges")
      .in("id", memberIds);
    if (memberError) continue;

    const churchMembers = (members ?? []) as MemberRow[];
    if (churchMembers.length === 0) continue;

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

        const { data: finalized } = await client
          .from("attendance_finalized_services")
          .select("church_id")
          .eq("church_id", churchId)
          .eq("service_id", serviceId)
          .eq("service_date", info.isoDate)
          .maybeSingle();
        if (finalized) continue;

        const { data: attendanceRows } = await client
          .from("attendance")
          .select("user_id, present, status, method")
          .eq("church_id", churchId)
          .eq("service_id", serviceId)
          .gte("timestamp", info.startUtc.toISOString())
          .lt("timestamp", info.endUtc.toISOString());

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
        const timestamp = serviceClosedAtUtc(info.isoDate, schedule)?.toISOString() ??
          new Date().toISOString();

        for (const member of churchMembers) {
          const primaryUserId = memberUserId(member);
          const alternateUserId = String(member.id ?? "").trim();
          if (!primaryUserId) continue;
          const attendance = attendanceByUserId.get(primaryUserId) ||
            (alternateUserId ? attendanceByUserId.get(alternateUserId) : undefined);

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
          const { error: insertError } = await client.from("attendance").insert(absentRows);
          if (!insertError) absencesCreated += absentRows.length;
        }

        await client.from("attendance_finalized_services").upsert({
          church_id: churchId,
          service_id: serviceId,
          service_date: info.isoDate,
          service_name: schedule.name ?? "Church Service",
          present_count: presentCount,
          late_count: lateCount,
          remote_count: remoteCount,
          absent_count: absentCount,
          finalized_at: new Date().toISOString(),
        }, { onConflict: "church_id,service_id,service_date" });
        servicesFinalized++;

        if (isSundaySchool(schedule)) {
          const leaders = churchMembers.filter(isLeader);
          const notificationRows = leaders
            .map((leader) => String(leader.id ?? leader.uid ?? "").trim())
            .filter(Boolean)
            .map((leaderId) => ({
              user_id: leaderId,
              actor_id: null,
              actor_name: "Grace Connect",
              type: "attendance_report",
              title: "Sunday School Attendance Ready",
              body:
                `${presentCount} present • ${lateCount} late • ${remoteCount} remote • ${absentCount} absent for ${info.isoDate}.`,
              place_id: churchId,
              entity_table: "attendance_finalized_services",
              entity_id: `${churchId}:${serviceId}:${info.isoDate}`,
              route: "/attendance_insights",
            }));
          if (notificationRows.length > 0) {
            const { error: notifyError } = await client
              .from("notifications")
              .insert(notificationRows);
            if (!notifyError) {
              reportsCreated += notificationRows.length;
              await client
                .from("attendance_finalized_services")
                .update({ report_sent_at: new Date().toISOString() })
                .eq("church_id", churchId)
                .eq("service_id", serviceId)
                .eq("service_date", info.isoDate);
            }
          }
        }
      }
    }
  }

  return jsonResponse({
    ok: true,
    churches_checked: churchIds.length,
    services_checked: servicesChecked,
    services_finalized: servicesFinalized,
    absences_created: absencesCreated,
    reports_created: reportsCreated,
  });
});
