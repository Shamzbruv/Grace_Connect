// Fygaro payment webhook.
//
// This endpoint is public by necessity -- Fygaro calls it, not a signed-in
// user -- so the HMAC signature is the only thing standing between a stranger
// and a free subscription. Nothing is trusted until verifyFygaroWebhook
// returns, including the payload's own amount.

import { serviceClient } from "../_shared/grace.ts";
import {
  fygaroWebhookConfigFromEnv,
  monthlyPeriodFrom,
  normalizeFygaroPayment,
  verifyFygaroWebhook,
} from "../_shared/fygaro.ts";

const PROVIDER = "fygaro";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "POST required." }, 405);
  }

  // The signature covers the exact bytes Fygaro sent, so the body must be
  // read as text and verified before it is parsed. Re-serialising parsed JSON
  // would change key order and whitespace and never match.
  const rawBody = await request.text();
  if (new TextEncoder().encode(rawBody).byteLength > 65_536) {
    return json({ error: "Payload too large." }, 413);
  }

  try {
    await verifyFygaroWebhook({
      config: fygaroWebhookConfigFromEnv(),
      signatureHeader: request.headers.get("Fygaro-Signature") ?? "",
      keyIdHeader: request.headers.get("Fygaro-Key-ID"),
      rawBody,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invalid signature";
    console.error("fygaro-webhook rejected:", message);
    // 4xx, per Fygaro's documented contract for a failed hook.
    return json({ error: message }, 400);
  }

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(rawBody || "{}") as Record<string, unknown>;
  } catch (_) {
    return json({ error: "Body must be valid JSON." }, 400);
  }

  try {
    const payment = normalizeFygaroPayment(payload);
    const period = monthlyPeriodFrom(payment.paidAt);

    const client = serviceClient();
    const { data, error } = await client.rpc(
      "apply_web_subscription_event_internal",
      {
        p_provider: PROVIDER,
        // Fygaro's transaction id is unique per charge, which makes it the
        // natural idempotency key: a retried hook resolves to the same id and
        // the database refuses to apply it twice.
        p_provider_event_id: payment.transactionId,
        p_event_type: "payment_succeeded",
        p_provider_session_id: payment.customReference,
        p_provider_subscription_id: null,
        p_provider_customer_id: payment.customerEmail,
        // Fygaro only notifies on a successful payment, so a hook that
        // verifies is by definition an active, paid period.
        p_provider_status: "active",
        p_currency: payment.currency,
        p_amount_minor: payment.amountMinor,
        p_current_period_start: period.start.toISOString(),
        p_current_period_end: period.end.toISOString(),
        p_cancel_at: null,
        // Keep the reconciliation fields, never the legacy JWT, card data,
        // billing address, or full customer contact payload.
        p_payload: {
          transactionId: payment.transactionId,
          customReference: payment.customReference,
          currency: payment.currency,
          amountMinor: payment.amountMinor,
          paidAt: payment.paidAt.toISOString(),
        },
      },
    );
    if (error) throw error;

    if (data?.duplicate === true) {
      // Already applied. Still a 200: anything else makes Fygaro keep
      // retrying a hook that has nothing left to do.
      return json({ ok: true, duplicate: true });
    }
    if (data?.matched === false) {
      console.error(
        "fygaro-webhook: no church matched transaction",
        payment.transactionId,
        "customReference",
        payment.customReference,
      );
      // Recorded in church_billing_events with the reason, so the payment is
      // never simply lost. A 200 stops the retries; a human reconciles it.
      return json({ ok: true, matched: false });
    }

    return json({ ok: true, churchId: data?.churchId, status: data?.status });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Hook failed.";
    console.error("fygaro-webhook failed:", message);
    // A 500 asks Fygaro to retry, which is right for a transient database
    // failure -- the idempotency key makes the retry safe.
    return json({ error: message }, 500);
  }
});
