import {
  isAllowedWebSubscriptionOrigin,
  webSubscriptionOrigins,
} from "./web_subscription_origin.ts";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

Deno.test("web subscription origins require an exact production origin", () => {
  assert(
    isAllowedWebSubscriptionOrigin("https://graceconnect-app.onrender.com"),
    "production landing origin",
  );
  assert(
    !isAllowedWebSubscriptionOrigin(
      "https://graceconnect-app.onrender.com.attacker.example",
    ),
    "lookalike origin must be rejected",
  );
  assert(!isAllowedWebSubscriptionOrigin(null), "missing origin rejected");
});

Deno.test("configured and local development origins are explicit", () => {
  const origins = webSubscriptionOrigins("https://staging.graceconnect.app");
  assert(origins.has("https://staging.graceconnect.app"), "configured origin");
  assert(
    isAllowedWebSubscriptionOrigin("http://localhost:8787"),
    "local development origin",
  );
  assert(
    !isAllowedWebSubscriptionOrigin("https://localhost:8787"),
    "unexpected local protocol rejected",
  );
});
