// Publishes a reel after its media has landed in R2.
//
// What this can verify is limited by what an R2 HEAD returns: existence,
// byte size, and the stored content type. It cannot parse the MP4, so it
// does not claim to validate duration, codec or faststart -- those stay
// client-declared. See docs/launch_reel_grace_plan.md.
import {
  authenticatedUser,
  handleOptions,
  jsonResponse,
  serviceClient,
} from "../_shared/grace.ts";
import { presignR2Url, r2ConfigFromEnv } from "../_shared/r2.ts";
import {
  ALLOWED_POSTER_TYPES,
  ALLOWED_VIDEO_TYPES,
  REEL_LIMITS,
  validatePublishRequest,
  verifyUploadedObject,
} from "../_shared/reel_validation.ts";

async function headObject(config: ReturnType<typeof r2ConfigFromEnv>, key: string) {
  const url = await presignR2Url({
    config,
    method: "HEAD",
    key,
    expiresInSeconds: 60,
  });
  const response = await fetch(url, { method: "HEAD" });
  if (!response.ok) return { exists: false, contentLength: null, contentType: null };
  const length = response.headers.get("content-length");
  return {
    exists: true,
    contentLength: length === null ? null : Number(length),
    contentType: response.headers.get("content-type"),
  };
}

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
  const validated = validatePublishRequest(body);
  if (!validated.ok) return jsonResponse({ error: validated.error }, 400);

  const client = serviceClient();
  const { data: session } = await client
    .from("reel_upload_sessions")
    .select("*")
    .eq("reel_id", validated.value.reelId)
    .maybeSingle();

  // Ownership is checked against the session, not against anything the
  // caller sent, so one member cannot finalize another member's upload.
  if (!session || String(session.user_id) !== user.id) {
    return jsonResponse({ error: "That upload was not found." }, 404);
  }
  if (session.status === "completed") {
    return jsonResponse({ error: "That reel was already published." }, 409);
  }
  if (new Date(String(session.expires_at)).getTime() < Date.now()) {
    await client.from("reel_upload_sessions").update({ status: "expired" })
      .eq("id", session.id);
    return jsonResponse({ error: "That upload expired. Please try again." }, 410);
  }

  let config;
  try {
    config = r2ConfigFromEnv();
  } catch (error) {
    console.error("R2 configuration missing", error);
    return jsonResponse({ error: "Reel uploads are not configured." }, 500);
  }

  const [video, poster] = await Promise.all([
    headObject(config, String(session.video_object_key)),
    headObject(config, String(session.poster_object_key)),
  ]);

  const videoCheck = verifyUploadedObject({
    ...video,
    allowedTypes: ALLOWED_VIDEO_TYPES,
    maxBytes: REEL_LIMITS.maxVideoBytes,
    declaredBytes: Number(session.declared_video_bytes ?? 0),
    label: "video",
  });
  if (!videoCheck.ok) return jsonResponse({ error: videoCheck.error }, 400);

  const posterCheck = verifyUploadedObject({
    ...poster,
    allowedTypes: ALLOWED_POSTER_TYPES,
    maxBytes: REEL_LIMITS.maxPosterBytes,
    declaredBytes: Number(session.declared_poster_bytes ?? 0),
    label: "cover image",
  });
  if (!posterCheck.ok) return jsonResponse({ error: posterCheck.error }, 400);

  const { error: publishError } = await client
    .from("reels")
    .update({
      caption: validated.value.caption || null,
      category: validated.value.category,
      visibility: validated.value.visibility,
      status: "ready",
      file_size_bytes: videoCheck.value.bytes,
      published_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", validated.value.reelId)
    .eq("author_id", user.id);
  if (publishError) {
    console.error("Could not publish reel", publishError);
    return jsonResponse({ error: "Could not publish this reel." }, 500);
  }

  await client
    .from("reel_upload_sessions")
    .update({ status: "completed", completed_at: new Date().toISOString() })
    .eq("id", session.id);

  return jsonResponse({ reel_id: validated.value.reelId, status: "ready" });
});
