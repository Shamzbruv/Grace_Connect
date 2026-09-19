import { presignR2Url, reelObjectKeys, rfc3986 } from "./r2.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

const TEST_CONFIG = {
  accountId: "438c47210da0c3920e0f7dacd46bbe49",
  accessKeyId: "AKIAIOSFODNN7EXAMPLE",
  // Well-known AWS documentation example key. Not a real credential.
  secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  bucket: "reel-grace-videos",
  endpoint: "https://438c47210da0c3920e0f7dacd46bbe49.r2.cloudflarestorage.com",
};

// Cross-checked against an independently written SigV4 implementation that
// reproduces AWS's own published presigned-URL example
// (aeeed9bb...d404) exactly. If this value changes, the signing changed and
// R2 will reject the URL.
Deno.test("presigned GET matches an independently verified SigV4 signature", async () => {
  const url = await presignR2Url({
    config: TEST_CONFIG,
    method: "GET",
    key: "reels/user1/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/video.mp4",
    expiresInSeconds: 1800,
    now: new Date("2026-09-19T00:00:00Z"),
  });
  const signature = new URL(url).searchParams.get("X-Amz-Signature");
  assert(
    signature ===
      "28b50b376e3aac312131110f3b523a07eb5e544e79434ec41614fca09516c228",
    `unexpected signature: ${signature}`,
  );
});

Deno.test("a presigned URL carries every parameter R2 needs and no payload hash", async () => {
  const url = new URL(
    await presignR2Url({
      config: TEST_CONFIG,
      method: "GET",
      key: "reels/user1/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/video.mp4",
      expiresInSeconds: 1800,
    }),
  );
  assert(url.origin === TEST_CONFIG.endpoint, "signs against the R2 endpoint");
  assert(
    url.pathname === "/reel-grace-videos/reels/user1/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/video.mp4",
    "path-style bucket addressing",
  );
  assert(url.searchParams.get("X-Amz-Algorithm") === "AWS4-HMAC-SHA256", "algorithm");
  assert(
    url.searchParams.get("X-Amz-Credential")!.includes("/auto/s3/aws4_request"),
    "R2 signs with region auto",
  );
  assert(url.searchParams.get("X-Amz-Expires") === "1800", "expiry carried");
  assert(url.searchParams.get("X-Amz-SignedHeaders") === "host", "host is signed");
  assert(!!url.searchParams.get("X-Amz-Signature"), "signature present");
  // The secret must never appear in a URL that reaches a device.
  assert(!url.toString().includes(TEST_CONFIG.secretAccessKey), "secret never leaks into the URL");
});

Deno.test("an upload signs Content-Type so a PUT cannot store a different kind of object", async () => {
  const withType = new URL(
    await presignR2Url({
      config: TEST_CONFIG,
      method: "PUT",
      key: "reels/user1/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/video.mp4",
      expiresInSeconds: 600,
      contentType: "video/mp4",
      now: new Date("2026-09-19T00:00:00Z"),
    }),
  );
  assert(
    withType.searchParams.get("X-Amz-SignedHeaders") === "content-type;host",
    "content-type is part of the signature",
  );
  const withoutType = new URL(
    await presignR2Url({
      config: TEST_CONFIG,
      method: "PUT",
      key: "reels/user1/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/video.mp4",
      expiresInSeconds: 600,
      now: new Date("2026-09-19T00:00:00Z"),
    }),
  );
  assert(
    withType.searchParams.get("X-Amz-Signature") !==
      withoutType.searchParams.get("X-Amz-Signature"),
    "signing content-type must change the signature",
  );
});

Deno.test("expiry bounds are enforced", async () => {
  for (const seconds of [0, -1, 604801]) {
    let rejected = false;
    try {
      await presignR2Url({
        config: TEST_CONFIG,
        method: "GET",
        key: "reels/a/b/video.mp4",
        expiresInSeconds: seconds,
      });
    } catch {
      rejected = true;
    }
    assert(rejected, `expiry ${seconds} must be rejected`);
  }
});

Deno.test("object keys are server-derived and cannot be steered by the caller", () => {
  const keys = reelObjectKeys("user-1", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
  assert(
    keys.video === "reels/user-1/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/video.mp4",
    "video key layout",
  );
  assert(keys.poster.endsWith("/poster.webp"), "poster key layout");

  // A traversal attempt in the user id must not escape the prefix.
  const hostile = reelObjectKeys("../../other", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
  assert(!hostile.video.includes(".."), "path traversal stripped from the key");
  assert(hostile.video.startsWith("reels/"), "key stays under the reels prefix");

  let rejected = false;
  try {
    reelObjectKeys("user-1", "not-a-uuid");
  } catch {
    rejected = true;
  }
  assert(rejected, "a non-uuid reel id is rejected");
});

Deno.test("rfc3986 escapes the characters encodeURIComponent leaves behind", () => {
  assert(rfc3986("a!b'c(d)e*f") === "a%21b%27c%28d%29e%2Af", "reserved characters escaped");
  assert(rfc3986("a b") === "a%20b", "spaces escaped");
});
