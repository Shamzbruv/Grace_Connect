// Scheduled sweep for abandoned uploads and failed deletions.
//
// Two ways bytes become orphaned: a device uploads and then never publishes,
// and an R2 delete fails transiently. Both end up as rows in
// reel_media_cleanup_jobs, and this drains that queue with backoff so a
// permanently failing object cannot spin forever or be forgotten.
import {
  handleOptions,
  jsonResponse,
  requireCronSecret,
  serviceClient,
} from "../_shared/grace.ts";
import { r2ConfigFromEnv } from "../_shared/r2.ts";
import { deleteR2Object } from "../_shared/reel_media.ts";

Deno.serve(async (request) => {
  const preflight = handleOptions(request);
  if (preflight) return preflight;
  const forbidden = requireCronSecret(request, "DAILY_QUIZ_CRON_SECRET");
  if (forbidden) return forbidden;

  const client = serviceClient();

  // Expire stale sessions first so their objects enter the queue in this run.
  const { data: expired, error: expireError } = await client
    .rpc("expire_reel_upload_sessions");
  if (expireError) {
    console.error("Could not expire upload sessions", expireError);
  }

  let config;
  try {
    config = r2ConfigFromEnv();
  } catch (error) {
    console.error("R2 configuration missing", error);
    return jsonResponse({ error: "Reel cleanup is not configured." }, 500);
  }

  const { data: claimed, error: claimError } = await client
    .rpc("claim_reel_cleanup_jobs", { p_limit: 50 });
  if (claimError) {
    console.error("Could not claim cleanup jobs", claimError);
    return jsonResponse({ error: "Could not claim cleanup work." }, 500);
  }

  const jobs = (claimed ?? []) as Array<{ id: string; object_key: string; attempts: number }>;
  let removed = 0;
  let failed = 0;
  for (const job of jobs) {
    const outcome = await deleteR2Object(config, job.object_key);
    await client.rpc("complete_reel_cleanup_job", {
      p_id: job.id,
      p_error: outcome.ok ? null : (outcome.error ?? "unknown"),
    });
    if (outcome.ok) removed += 1;
    else failed += 1;
  }

  return jsonResponse({
    sessions_expired: expired ?? 0,
    objects_removed: removed,
    objects_failed: failed,
    claimed: jobs.length,
  });
});
