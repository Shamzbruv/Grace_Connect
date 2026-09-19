import {
  parsePlaybackBatch,
  REEL_LIMITS,
  validatePublishRequest,
  validateUploadRequest,
  verifyUploadedObject,
} from "./reel_validation.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const validUpload = {
  video_content_type: "video/mp4",
  video_size: 12_000_000,
  poster_content_type: "image/webp",
  poster_size: 120_000,
  duration_ms: 43_820,
};

Deno.test("a well-formed upload request is accepted", () => {
  const result = validateUploadRequest(validUpload);
  assert(result.ok, "valid request accepted");
  if (result.ok) assert(result.value.durationMs === 43_820, "duration carried");
});

Deno.test("upload limits are enforced server side", () => {
  const cases: Array<[Record<string, unknown>, string]> = [
    [{ ...validUpload, video_content_type: "video/quicktime" }, "non-MP4 video"],
    [{ ...validUpload, poster_content_type: "image/gif" }, "unsupported poster type"],
    [{ ...validUpload, video_size: REEL_LIMITS.maxVideoBytes + 1 }, "oversized video"],
    [{ ...validUpload, poster_size: REEL_LIMITS.maxPosterBytes + 1 }, "oversized poster"],
    [{ ...validUpload, duration_ms: REEL_LIMITS.maxDurationMs + 1 }, "over 60 seconds"],
    [{ ...validUpload, duration_ms: 10 }, "too short"],
    [{ ...validUpload, video_size: 0 }, "zero size"],
    [{ ...validUpload, video_size: -5 }, "negative size"],
    [{ ...validUpload, video_size: 1.5 }, "fractional size"],
    [{ ...validUpload, duration_ms: "abc" }, "non-numeric duration"],
    [{}, "empty body"],
  ];
  for (const [body, label] of cases) {
    assert(!validateUploadRequest(body).ok, `${label} must be rejected`);
  }
});

Deno.test("publish requests validate the reel id, category and visibility", () => {
  const ok = validatePublishRequest({
    reel_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    caption: "Praise report",
    category: "testimony",
    visibility: "followers",
  });
  assert(ok.ok, "valid publish accepted");

  assert(!validatePublishRequest({ reel_id: "nope" }).ok, "bad uuid rejected");
  assert(
    !validatePublishRequest({
      reel_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      category: "not_a_category",
    }).ok,
    "unknown category rejected",
  );
  assert(
    !validatePublishRequest({
      reel_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      visibility: "everyone",
    }).ok,
    "unknown visibility rejected",
  );
  assert(
    !validatePublishRequest({
      reel_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      caption: "x".repeat(REEL_LIMITS.maxCaptionLength + 1),
    }).ok,
    "overlong caption rejected",
  );
});

Deno.test("a playback batch is bounded and de-duplicated", () => {
  const id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
  const duped = parsePlaybackBatch({ reel_ids: [id, id, id] });
  assert(duped.ok && duped.value.length === 1, "repeated ids collapse to one");

  const many = Array.from(
    { length: REEL_LIMITS.maxPlaybackBatch + 1 },
    (_, i) => `aaaaaaaa-bbbb-cccc-dddd-${String(i).padStart(12, "0")}`,
  );
  assert(!parsePlaybackBatch({ reel_ids: many }).ok, "oversized batch rejected");
  assert(!parsePlaybackBatch({ reel_ids: [] }).ok, "empty batch rejected");
  assert(!parsePlaybackBatch({ reel_ids: ["../etc/passwd"] }).ok, "non-uuid rejected");
  assert(!parsePlaybackBatch({}).ok, "missing ids rejected");
});

Deno.test("finalize verifies only what R2 can actually prove", () => {
  const base = {
    exists: true,
    contentLength: 12_000_000,
    contentType: "video/mp4",
    allowedTypes: ["video/mp4"],
    maxBytes: REEL_LIMITS.maxVideoBytes,
    declaredBytes: 12_000_000,
    label: "video",
  };
  assert(verifyUploadedObject(base).ok, "a matching object is accepted");
  assert(!verifyUploadedObject({ ...base, exists: false }).ok, "missing object rejected");
  assert(!verifyUploadedObject({ ...base, contentLength: 0 }).ok, "empty object rejected");
  assert(
    !verifyUploadedObject({ ...base, contentLength: REEL_LIMITS.maxVideoBytes + 1 }).ok,
    "oversized object rejected",
  );
  // A different file swapped in against the same presigned PUT.
  assert(
    !verifyUploadedObject({ ...base, contentLength: 999_999 }).ok,
    "size mismatch against the authorized upload is rejected",
  );
  assert(
    !verifyUploadedObject({ ...base, contentType: "application/zip" }).ok,
    "unexpected stored type rejected",
  );
  // Content-Type may carry parameters, and R2 may omit it entirely.
  assert(
    verifyUploadedObject({ ...base, contentType: "video/mp4; charset=utf-8" }).ok,
    "content type parameters tolerated",
  );
  assert(verifyUploadedObject({ ...base, contentType: null }).ok, "absent type tolerated");
});
