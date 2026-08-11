import {
  handleOptions,
  jamaicaDateString,
  jsonResponse,
  requireCronSecret,
  sendTopicPush,
  serviceClient,
} from "../_shared/grace.ts";

function dateOffset(dateKey: string, days: number): string {
  const date = new Date(`${dateKey}T12:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "POST required." }, 405);

  const forbidden = requireCronSecret(request, "DAILY_QUIZ_CRON_SECRET");
  if (forbidden) return forbidden;

  const client = serviceClient();
  const today = jamaicaDateString();
  const yesterday = dateOffset(today, -1);
  const { data: streakRows, error: streakError } = await client
    .from("bible_streaks")
    .select("user_id, church_id, streak_count, last_reminder_date")
    .eq("last_read_date", yesterday)
    .gt("streak_count", 0)
    .or(`last_reminder_date.is.null,last_reminder_date.neq.${today}`);

  if (streakError) return jsonResponse({ error: streakError.message }, 500);
  const candidates = streakRows ?? [];
  if (candidates.length === 0) {
    return jsonResponse({ ok: true, candidates: 0, reminded: 0, pushes_sent: 0 });
  }

  const { data: preferences } = await client
    .from("users")
    .select("id, uid, notifyBibleStreak")
    .eq("notifyBibleStreak", true);
  const optedIn = new Set(
    (preferences ?? [])
      .filter((row) => row.notifyBibleStreak !== false)
      .flatMap((row) => [String(row.id ?? ""), String(row.uid ?? "")])
      .filter(Boolean),
  );

  let reminded = 0;
  let pushesSent = 0;
  for (const streak of candidates) {
    const userId = String(streak.user_id ?? "");
    if (!userId || !optedIn.has(userId)) continue;

    // Claim the reminder before delivery. Concurrent/retried cron calls cannot
    // create duplicates; the notification outbox still records provider errors.
    const { data: claimed } = await client
      .from("bible_streaks")
      .update({ last_reminder_date: today })
      .eq("user_id", userId)
      .eq("last_read_date", yesterday)
      .or(`last_reminder_date.is.null,last_reminder_date.neq.${today}`)
      .select("user_id")
      .maybeSingle();
    if (!claimed) continue;

    const count = Number(streak.streak_count ?? 0);
    const title = "Keep Your Bible Streak Alive";
    const body = `Your ${count}-day streak is waiting. Read a chapter for one minute before midnight to keep it going.`;
    const route = "/bible";
    await client.from("notifications").insert({
      user_id: userId,
      actor_id: null,
      actor_name: "Grace Connect",
      type: "bible_streak_reminder",
      title,
      body,
      place_id: streak.church_id ?? null,
      entity_table: "bible_streaks",
      entity_id: userId,
      route,
    });

    const push = await sendTopicPush(client, {
      topic: `user_${userId}`,
      title,
      body,
      route,
      type: "bible_streak_reminder",
      entityTable: "bible_streaks",
      entityId: userId,
    });
    if (push.sent) pushesSent++;
    reminded++;
  }

  return jsonResponse({
    ok: true,
    reminder_date: today,
    candidates: candidates.length,
    reminded,
    pushes_sent: pushesSent,
  });
});
