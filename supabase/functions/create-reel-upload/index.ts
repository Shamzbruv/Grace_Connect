// Issues short-lived presigned PUT URLs so a device uploads reel media
// straight to private R2. Supabase is never in the byte path.
import {
  authenticatedUser,
  handleOptions,
  jsonResponse,
  profileChurchId,
  serviceClient,
  userProfile,
} from "../_shared/grace.ts";
import { presignR2Url, r2ConfigFromEnv, reelObjectKeys } from "../_shared/r2.ts";
import { REEL_LIMITS, validateUploadRequest } from "../_shared/reel_validation.ts";

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
  const validated = validateUploadRequest(body);
  if (!validated.ok) return jsonResponse({ error: validated.error }, 400);

  const client = serviceClient();

  let profile: Record<string, unknown>;
  try {
    profile = await userProfile(client, user.id);
  } catch {
    return jsonResponse({ error: "Member profile was not found." }, 403);
  }
  // A suspended or deactivated account cannot obtain upload authorization.
  const accountState = String(profile.accountState ?? "active").trim().toLowerCase();
  if (accountState !== "active") {
    return jsonResponse({ error: "This account cannot post reels right now." }, 403);
  }

  const nowIso = new Date().toISOString();

  // Rate limits, server-enforced: concurrent sessions and daily publishes.
  const { count: activeSessions } = await client
    .from("reel_upload_sessions")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .eq("status", "pending")
    .gt("expires_at", nowIso);
  if ((activeSessions ?? 0) >= REEL_LIMITS.maxActiveUploadSessions) {
    return jsonResponse(
      { error: "Finish or cancel your current reel upload first." },
      429,
    );
  }

  const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count: recentPublishes } = await client
    .from("reels")
    .select("id", { count: "exact", head: true })
    .eq("author_id", user.id)
    .gte("published_at", dayAgo);
  if ((recentPublishes ?? 0) >= REEL_LIMITS.maxPublishesPerDay) {
    return jsonResponse({ error: "You have reached today's reel limit." }, 429);
  }

  let config;
  try {
    config = r2ConfigFromEnv();
  } catch (error) {
    console.error("R2 configuration missing", error);
    return jsonResponse({ error: "Reel uploads are not configured." }, 500);
  }

  // The reel id and both object keys are generated here. A client never
  // proposes a path, so it cannot aim a write at another member's prefix.
  const reelId = crypto.randomUUID();
  const keys = reelObjectKeys(user.id, reelId);
  const churchId = profileChurchId(profile) || null;

  const { error: reelError } = await client.from("reels").insert({
    id: reelId,
    author_id: user.id,
    author_church_id: churchId,
    status: "uploading",
    video_object_key: keys.video,
    poster_object_key: keys.poster,
    mime_type: validated.value.videoContentType,
    duration_ms: validated.value.durationMs,
  });
  if (reelError) {
    console.error("Could not create reel row", reelError);
    return jsonResponse({ error: "Could not start this upload." }, 500);
  }

  const expiresAt = new Date(Date.now() + REEL_LIMITS.uploadUrlTtlSeconds * 1000);
  const { error: sessionError } = await client.from("reel_upload_sessions").insert({
    reel_id: reelId,
    user_id: user.id,
    video_object_key: keys.video,
    poster_object_key: keys.poster,
    declared_video_bytes: validated.value.videoBytes,
    declared_poster_bytes: validated.value.posterBytes,
    declared_duration_ms: validated.value.durationMs,
    status: "pending",
    expires_at: expiresAt.toISOString(),
  });
  if (sessionError) {
    console.error("Could not create upload session", sessionError);
    return jsonResponse({ error: "Could not start this upload." }, 500);
  }

  const [videoUploadUrl, posterUploadUrl] = await Promise.all([
    presignR2Url({
      config,
      method: "PUT",
      key: keys.video,
      expiresInSeconds: REEL_LIMITS.uploadUrlTtlSeconds,
      contentType: validated.value.videoContentType,
    }),
    presignR2Url({
      config,
      method: "PUT",
      key: keys.poster,
      expiresInSeconds: REEL_LIMITS.uploadUrlTtlSeconds,
      contentType: validated.value.posterContentType,
    }),
  ]);

  return jsonResponse({
    reel_id: reelId,
    video_upload_url: videoUploadUrl,
    poster_upload_url: posterUploadUrl,
    // The device must send exactly these, or the signature will not match.
    video_content_type: validated.value.videoContentType,
    poster_content_type: validated.value.posterContentType,
    expires_at: expiresAt.toISOString(),
  });
});
