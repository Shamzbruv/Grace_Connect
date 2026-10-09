import { anonClient, authenticatedUser, handleOptions, jsonResponse,
  requireCronSecret, serviceClient } from "../_shared/grace.ts";
import { requireFygaroCheckout } from "../_shared/fygaro_configuration.ts";
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
      if (Date.now() < Date.parse(job.consumed_at) + 16 * 60 * 1000) {
        return {phase:job.phase,waiting_for_uploads:true};
      }
      const config = r2ConfigFromEnv();
      const page = await listResetObjects(config, fetch, job.r2_after ?? undefined);
      const { data: keys, error } = await client.rpc("platform_reset_filter_r2_keys", {p_keys:page,p_lease:job.lease});
      if(error) throw error;
      // Advance past protected files as well, so a page of review media cannot
      // trap cleanup on the first page. Failed deletions never move the cursor.
      const outcomes = await Promise.all((keys as string[]).map(key => deleteR2Object(config, key)));
      if (outcomes.some(outcome => !outcome.ok)) throw new Error("R2 deletion failed");
      if (page.length) await command("r2_cursor", page[page.length-1]);
      else await command("advance");
    } else if (job.phase === "accounts") {
      const others = await command("account_batch") as string[];
      for (const id of others) {
        const { error } = await client.auth.admin.deleteUser(id);
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
    try { await requireFygaroCheckout(client); paymentsReady = true; } catch { /* Only readiness, never secret values. */ }
    try { r2ConfigFromEnv(); mediaReady = true; } catch { /* Same. */ }
    return jsonResponse({ ...status, payments_ready: paymentsReady, media_ready: mediaReady,
      reset_ready: mediaReady && !!Deno.env.get("DAILY_QUIZ_CRON_SECRET") && status.reset_worker_scheduled,
      payment_webhook: "https://nimgsgnkcvddomrgkawb.supabase.co/functions/v1/fygaro-webhook" });
  }
  if (body.action === "protect_review") {
    if (status.role !== "super_developer") return jsonResponse({error:"Only the platform owner can configure review protection."},403);
    const valid=(value:unknown,max:number)=>Array.isArray(value) && value.length>0 && value.length<=max && value.every(v=>typeof v==='string' && v.length<=320);
    if(!valid(body.emails,20)||!valid(body.church_ids,10)) return jsonResponse({error:"Enter review login emails and church IDs."},400);
    const {error}=await client.rpc("platform_reset_protect_review",{p_actor:user.id,p_emails:body.emails,p_church_ids:body.church_ids});
    if(error) return jsonResponse({error:error.code==='P0001' ? error.message : "Review protection could not be saved. Check the accounts and church IDs."},400);
    return jsonResponse({saved:true});
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
