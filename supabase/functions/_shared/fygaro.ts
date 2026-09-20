// Fygaro payment integration.
//
// Fygaro has no REST endpoint that creates a checkout. Instead a payment
// button is configured once in their dashboard and the amount is carried to
// it in the URL -- either as plain query parameters or as a signed JWT.
//
// This module only ever uses the JWT form. With `?amount=17.00` a church
// leader can edit the number in the address bar and pay whatever they like;
// with a JWT the amount is inside a payload signed by a secret that only the
// server holds, so tampering invalidates it.

export interface FygaroCheckoutConfig {
  buttonUrl: string;
  keyId: string;
  secret: string;
}

export interface FygaroWebhookConfig {
  /** Webhook signing secrets by `Fygaro-Key-ID`, so a key can be rotated. */
  secrets: Record<string, string>;
  /** Used when the header names a key id we have no specific secret for. */
  defaultSecret?: string;
}

const encoder = new TextEncoder();

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function hmacSha256(secret: string, message: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(message),
  );
  return new Uint8Array(signature);
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/**
 * Compares two strings without leaking, through timing, how long a common
 * prefix they share. A plain `===` on a signature lets an attacker recover it
 * one character at a time.
 */
export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/** Fygaro expects the amount as a decimal string, e.g. "100.01". */
export function formatFygaroAmount(amountMinor: number): string {
  if (!Number.isFinite(amountMinor) || amountMinor < 0) {
    throw new Error("A valid amount is required");
  }
  return (Math.round(amountMinor) / 100).toFixed(2);
}

export interface SignCheckoutOptions {
  config: FygaroCheckoutConfig;
  amountMinor: number;
  currency: string;
  customReference: string;
  expiresInSeconds?: number;
  now?: Date;
}

export async function signFygaroCheckoutJwt(
  options: SignCheckoutOptions,
): Promise<string> {
  const {
    config,
    amountMinor,
    currency,
    customReference,
    expiresInSeconds = 1800,
    now = new Date(),
  } = options;

  if (!config.keyId || !config.secret) {
    throw new Error("Fygaro checkout signing is not configured");
  }
  if (!customReference) {
    throw new Error("A custom reference is required");
  }

  const issuedAt = Math.floor(now.getTime() / 1000);
  const header = { alg: "HS256", typ: "JWT", kid: config.keyId };
  const payload = {
    amount: formatFygaroAmount(amountMinor),
    currency: currency.toUpperCase(),
    custom_reference: customReference,
    // nbf is backdated by a minute so a payment page opened against a server
    // whose clock runs slightly fast is not rejected as "not yet valid".
    nbf: issuedAt - 60,
    exp: issuedAt + expiresInSeconds,
  };

  const signingInput = [
    base64UrlEncode(encoder.encode(JSON.stringify(header))),
    base64UrlEncode(encoder.encode(JSON.stringify(payload))),
  ].join(".");
  const signature = await hmacSha256(config.secret, signingInput);
  return `${signingInput}.${base64UrlEncode(signature)}`;
}

export function buildFygaroCheckoutUrl(buttonUrl: string, jwt: string): string {
  if (!buttonUrl) throw new Error("Fygaro button URL is not configured");
  const url = new URL(buttonUrl);
  url.searchParams.set("jwt", jwt);
  return url.toString();
}

export interface ParsedFygaroSignature {
  timestamp: number;
  hashes: string[];
}

/**
 * Parses `Fygaro-Signature: t=1700000000,v1=abc...,v1=def...`
 *
 * More than one `v1` is legitimate: it is how a secret is rotated without
 * dropping webhooks mid-flight, so any one matching is enough.
 */
export function parseFygaroSignature(header: string): ParsedFygaroSignature {
  const parts = (header ?? "").split(",").map((part) => part.trim());
  let timestamp = Number.NaN;
  const hashes: string[] = [];

  for (const part of parts) {
    const separator = part.indexOf("=");
    if (separator <= 0) continue;
    const key = part.slice(0, separator).trim();
    const value = part.slice(separator + 1).trim();
    if (key === "t") timestamp = Number(value);
    else if (key === "v1" && value) hashes.push(value.toLowerCase());
  }

  if (!Number.isFinite(timestamp) || hashes.length === 0) {
    throw new Error("Malformed Fygaro signature header");
  }
  return { timestamp, hashes };
}

export interface VerifyWebhookOptions {
  config: FygaroWebhookConfig;
  signatureHeader: string;
  keyIdHeader?: string | null;
  rawBody: string;
  now?: Date;
  toleranceSeconds?: number;
}

/**
 * Verifies a Fygaro webhook. Throws with a specific reason rather than
 * returning false, so the caller can log why a payment notification was
 * rejected instead of guessing.
 */
export async function verifyFygaroWebhook(
  options: VerifyWebhookOptions,
): Promise<void> {
  const {
    config,
    signatureHeader,
    keyIdHeader,
    rawBody,
    now = new Date(),
    toleranceSeconds = 300,
  } = options;

  const { timestamp, hashes } = parseFygaroSignature(signatureHeader);

  // Replay protection. A signature stays valid forever otherwise, so a
  // captured "payment succeeded" could be replayed to extend a subscription.
  const ageSeconds = Math.abs(Math.floor(now.getTime() / 1000) - timestamp);
  if (ageSeconds > toleranceSeconds) {
    throw new Error("Fygaro signature timestamp is outside the allowed window");
  }

  const keyId = (keyIdHeader ?? "").trim();
  const secret = (keyId && config.secrets[keyId]) || config.defaultSecret;
  if (!secret) {
    throw new Error("No Fygaro webhook secret is configured for this key id");
  }

  const expected = toHex(await hmacSha256(secret, `${timestamp}.${rawBody}`));
  const matched = hashes.some((hash) => timingSafeEqual(hash, expected));
  if (!matched) {
    throw new Error("Fygaro signature did not match");
  }
}

export function fygaroCheckoutConfigFromEnv(): FygaroCheckoutConfig {
  const buttonUrl = Deno.env.get("FYGARO_BUTTON_URL") ?? "";
  const keyId = Deno.env.get("FYGARO_KEY_ID") ?? "";
  const secret = Deno.env.get("FYGARO_SECRET_KEY") ?? "";
  if (!buttonUrl || !keyId || !secret) {
    throw new Error(
      "Fygaro is not configured. Set FYGARO_BUTTON_URL, FYGARO_KEY_ID and FYGARO_SECRET_KEY.",
    );
  }
  return { buttonUrl, keyId, secret };
}

export function fygaroWebhookConfigFromEnv(): FygaroWebhookConfig {
  const raw = Deno.env.get("FYGARO_WEBHOOK_SECRETS") ?? "";
  let secrets: Record<string, string> = {};
  if (raw.trim()) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === "object") {
        secrets = parsed as Record<string, string>;
      }
    } catch (_) {
      // A malformed rotation map must not silently disable verification --
      // the default secret below still applies, and a missing secret throws.
    }
  }
  const defaultSecret = Deno.env.get("FYGARO_WEBHOOK_SECRET") ?? undefined;
  if (!defaultSecret && Object.keys(secrets).length === 0) {
    throw new Error(
      "Fygaro webhook verification is not configured. Set FYGARO_WEBHOOK_SECRET.",
    );
  }
  return { secrets, defaultSecret };
}

export interface FygaroWebhookPayload {
  transactionId?: string;
  reference?: string;
  customReference?: string | null;
  authCode?: string | null;
  currency?: string;
  amount?: string;
  createdAt?: string;
  client?: { name?: string; email?: string; phone?: string } | null;
  card?: Record<string, unknown> | null;
}

export interface NormalizedFygaroPayment {
  transactionId: string;
  customReference: string | null;
  currency: string;
  amountMinor: number;
  paidAt: Date;
  customerEmail: string | null;
}

export function normalizeFygaroPayment(
  payload: FygaroWebhookPayload,
): NormalizedFygaroPayment {
  const transactionId = (payload.transactionId ?? "").trim();
  if (!transactionId) {
    throw new Error("Fygaro payload has no transactionId");
  }
  const amount = Number(payload.amount);
  if (!Number.isFinite(amount) || amount < 0) {
    throw new Error("Fygaro payload has no usable amount");
  }
  const parsedDate = payload.createdAt ? new Date(payload.createdAt) : null;
  return {
    transactionId,
    customReference: (payload.customReference ?? "").trim() || null,
    currency: (payload.currency ?? "").trim().toUpperCase(),
    amountMinor: Math.round(amount * 100),
    paidAt: parsedDate && !Number.isNaN(parsedDate.getTime())
      ? parsedDate
      : new Date(),
    customerEmail: (payload.client?.email ?? "").trim() || null,
  };
}

/**
 * A monthly subscription period. Fygaro reports a payment, not a billing
 * period, so the period the payment buys is derived here.
 */
export function monthlyPeriodFrom(start: Date): { start: Date; end: Date } {
  const end = new Date(start.getTime());
  const day = end.getUTCDate();
  end.setUTCMonth(end.getUTCMonth() + 1);
  // Rolling 31 Jan forward lands on 3 March in a non-leap year, which would
  // quietly give the church two extra days every time. Clamp to the last day
  // of the target month instead.
  if (end.getUTCDate() !== day) end.setUTCDate(0);
  return { start, end };
}
