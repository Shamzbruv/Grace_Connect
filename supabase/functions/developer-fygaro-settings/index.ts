import {
  authenticatedUser,
  handleOptions,
  jsonResponse,
  serviceClient,
} from "../_shared/grace.ts";

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "POST required." }, 405);
  }
  let user;
  try {
    user = await authenticatedUser(request);
  } catch {
    return jsonResponse({ error: "Sign in to the developer portal." }, 401);
  }
  const text = await request.text();
  if (new TextEncoder().encode(text).length > 16384) {
    return jsonResponse({ error: "Configuration is too large." }, 413);
  }
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return jsonResponse({ error: "Invalid configuration." }, 400);
  }
  if (!body || !["status", "save"].includes(body.action)) {
    return jsonResponse({ error: "Unknown action." }, 400);
  }
  const { data, error } = await serviceClient().rpc("fygaro_owner_settings", {
    p_actor: user.id,
    p_action: body.action,
    p_config: body.action === "save" ? body.config : null,
  });
  if (error) {
    return jsonResponse({
      error: error.code === "42501"
        ? "Only the platform owner can configure payments."
        : error.code === "P0001"
        ? error.message
        : "Payment configuration could not be saved.",
    }, error.code === "42501" ? 403 : 400);
  }
  return jsonResponse({
    ...data,
    webhook_url:
      "https://nimgsgnkcvddomrgkawb.supabase.co/functions/v1/fygaro-webhook",
    return_url: "https://graceconnect.love/manage-subscription.html",
  });
});
