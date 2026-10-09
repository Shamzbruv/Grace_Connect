import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  loadFygaroConfiguration,
  parseFygaroConfiguration,
  requireFygaroCheckout,
} from "./fygaro_configuration.ts";
const credentials = {
  button_url: "https://www.fygaro.com/en/pb/example",
  key_id: "checkout-key",
  secret_key: "test-checkout-secret",
  webhook_key_id: "hook-key",
  webhook_secret_key: "test-webhook-secret",
};
Deno.test("paused checkout continues verifying previously initiated payments", async () => {
  const data = { enabled: false, credentials };
  const client = { rpc: () => Promise.resolve({ data, error: null }) };
  assertEquals((await loadFygaroConfiguration(client)).webhook.secrets, {
    "hook-key": "test-webhook-secret",
  });
  await assertRejects(() => requireFygaroCheckout(client), Error, "paused");
});
Deno.test("runtime credentials and rotation expire without exposing config fallback", () => {
  const data = {
    enabled: true,
    credentials: {
      ...credentials,
      previous_webhook_key_id: "old-key",
      previous_webhook_secret_key: "old-secret",
      previous_webhook_expires_at: "2026-10-15T00:00:00Z",
    },
  };
  assertEquals(
    parseFygaroConfiguration(data, Date.parse("2026-10-08T00:00:00Z")).webhook
      .secrets["old-key"],
    "old-secret",
  );
  assertEquals(
    parseFygaroConfiguration(data, Date.parse("2026-10-16T00:00:00Z")).webhook
      .secrets["old-key"],
    undefined,
  );
  assertEquals(parseFygaroConfiguration(data).checkout?.keyId, "checkout-key");
  assertThrows(
    () => parseFygaroConfiguration({ enabled: true, credentials: {} }),
    Error,
    "webhook",
  );
});
Deno.test("database configuration outage cannot silently turn checkout back on", async () => {
  await assertRejects(
    () =>
      loadFygaroConfiguration({
        rpc: () =>
          Promise.resolve({ data: null, error: { message: "Unavailable" } }),
      }),
    Error,
    "could not be loaded",
  );
});
