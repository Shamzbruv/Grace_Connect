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
    if (!attempt) return jsonResponse({ error: "No active quiz attempt." }, 404);

    await client
      .from("quiz_attempts")
      .update({ last_heartbeat_at: new Date().toISOString() })
      .eq("id", attemptId);

    return jsonResponse({ ok: true });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : "Heartbeat failed." }, 400);
  }
});
