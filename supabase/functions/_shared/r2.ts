// AWS SigV4 query-string presigning for Cloudflare R2.
//
// The bucket is private, so every byte transfer -- upload and playback --
// happens through a short-lived presigned URL minted here. This module is the
// only place R2 credentials are ever read, and it runs exclusively inside Edge
// Functions. Nothing it produces may be persisted: a signed URL is a bearer
// capability for whoever holds it until it expires.

const ENCODER = new TextEncoder();

export type R2Config = {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  bucket: string;
  endpoint: string;
};

/// Reads configuration from the function environment. Throws rather than
/// falling back to anything, so a missing secret fails loudly at the first
/// call instead of silently producing URLs that cannot work.
export function r2ConfigFromEnv(env = Deno.env): R2Config {
  const read = (name: string): string => {
    const value = (env.get(name) ?? "").trim();
    if (!value) throw new Error(`Missing required R2 configuration: ${name}`);
    return value;
  };
  const endpoint = read("R2_S3_ENDPOINT").replace(/\/+$/, "");
  if (!/^https:\/\//i.test(endpoint)) {
    throw new Error("R2_S3_ENDPOINT must be an https endpoint");
  }
  return {
    accountId: read("R2_ACCOUNT_ID"),
    accessKeyId: read("R2_ACCESS_KEY_ID"),
    secretAccessKey: read("R2_SECRET_ACCESS_KEY"),
    bucket: read("R2_BUCKET_NAME"),
    endpoint,
  };
}

function hex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function sha256Hex(value: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", ENCODER.encode(value)));
}

async function hmac(key: ArrayBuffer | Uint8Array, value: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return crypto.subtle.sign("HMAC", cryptoKey, ENCODER.encode(value));
}

/// RFC 3986 encoding. encodeURIComponent leaves !'()* unescaped, and AWS
/// requires them escaped; a mismatch here changes the canonical request and
/// produces a signature the server rejects.
export function rfc3986(value: string): string {
  return encodeURIComponent(value).replace(
    /[!'()*]/g,
    (char) => `%${char.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

/// Object keys keep their slashes: each segment is encoded independently.
function encodeKey(key: string): string {
  return key.split("/").map(rfc3986).join("/");
}

export type PresignOptions = {
  config: R2Config;
  method: "GET" | "PUT" | "HEAD" | "DELETE";
  key: string;
  expiresInSeconds: number;
  /// Signed for uploads so a presigned PUT cannot be reused to store a
  /// different kind of object than the one that was authorized.
  contentType?: string;
  now?: Date;
};

export async function presignR2Url(options: PresignOptions): Promise<string> {
  const { config, method, key, contentType } = options;
  const cleanKey = key.replace(/^\/+/, "");
  if (!cleanKey) throw new Error("An object key is required");
  const expires = Math.floor(options.expiresInSeconds);
  // AWS caps presigned URL lifetime at 7 days.
  if (!Number.isFinite(expires) || expires < 1 || expires > 604800) {
    throw new Error("Presigned URL expiry must be between 1 and 604800 seconds");
  }

  const now = options.now ?? new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);
  // R2 uses the fixed region "auto".
  const region = "auto";
  const service = "s3";
  const scope = `${dateStamp}/${region}/${service}/aws4_request`;

  const url = new URL(config.endpoint);
  const host = url.host;
  const canonicalUri = `/${encodeKey(config.bucket)}/${encodeKey(cleanKey)}`;

  const signedHeaderNames = contentType ? ["content-type", "host"] : ["host"];
  const canonicalHeaders = signedHeaderNames
    .map((name) =>
      name === "host" ? `host:${host}\n` : `content-type:${contentType!.trim()}\n`
    )
    .join("");
  const signedHeaders = signedHeaderNames.join(";");

  const query: Array<[string, string]> = [
    ["X-Amz-Algorithm", "AWS4-HMAC-SHA256"],
    ["X-Amz-Credential", `${config.accessKeyId}/${scope}`],
    ["X-Amz-Date", amzDate],
    ["X-Amz-Expires", String(expires)],
    ["X-Amz-SignedHeaders", signedHeaders],
  ];
  const canonicalQuery = query
    .map(([name, value]) => [rfc3986(name), rfc3986(value)] as const)
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : a[1] < b[1] ? -1 : 1))
    .map(([name, value]) => `${name}=${value}`)
    .join("&");

  const canonicalRequest = [
    method,
    canonicalUri,
    canonicalQuery,
    canonicalHeaders,
    signedHeaders,
    "UNSIGNED-PAYLOAD",
  ].join("\n");

  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    scope,
    await sha256Hex(canonicalRequest),
  ].join("\n");

  const kDate = await hmac(ENCODER.encode(`AWS4${config.secretAccessKey}`), dateStamp);
  const kRegion = await hmac(kDate, region);
  const kService = await hmac(kRegion, service);
  const kSigning = await hmac(kService, "aws4_request");
  const signature = hex(await hmac(kSigning, stringToSign));

  return `${url.origin}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}

/// Object keys are built server-side only. A client never proposes a key: a
/// caller-supplied path could otherwise overwrite another member's media.
export function reelObjectKeys(userId: string, reelId: string) {
  if (!/^[0-9a-f-]{36}$/i.test(reelId)) throw new Error("A reel id is required");
  const safeUser = userId.replace(/[^A-Za-z0-9_-]/g, "");
  if (!safeUser) throw new Error("A user id is required");
  return {
    video: `reels/${safeUser}/${reelId}/video.mp4`,
    poster: `reels/${safeUser}/${reelId}/poster.webp`,
  };
}
