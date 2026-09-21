import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildFygaroCheckoutUrl,
  formatFygaroAmount,
  fygaroPaymentConfigFromEnv,
  monthlyPeriodFrom,
  normalizeFygaroPayment,
  parseFygaroSignature,
  signFygaroCheckoutJwt,
  timingSafeEqual,
  verifyFygaroWebhook,
} from "./fygaro.ts";

const checkoutConfig = {
  buttonUrl: "https://www.fygaro.com/en/pb/00000000-0000-0000-0000-000000000000",
  keyId: "test-key",
  secret: "test-secret",
};

Deno.test('checkout requires a usable webhook verifier as well as payment keys', () => {
  const env: Record<string, string> = {
    FYGARO_BUTTON_URL: checkoutConfig.buttonUrl,
    FYGARO_KEY_ID: checkoutConfig.keyId,
    FYGARO_SECRET_KEY: checkoutConfig.secret,
  };
  const read = (key: string) => env[key];
  assertThrows(() => fygaroPaymentConfigFromEnv(read), Error, 'webhook verification is not configured');
  env.FYGARO_WEBHOOK_SECRETS = '{"empty":"","invalid":3}';
  assertThrows(() => fygaroPaymentConfigFromEnv(read), Error, 'webhook verification is not configured');
  env.FYGARO_WEBHOOK_SECRET = 'test-hook-secret';
  assertEquals(fygaroPaymentConfigFromEnv(read), checkoutConfig);
  env.FYGARO_BUTTON_URL = 'http://insecure.example/pay';
  assertThrows(() => fygaroPaymentConfigFromEnv(read), Error, 'HTTPS');
});

function decodeSegment(segment: string): Record<string, unknown> {
  const padded = segment.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(padded + "=".repeat((4 - padded.length % 4) % 4)));
}

/** Independent HMAC so the tests do not verify the module against itself. */
async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)),
  );
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("amounts are formatted as Fygaro's two-decimal strings", () => {
  assertEquals(formatFygaroAmount(1700), "17.00");
  assertEquals(formatFygaroAmount(268900), "2689.00");
  assertEquals(formatFygaroAmount(10001), "100.01");
  assertEquals(formatFygaroAmount(0), "0.00");
  assertThrows(() => formatFygaroAmount(-1));
  assertThrows(() => formatFygaroAmount(Number.NaN));
});

Deno.test("checkout JWT carries the signed amount, currency and reference", async () => {
  const now = new Date("2026-09-20T12:00:00Z");
  const jwt = await signFygaroCheckoutJwt({
    config: checkoutConfig,
    amountMinor: 1700,
    currency: "usd",
    customReference: "session-abc",
    now,
  });

  const [headerSegment, payloadSegment, signature] = jwt.split(".");
  const header = decodeSegment(headerSegment);
  const payload = decodeSegment(payloadSegment);

  assertEquals(header.alg, "HS256");
  assertEquals(header.kid, "test-key");
  assertEquals(payload.amount, "17.00");
  assertEquals(payload.currency, "USD");
  assertEquals(payload.custom_reference, "session-abc");

  // The signature must be over the exact header.payload string.
  const expected = await hmacHex(
    checkoutConfig.secret,
    `${headerSegment}.${payloadSegment}`,
  );
  const actualHex = Array.from(
    atob(signature.replace(/-/g, "+").replace(/_/g, "/")),
  )
    .map((c) => c.charCodeAt(0).toString(16).padStart(2, "0"))
    .join("");
  assertEquals(actualHex, expected);
});

Deno.test("checkout JWT expires and is not valid before it is issued", async () => {
  const now = new Date("2026-09-20T12:00:00Z");
  const issuedAt = Math.floor(now.getTime() / 1000);
  const jwt = await signFygaroCheckoutJwt({
    config: checkoutConfig,
    amountMinor: 1700,
    currency: "USD",
    customReference: "session-abc",
    expiresInSeconds: 900,
    now,
  });
  const payload = decodeSegment(jwt.split(".")[1]);
  assertEquals(payload.exp, issuedAt + 900);
  assertEquals(payload.nbf, issuedAt - 60);
});

Deno.test("checkout requires configuration and a reference", async () => {
  await assertRejects(() =>
    signFygaroCheckoutJwt({
      config: { ...checkoutConfig, secret: "" },
      amountMinor: 1700,
      currency: "USD",
      customReference: "abc",
    })
  );
  await assertRejects(() =>
    signFygaroCheckoutJwt({
      config: checkoutConfig,
      amountMinor: 1700,
      currency: "USD",
      customReference: "",
    })
  );
});

Deno.test("checkout URL keeps the button path and adds the jwt", () => {
  const url = buildFygaroCheckoutUrl(checkoutConfig.buttonUrl, "a.b.c");
  assertEquals(
    url,
    `${checkoutConfig.buttonUrl}?jwt=a.b.c`,
  );
});

Deno.test("signature header parsing accepts several v1 hashes", () => {
  const parsed = parseFygaroSignature("t=1700000000,v1=aaa,v1=BBB");
  assertEquals(parsed.timestamp, 1700000000);
  assertEquals(parsed.hashes, ["aaa", "bbb"]);
  assertThrows(() => parseFygaroSignature("t=1700000000"));
  assertThrows(() => parseFygaroSignature("v1=aaa"));
  assertThrows(() => parseFygaroSignature(""));
});

Deno.test("a correctly signed webhook verifies", async () => {
  const now = new Date("2026-09-20T12:00:00Z");
  const timestamp = Math.floor(now.getTime() / 1000);
  const rawBody = JSON.stringify({ transactionId: "tx-1", amount: "17.00" });
  const hash = await hmacHex("hook-secret", `${timestamp}.${rawBody}`);

  await verifyFygaroWebhook({
    config: { secrets: { "hook-key": "hook-secret" } },
    signatureHeader: `t=${timestamp},v1=${hash}`,
    keyIdHeader: "hook-key",
    rawBody,
    now,
  });
});

Deno.test("a tampered body fails verification", async () => {
  const now = new Date("2026-09-20T12:00:00Z");
  const timestamp = Math.floor(now.getTime() / 1000);
  const hash = await hmacHex("hook-secret", `${timestamp}.{"amount":"17.00"}`);

  await assertRejects(
    () =>
      verifyFygaroWebhook({
        config: { secrets: { "hook-key": "hook-secret" } },
        signatureHeader: `t=${timestamp},v1=${hash}`,
        keyIdHeader: "hook-key",
        // The attacker's amount, signed for the original one.
        rawBody: '{"amount":"1700.00"}',
        now,
      }),
    Error,
    "did not match",
  );
});

Deno.test("an old signature is rejected as a replay", async () => {
  const signedAt = new Date("2026-09-20T12:00:00Z");
  const timestamp = Math.floor(signedAt.getTime() / 1000);
  const rawBody = '{"transactionId":"tx-1"}';
  const hash = await hmacHex("hook-secret", `${timestamp}.${rawBody}`);

  await assertRejects(
    () =>
      verifyFygaroWebhook({
        config: { secrets: { "hook-key": "hook-secret" } },
        signatureHeader: `t=${timestamp},v1=${hash}`,
        keyIdHeader: "hook-key",
        rawBody,
        // Six minutes later: past the 300 second window.
        now: new Date("2026-09-20T12:06:00Z"),
      }),
    Error,
    "outside the allowed window",
  );
});

Deno.test("an unknown key id falls back to the default secret", async () => {
  const now = new Date("2026-09-20T12:00:00Z");
  const timestamp = Math.floor(now.getTime() / 1000);
  const rawBody = '{"transactionId":"tx-1"}';
  const hash = await hmacHex("fallback", `${timestamp}.${rawBody}`);

  await verifyFygaroWebhook({
    config: { secrets: {}, defaultSecret: "fallback" },
    signatureHeader: `t=${timestamp},v1=${hash}`,
    keyIdHeader: "rotated-away",
    rawBody,
    now,
  });
});

Deno.test("verification fails when no secret is configured", async () => {
  const now = new Date("2026-09-20T12:00:00Z");
  const timestamp = Math.floor(now.getTime() / 1000);
  await assertRejects(
    () =>
      verifyFygaroWebhook({
        config: { secrets: {} },
        signatureHeader: `t=${timestamp},v1=abc`,
        keyIdHeader: "any",
        rawBody: "{}",
        now,
      }),
    Error,
    "No Fygaro webhook secret",
  );
});

Deno.test("timing safe comparison still compares correctly", () => {
  assertEquals(timingSafeEqual("abc", "abc"), true);
  assertEquals(timingSafeEqual("abc", "abd"), false);
  assertEquals(timingSafeEqual("abc", "abcd"), false);
  assertEquals(timingSafeEqual("", ""), true);
});

Deno.test("payment payloads normalise to minor units", () => {
  const payment = normalizeFygaroPayment({
    transactionId: "tx-9",
    customReference: " session-1 ",
    currency: "jmd",
    amount: "2689.00",
    createdAt: "2026-09-20T12:00:00Z",
    client: { email: "pastor@example.com" },
  });
  assertEquals(payment.transactionId, "tx-9");
  assertEquals(payment.customReference, "session-1");
  assertEquals(payment.currency, "JMD");
  assertEquals(payment.amountMinor, 268900);
  assertEquals(payment.customerEmail, "pastor@example.com");
  assertEquals(payment.paidAt.toISOString(), "2026-09-20T12:00:00.000Z");
});

Deno.test("a payload without a transaction id or amount is rejected", () => {
  assertThrows(() => normalizeFygaroPayment({ amount: "1.00" }));
  assertThrows(() => normalizeFygaroPayment({ transactionId: "tx" }));
});

Deno.test("a monthly period does not overshoot a short month", () => {
  const fromJan31 = monthlyPeriodFrom(new Date("2026-01-31T00:00:00Z"));
  assertEquals(fromJan31.end.toISOString(), "2026-02-28T00:00:00.000Z");

  const fromMar15 = monthlyPeriodFrom(new Date("2026-03-15T00:00:00Z"));
  assertEquals(fromMar15.end.toISOString(), "2026-04-15T00:00:00.000Z");

  const leapYear = monthlyPeriodFrom(new Date("2028-01-31T00:00:00Z"));
  assertEquals(leapYear.end.toISOString(), "2028-02-29T00:00:00.000Z");
});

Deno.test('malformed monetary values cannot be rounded into a valid payment', () => {
  const valid = { transactionId: 'tx', currency: 'USD', amount: '17.00', createdAt: '2026-09-20T12:00:00Z' };
  for (const amount of ['', ' ', '0.00', '-1.00', '1e3', '17.001', '0x11', 'NaN']) {
    assertThrows(() => normalizeFygaroPayment({ ...valid, amount }));
  }
  assertThrows(() => normalizeFygaroPayment({ ...valid, createdAt: 'invalid' }));
  assertThrows(() => normalizeFygaroPayment({ ...valid, currency: '' }));
  assertThrows(() => formatFygaroAmount(1700.5));
});

Deno.test('checkout never sends the signed price to an insecure URL', () => {
  assertThrows(() => buildFygaroCheckoutUrl('http://example.org/pay', 'signed'));
  assertThrows(() => buildFygaroCheckoutUrl('https://user:pass@example.org/pay', 'signed'));
});
