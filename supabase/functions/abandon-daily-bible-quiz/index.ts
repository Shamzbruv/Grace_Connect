import {
  authenticatedUser,
  handleOptions,
  jsonResponse,
  serviceClient,
} from "../_shared/grace.ts";

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "POST required." }, 405);

  try {
    const client = serviceClient();
    const user = await authenticatedUser(request);
    const body = await request.json().catch(() => ({}));
    const attemptId = String(body.attempt_id ?? "");
    if (!attemptId) return jsonResponse({ error: "Missing attempt." }, 400);

    const { data: attempt } = await client
      .from("quiz_attempts")
      .select("id, church_id")
      .eq("id", attemptId)
      .eq("member_id", user.id)
      .eq("status", "active")
      .maybeSingle();
    if (!attempt) return jsonResponse({ ok: true, status: "not_active" });

    const now = new Date().toISOString();
    await client
      .from("quiz_attempts")
      .update({
        status: "abandoned",
        failed_at: now,
        failure_reason: "Grace Connect was closed or moved to the background during the quiz.",
      })
      .eq("id", attemptId);
    await client.from("quiz_security_events").insert({
      attempt_id: attemptId,
      member_id: user.id,
      church_id: attempt.church_id,
      event_type: "app_backgrounded",
    });
    return jsonResponse({ ok: true, status: "abandoned" });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : "Unable to abandon quiz." }, 400);
  }
});
