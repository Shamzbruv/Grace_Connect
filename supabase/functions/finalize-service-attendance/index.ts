import {
  handleOptions,
  jsonResponse,
  requireCronSecret,
  serviceClient,
} from "../_shared/grace.ts";
import {
  attendanceServiceIsPastDue,
} from "../_shared/attendance_finalization.ts";

type ServiceScheduleRow = {
  serviceId?: string;
  churchId?: string;
  name?: string;
  dayOfWeek?: number;
  startTime?: string;
  endTime?: string;
  checkInClosesMinutesAfter?: number;
  minimumDwellMinutes?: number;
  attendanceEnabled?: boolean;
};

type MemberRow = {
  attendanceUserId?: string;
  id?: string;
  uid?: string;
  fullName?: string;
  photoUrl?: string;
  roles?: string[];
  appPrivileges?: string[];
};

type ChurchAliasRow = {
  id?: string;
  placeId?: string;
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
  const startUtc = new Date(`${isoDate}T05:00:00.000Z`);
  const endUtc = new Date(startUtc);
  endUtc.setUTCDate(endUtc.getUTCDate() + 1);
  return {
    isoDate,
    dayOfWeek: weekdayMap[value("weekday")] ?? 7,
    startUtc,
    endUtc,
    daysBack,
  };
}

function memberUserId(member: MemberRow): string {
  return String(member.attendanceUserId ?? "").trim();
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

function aliasesForChurch(
  churchId: string,
  churches: ChurchAliasRow[],
): { aliases: string[]; identity: string } {
  const match = churches.find((church) =>
    String(church.id ?? "").trim() === churchId ||
    String(church.placeId ?? "").trim() === churchId
  );
  if (!match) return { aliases: [churchId], identity: churchId };
  const aliases = Array.from(
    new Set([
      churchId,
      String(match.id ?? "").trim(),
      String(match.placeId ?? "").trim(),
    ].filter(Boolean)),
  );
  return {
    aliases,
    identity: String(match.id ?? "").trim() || churchId,
  };
}

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

  const { data: churchAliasData } = await client
    .from("churches")
    .select("id, placeId");
  const churchAliasRows = (churchAliasData ?? []) as ChurchAliasRow[];

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
  const processedChurches = new Set<string>();

  for (const churchId of churchIds) {
    const church = aliasesForChurch(churchId, churchAliasRows);
    if (processedChurches.has(church.identity)) continue;
    processedChurches.add(church.identity);

    const { data: membershipRows } = await client
      .from("church_memberships")
      .select("user_id")
      .in("church_id", church.aliases)
      .eq("membership_status", "active");

    const memberIds = Array.from(
      new Set(
        (membershipRows ?? []).map((row) => String(row.user_id ?? "").trim())
          .filter(Boolean),
      ),
    );

    const memberSelect = "id, uid, fullName, photoUrl, roles, appPrivileges";
    const { data: membersById, error: memberByIdError } = memberIds.length === 0
      ? { data: [] as MemberRow[], error: null }
      : await client.from("users").select(memberSelect).in("id", memberIds);
    const { data: membersByUid, error: memberByUidError } =
      memberIds.length === 0
        ? { data: [] as MemberRow[], error: null }
        : await client.from("users").select(memberSelect).in("uid", memberIds);

    if (memberByIdError && memberByUidError) {
      console.error(
        `Attendance profile display lookup failed for ${churchId}; closeout will continue with canonical membership IDs.`,
      );
    }

    const profiles = [
      ...(membersById ?? []),
      ...(membersByUid ?? []),
    ] as MemberRow[];
    // church_memberships.user_id is the canonical auth identity. Profile IDs
    // and legacy uid mirrors are display-data lookup keys only and can never
    // become a second attendance identity.
    const churchMembers = memberIds.map((membershipUserId) => {
      const profile = profiles.find((candidate) =>
        String(candidate.id ?? "").trim() === membershipUserId ||
        String(candidate.uid ?? "").trim() === membershipUserId
      );
      return {
        ...(profile ?? {}),
        attendanceUserId: membershipUserId,
      } satisfies MemberRow;
    });
    const sundaySchoolLeaders = churchMembers.filter(isLeader);
    for (const info of targetDates) {
      const { data: schedules, error: scheduleError } = await client
        .from("service_schedules")
        .select("*")
        .in("churchId", church.aliases)
        .eq("dayOfWeek", info.dayOfWeek)
        .eq("attendanceEnabled", true);
      if (scheduleError) continue;

      for (const schedule of (schedules ?? []) as ServiceScheduleRow[]) {
        servicesChecked++;
        const serviceId = String(schedule.serviceId ?? "").trim();
        const scheduleChurchId = String(schedule.churchId ?? "").trim() ||
          churchId;
        if (
          !serviceId ||
          !attendanceServiceIsPastDue(info.isoDate, schedule)
        ) continue;

        const { data: finalized, error: finalizedError } = await client
          .from("attendance_finalized_services")
          .select("church_id, report_sent_at")
          .eq("church_id", scheduleChurchId)
          .eq("service_id", serviceId)
          .eq("service_date", info.isoDate)
          .maybeSingle();
        if (finalizedError) continue;
        if (finalized) {
          if (isSundaySchool(schedule) && !finalized.report_sent_at) {
            reportsCreated += await sendSundaySchoolReport(
              client,
              scheduleChurchId,
              serviceId,
              info.isoDate,
              sundaySchoolLeaders,
            );
          }
          continue;
        }

        // Population, absence insertion, claim expiry, totals, and the marker
        // are one database transaction. The database derives members only
        // from active church_memberships and uses membership.user_id exactly.
        const { data: closeoutData, error: finalizeError } = await client.rpc(
          "finalize_attendance_service_v2",
          {
            p_church_id: scheduleChurchId,
            p_service_id: serviceId,
            p_service_date: info.isoDate,
            p_service_name: schedule.name ?? "Church Service",
          },
        );
        const closeout = closeoutData as Record<string, unknown> | null;
        // Do not send duplicate reports or count a service as finalized when
        // its durable finalization marker could not be saved.
        if (finalizeError || closeout?.finalized !== true) continue;
        absencesCreated += Number(closeout.absences_created ?? 0);
        servicesFinalized++;

        if (isSundaySchool(schedule)) {
          reportsCreated += await sendSundaySchoolReport(
            client,
            scheduleChurchId,
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
