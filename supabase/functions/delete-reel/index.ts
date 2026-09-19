// Removes a reel and its media. Idempotent: deleting an already-deleted reel
// succeeds, so a client retry after a dropped response is safe.
//
// The database hides the reel first and records what media is owed for
// removal. If R2 deletion then fails, the durable cleanup queue retries it --
// the bytes are never silently abandoned.
import {
  authenticatedUser,
  handleOptions,
  jsonResponse,
  serviceClient,
} from "../_shared/grace.ts";
import { anonClient } from "../_shared/grace.ts";
import { accessTokenFromRequest } from "../_shared/grace.ts";
import { r2ConfigFromEnv } from "../_shared/r2.ts";
import { deleteR2Object } from "../_shared/reel_media.ts";

Deno.serve(async (request) => {
  const preflight = handleOptions(request);
  if (preflight) return preflight;
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    await authenticatedUser(request);
  } catch {
    return jsonResponse({ error: "Not authenticated." }, 401);
  }

  const body = await request.json().catch(() => ({}));
  const reelId = String((body as Record<string, unknown>).reel_id ?? "").trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(reelId)) {
    return jsonResponse({ error: "A reel id is required." }, 400);
  }

  // Ownership is enforced inside delete_my_reel against auth.uid(), so the
  // call runs as the member rather than as the service role.
  const token = accessTokenFromRequest(request)!;
  const { data, error } = await anonClient(token).rpc("delete_my_reel", {
    p_reel_id: reelId,
  });
  if (error) {
    const denied = String(error.message ?? "").includes("Only the author");
    return jsonResponse({ error: denied ? "Only the author can delete this reel." : "Could not delete this reel." }, denied ? 403 : 500);
  }

  const result = (data ?? {}) as { object_keys?: string[]; already_deleted?: boolean };
  const keys = result.object_keys ?? [];

  let removed = 0;
  let queuedForRetry = 0;
  if (keys.length > 0) {
    let config;
    try {
      config = r2ConfigFromEnv();
    } catch {
      // The reel is already hidden and its keys are queued; the scheduled
      // sweep will remove the bytes once configuration is restored.
      return jsonResponse({ deleted: true, media_removed: 0, queued_for_retry: keys.length });
    }
    const client = serviceClient();
    for (const key of keys) {
      const outcome = await deleteR2Object(config, key);
      if (outcome.ok) {
        removed += 1;
        await client.from("reel_media_cleanup_jobs")
          .update({ completed_at: new Date().toISOString() })
          .eq("object_key", key).is("completed_at", null);
      } else {
        queuedForRetry += 1;
        await client.from("reel_media_cleanup_jobs")
          .update({ last_error: outcome.error ?? "unknown" })
          .eq("object_key", key).is("completed_at", null);
      }
    }
  }

  return jsonResponse({
    deleted: true,
    already_deleted: result.already_deleted === true,
    media_removed: removed,
    queued_for_retry: queuedForRetry,
  });
});
