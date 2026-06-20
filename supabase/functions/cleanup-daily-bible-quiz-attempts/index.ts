import {
  handleOptions,
  jsonResponse,
  requireCronSecret,
  serviceClient,
} from "../_shared/grace.ts";

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "POST required." }, 405);

  const forbidden = requireCronSecret(request, "DAILY_QUIZ_CRON_SECRET");
  if (forbidden) return forbidden;

  const client = serviceClient();
  const cutoff = new Date(Date.now() - 10000).toISOString();
  const { data: stale } = await client
    .from("quiz_attempts")
    .select("id, member_id, church_id")
    .eq("status", "active")
    .lt("last_heartbeat_at", cutoff);

  const attempts = stale ?? [];
  for (const attempt of attempts) {
    await client
      .from("quiz_attempts")
      .update({
        status: "abandoned",
        failed_at: new Date().toISOString(),
        failure_reason: "Heartbeat expired while quiz was active.",
      })
      .eq("id", attempt.id);
    await client.from("quiz_security_events").insert({
      attempt_id: attempt.id,
      member_id: attempt.member_id,
      church_id: attempt.church_id,
      event_type: "heartbeat_expired",
    });
  }

  return jsonResponse({ ok: true, abandoned: attempts.length });
});
