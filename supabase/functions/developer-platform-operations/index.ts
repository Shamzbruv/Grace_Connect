import { anonClient, authenticatedUser, handleOptions, jsonResponse,
  requireCronSecret, serviceClient } from "../_shared/grace.ts";
import { fygaroPaymentConfigFromEnv } from "../_shared/fygaro.ts";
import { r2ConfigFromEnv } from "../_shared/r2.ts";
import { deleteR2Object } from "../_shared/reel_media.ts";
import { listResetObjects, validateResetRequest } from "../_shared/platform_reset.ts";

const safeError = "Cleanup paused after a service error. It will retry automatically; check function logs if it persists.";

async function work() {
  const client = serviceClient();
  const { data: job, error } = await client.rpc("platform_reset_worker", { p_command: "claim" });
  if (error) throw error;
  if (!job) return { idle: true };
  const command = async (name: string, errorMessage?: string) => {
    const { data, error } = await client.rpc("platform_reset_worker", {
      p_command: name, p_lease: job.lease, p_error: errorMessage ?? null,
    });
    if (error) throw error;
    return data;
  };
  let failed = false;
  try {
    if (job.phase === "data") {
      await command("purge");
    } else if (job.phase === "storage") {
      const items = await command("storage_batch") as Array<{ bucket: string; path: string }>;
      for (const bucket of new Set(items.map(item => item.bucket))) {
        const paths = items.filter(item => item.bucket === bucket).map(item => item.path);
        const { error } = await client.storage.from(bucket).remove(paths);
        if (error) throw error;
      }
      if (!items.length) await command("advance");
    } else if (job.phase === "r2") {
      const config = r2ConfigFromEnv();
      const keys = await listResetObjects(config);
      // No continuation cursor: deleting the first page makes the next first
      // page the remaining objects, including orphaned or late uploads.
      const outcomes = await Promise.all(keys.map(key => deleteR2Object(config, key)));
      if (outcomes.some(outcome => !outcome.ok)) throw new Error("R2 deletion failed");
      if (!keys.length) await command("advance");
    } else if (job.phase === "accounts") {
      const { data, error } = await client.auth.admin.listUsers({ page: 1, perPage: 50 });
      if (error) throw error;
      const others = data.users.filter(user => user.id !== job.keeper_id);
      for (const user of others) {
        const { error } = await client.auth.admin.deleteUser(user.id);
        if (error) throw error;
      }
      if (!others.length) await command("advance");
    }
  } catch (error) {
    failed = true;
    // Do not log user details, credentials or signed URLs.
    console.error("Platform reset worker stopped", job.phase, error instanceof Error ? error.name : "service_error");
  } finally {
    await command("release", failed ? safeError : undefined);
  }
  return { phase: job.phase, retrying: failed };
}

Deno.serve(async request => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);
  const body = await request.json().catch(() => ({}));
  if (!body || typeof body !== "object") return jsonResponse({ error: "Invalid request." }, 400);
  if (body.action === "work") {
    // This function disables gateway JWT checks only for this cron path.
    // Interactive paths below still validate the user's JWT with Auth.
    const forbidden = requireCronSecret(request, "DAILY_QUIZ_CRON_SECRET");
    if (forbidden) return forbidden;
    try { return jsonResponse(await work()); }
    catch { return jsonResponse({ error: "Cleanup worker unavailable." }, 500); }
  }
  let user;
  try { user = await authenticatedUser(request); }
  catch { return jsonResponse({ error: "Sign in to the developer portal." }, 401); }
  const client = serviceClient();
  const { data: status, error } = await client.rpc("platform_operations_status", { p_actor: user.id });
  if (error || !status) return jsonResponse({ error: "Developer access required." }, 403);
  if (body.action === "status") {
    let paymentsReady = false;
    let mediaReady = false;
    try { fygaroPaymentConfigFromEnv(); paymentsReady = true; } catch { /* Only readiness, never secret values. */ }
    try { r2ConfigFromEnv(); mediaReady = true; } catch { /* Same. */ }
    return jsonResponse({ ...status, payments_ready: paymentsReady, media_ready: mediaReady,
      reset_ready: mediaReady && !!Deno.env.get("DAILY_QUIZ_CRON_SECRET") && status.reset_worker_scheduled,
      payment_webhook: "https://nimgsgnkcvddomrgkawb.supabase.co/functions/v1/fygaro-webhook" });
  }
  if (body.action !== "reset") return jsonResponse({ error: "Unknown action." }, 400);
  if (!status.reset.can_start || status.role !== "super_developer") return jsonResponse({ error: "This reset is unavailable or has already been used." }, 403);
  if (!validateResetRequest(body)) return jsonResponse({ error: "Enter your password and the exact confirmation phrase." }, 400);
  if (!status.reset_worker_scheduled || !Deno.env.get("DAILY_QUIZ_CRON_SECRET")) return jsonResponse({ error: "The reset worker must be configured first." }, 503);
  try {
    // Read-only preflight confirms real R2 list permissions before any data is changed.
    await listResetObjects(r2ConfigFromEnv());
  } catch { return jsonResponse({ error: "R2 cleanup access must be configured before resetting." }, 503); }
  const proof = anonClient();
  const { data: signedIn, error: passwordError } = await proof.auth.signInWithPassword({
    email: user.email ?? "", password: body.password,
  });
  const verified = !passwordError && signedIn.user?.id === user.id;
  // Discard just the temporary proof session, never the active portal session.
  if (signedIn.session) await proof.auth.signOut({ scope: "local" });
  if (!verified) return jsonResponse({ error: "The password could not be verified." }, 403);
  const { data: started, error: startError } = await client.rpc("platform_reset_begin", { p_actor: user.id });
  if (startError) return jsonResponse({ error: "The reset could not start. Refresh its status; it may already be in progress." }, 409);
  return jsonResponse(started, 202);
});
