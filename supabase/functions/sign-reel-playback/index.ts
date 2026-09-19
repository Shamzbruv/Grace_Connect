// Exchanges reel ids for short-lived presigned GET URLs.
//
// This is the only path by which private reel media becomes fetchable, so
// visibility is re-checked here per reel. The ids in the request are treated
// as a request, never as proof of entitlement: a caller can send any id.
//
// Video and poster are signed together, so a 12-reel page costs one call
// rather than 24. URLs are returned for the client to hold in memory only --
// they are never persisted, here or on the device.
import {
  authenticatedUser,
  handleOptions,
  jsonResponse,
  serviceClient,
} from "../_shared/grace.ts";
import { presignR2Url, r2ConfigFromEnv } from "../_shared/r2.ts";
import { parsePlaybackBatch, REEL_LIMITS } from "../_shared/reel_validation.ts";

Deno.serve(async (request) => {
  const preflight = handleOptions(request);
  if (preflight) return preflight;
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  let user;
  try {
    user = await authenticatedUser(request);
  } catch {
    return jsonResponse({ error: "Not authenticated." }, 401);
  }

  const body = await request.json().catch(() => ({}));
  const batch = parsePlaybackBatch(body);
  if (!batch.ok) return jsonResponse({ error: batch.error }, 400);

  const client = serviceClient();

  // The same predicate the feed uses, so the two can never disagree about
  // who may see a reel. Unauthorized ids are dropped rather than refused, so
  // this cannot be used to probe which reels exist.
  const { data: authorized, error: authorizationError } = await client
    .rpc("authorize_reel_playback", {
      p_viewer: user.id,
      p_reel_ids: batch.value,
    });
  if (authorizationError) {
    console.error("Could not authorize reel playback", authorizationError);
    return jsonResponse({ error: "Could not prepare playback." }, 500);
  }

  let config;
  try {
    config = r2ConfigFromEnv();
  } catch (error) {
    console.error("R2 configuration missing", error);
    return jsonResponse({ error: "Reel playback is not configured." }, 500);
  }

  const rows = (authorized ?? []) as Array<{
    id: string;
    video_object_key: string | null;
    poster_object_key: string | null;
  }>;

  const expiresAt = new Date(Date.now() + REEL_LIMITS.playbackUrlTtlSeconds * 1000);
  const media = await Promise.all(rows.map(async (row) => {
    const [videoUrl, posterUrl] = await Promise.all([
      row.video_object_key
        ? presignR2Url({
          config,
          method: "GET",
          key: row.video_object_key,
          expiresInSeconds: REEL_LIMITS.playbackUrlTtlSeconds,
        })
        : Promise.resolve(null),
      row.poster_object_key
        ? presignR2Url({
          config,
          method: "GET",
          key: row.poster_object_key,
          expiresInSeconds: REEL_LIMITS.playbackUrlTtlSeconds,
        })
        : Promise.resolve(null),
    ]);
    return { reel_id: row.id, video_url: videoUrl, poster_url: posterUrl };
  }));

  return jsonResponse({
    media,
    expires_at: expiresAt.toISOString(),
    ttl_seconds: REEL_LIMITS.playbackUrlTtlSeconds,
  });
});
