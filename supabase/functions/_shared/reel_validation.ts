// Server-side limits for Reel Grace uploads.
//
// These are enforced on the server because Flutter validation is a
// convenience, not a control: the upload request is an HTTP call anyone
// holding a session token can make directly.
//
// Note what is deliberately NOT here. An R2 HEAD proves an object exists,
// its byte size, and the content type the uploader set. It cannot parse the
// MP4 container, so duration, codec, dimensions and faststart are
// client-declared. They are range-checked for sanity and stored for layout,
// but they are never a security boundary. See docs/launch_reel_grace_plan.md.

export const REEL_LIMITS = {
  maxVideoBytes: 25 * 1024 * 1024,
  maxPosterBytes: 500 * 1024,
  maxDurationMs: 60_000,
  minDurationMs: 500,
  maxActiveUploadSessions: 3,
  maxPublishesPerDay: 10,
  uploadUrlTtlSeconds: 600,
  playbackUrlTtlSeconds: 1800,
  maxPlaybackBatch: 20,
  maxCaptionLength: 2200,
} as const;

export const ALLOWED_VIDEO_TYPES = ["video/mp4"] as const;
export const ALLOWED_POSTER_TYPES = ["image/webp", "image/jpeg"] as const;

export const REEL_CATEGORIES = [
  "testimony", "worship", "word", "encouragement", "bible_study", "youth",
  "church_moment", "ministry", "relationships", "motivation", "other",
] as const;

export const REEL_VISIBILITIES = ["public", "followers", "church"] as const;

export type UploadRequest = {
  videoContentType: string;
  videoBytes: number;
  posterContentType: string;
  posterBytes: number;
  durationMs: number;
};

export type ValidationResult<T> =
  | { ok: true; value: T }
  | { ok: false; error: string };

function positiveInt(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(parsed) || !Number.isInteger(parsed) || parsed <= 0) {
    return null;
  }
  return parsed;
}

export function validateUploadRequest(body: unknown): ValidationResult<UploadRequest> {
  const input = (body ?? {}) as Record<string, unknown>;
  const videoContentType = String(input.video_content_type ?? "").trim().toLowerCase();
  const posterContentType = String(input.poster_content_type ?? "").trim().toLowerCase();

  if (!(ALLOWED_VIDEO_TYPES as readonly string[]).includes(videoContentType)) {
    return { ok: false, error: "Reels must be uploaded as MP4 video." };
  }
  if (!(ALLOWED_POSTER_TYPES as readonly string[]).includes(posterContentType)) {
    return { ok: false, error: "A reel cover must be a WebP or JPEG image." };
  }

  const videoBytes = positiveInt(input.video_size);
  if (videoBytes === null) return { ok: false, error: "A video size is required." };
  if (videoBytes > REEL_LIMITS.maxVideoBytes) {
    return { ok: false, error: "That video is larger than the 25 MB reel limit." };
  }

  const posterBytes = positiveInt(input.poster_size);
  if (posterBytes === null) return { ok: false, error: "A cover image size is required." };
  if (posterBytes > REEL_LIMITS.maxPosterBytes) {
    return { ok: false, error: "That cover image is larger than the 500 KB limit." };
  }

  const durationMs = positiveInt(input.duration_ms);
  if (durationMs === null) return { ok: false, error: "A reel duration is required." };
  if (durationMs < REEL_LIMITS.minDurationMs) {
    return { ok: false, error: "That reel is too short to publish." };
  }
  if (durationMs > REEL_LIMITS.maxDurationMs) {
    return { ok: false, error: "Reels can be at most 60 seconds long." };
  }

  return {
    ok: true,
    value: { videoContentType, videoBytes, posterContentType, posterBytes, durationMs },
  };
}

export type PublishRequest = {
  reelId: string;
  caption: string;
  category: string;
  visibility: string;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function validatePublishRequest(body: unknown): ValidationResult<PublishRequest> {
  const input = (body ?? {}) as Record<string, unknown>;
  const reelId = String(input.reel_id ?? "").trim();
  if (!UUID_PATTERN.test(reelId)) return { ok: false, error: "A reel id is required." };

  const caption = String(input.caption ?? "").trim();
  if (caption.length > REEL_LIMITS.maxCaptionLength) {
    return { ok: false, error: "That caption is too long." };
  }

  const category = String(input.category ?? "other").trim().toLowerCase();
  if (!(REEL_CATEGORIES as readonly string[]).includes(category)) {
    return { ok: false, error: "Choose a category for this reel." };
  }

  const visibility = String(input.visibility ?? "public").trim().toLowerCase();
  if (!(REEL_VISIBILITIES as readonly string[]).includes(visibility)) {
    return { ok: false, error: "Choose who can see this reel." };
  }

  return { ok: true, value: { reelId, caption, category, visibility } };
}

/// A batch of reel ids to sign. Bounded so one call cannot be turned into a
/// bulk signing oracle, and de-duplicated so a repeated id cannot inflate it.
export function parsePlaybackBatch(body: unknown): ValidationResult<string[]> {
  const input = (body ?? {}) as Record<string, unknown>;
  const raw = input.reel_ids;
  if (!Array.isArray(raw) || raw.length === 0) {
    return { ok: false, error: "At least one reel id is required." };
  }
  const ids: string[] = [];
  for (const entry of raw) {
    const id = String(entry ?? "").trim();
    if (!UUID_PATTERN.test(id)) return { ok: false, error: "A reel id was not valid." };
    if (!ids.includes(id)) ids.push(id);
  }
  if (ids.length > REEL_LIMITS.maxPlaybackBatch) {
    return { ok: false, error: "Too many reels were requested at once." };
  }
  return { ok: true, value: ids };
}

/// What finalize can actually prove from an R2 HEAD. Anything about the media
/// itself (duration, codec, faststart) is explicitly out of scope.
export function verifyUploadedObject(options: {
  exists: boolean;
  contentLength: number | null;
  contentType: string | null;
  allowedTypes: readonly string[];
  maxBytes: number;
  declaredBytes: number;
  label: string;
}): ValidationResult<{ bytes: number }> {
  const { exists, contentLength, contentType, allowedTypes, maxBytes, declaredBytes, label } =
    options;
  if (!exists) return { ok: false, error: `The ${label} was not uploaded.` };
  if (contentLength === null || contentLength <= 0) {
    return { ok: false, error: `The ${label} upload was empty.` };
  }
  if (contentLength > maxBytes) {
    return { ok: false, error: `The ${label} is larger than its limit.` };
  }
  // The stored object must be the one that was authorized, not a different
  // file swapped in against the same presigned PUT.
  if (Math.abs(contentLength - declaredBytes) > 1024) {
    return { ok: false, error: `The ${label} does not match the requested upload.` };
  }
  const type = (contentType ?? "").split(";")[0].trim().toLowerCase();
  if (type && !allowedTypes.includes(type)) {
    return { ok: false, error: `The ${label} was stored with an unexpected type.` };
  }
  return { ok: true, value: { bytes: contentLength } };
}
