// Subscription self-service for the public website.
//
// The Android app provides account support. Website transactions (starting a
// payment, reviewing billing, requesting cancellation) happen here after the
// church leader signs in with the same credentials they use in the app.

import { authenticatedUser, serviceClient } from "../_shared/grace.ts";
import { isAllowedWebSubscriptionOrigin } from "../_shared/web_subscription_origin.ts";
import {
  buildFygaroCheckoutUrl,
  fygaroPaymentConfigFromEnv,
  signFygaroCheckoutJwt,
} from "../_shared/fygaro.ts";

const allowedHeaders = "authorization, x-client-info, apikey, content-type";
const PROVIDER = "fygaro";

function corsHeaders(origin: string): HeadersInit {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": allowedHeaders,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };
}

function response(origin: string, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function errorStatus(message: string): number {
  const normalized = message.toLowerCase();
  if (normalized.includes("authenticated")) return 401;
  if (
    normalized.includes("permission") ||
    normalized.includes("membership") ||
    normalized.includes("forbidden") ||
    normalized.includes("service role")
  ) return 403;
  if (
    normalized.includes("not configured") ||
    normalized.includes("is not configured")
  ) return 503;
  if (
    normalized.includes("required") ||
    normalized.includes("unknown") ||
    normalized.includes("unsupported") ||
    normalized.includes("already") ||
    normalized.includes("cannot be paid") ||
    normalized.includes("no published price") ||
    normalized.includes("no subscription")
  ) return 400;
  return 500;
}

Deno.serve(async (request) => {
  const origin = request.headers.get("Origin") ?? "";
  if (
    !isAllowedWebSubscriptionOrigin(
      origin,
      Deno.env.get("GRACE_CONNECT_WEB_ORIGINS"),
    )
  ) {
    return new Response(
      JSON.stringify({ error: "Website origin not allowed." }),
      {
        status: 403,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Cache-Control": "no-store",
        },
      },
    );
  }
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(origin) });
  }
  if (request.method !== "POST") {
    return response(origin, { error: "POST required." }, 405);
  }

  try {
    const user = await authenticatedUser(request);

    const bodyText = await request.text();
    if (new TextEncoder().encode(bodyText).byteLength > 16_384) {
      return response(origin, { error: "Request body is too large." }, 413);
    }
    let body: Record<string, unknown>;
    try {
      body = JSON.parse(bodyText || "{}") as Record<string, unknown>;
    } catch (_) {
      return response(origin, { error: "Request body must be valid JSON." }, 400);
    }

    const client = serviceClient();
    const action = String(body.action ?? "context").trim().toLowerCase();

    if (action === "context") {
      const { data, error } = await client.rpc(
        "get_web_subscription_portal_context_internal",
        { p_actor_id: user.id },
      );
      if (error) throw error;
      let checkoutReady = false;
      try {
        fygaroPaymentConfigFromEnv();
        checkoutReady = true;
      } catch (_) { /* Account management remains available during setup. */ }
      return response(origin, { ok: true, context: { ...data, checkoutReady } });
    }

    if (action === "checkout") {
      const tierCode = String(body.tierCode ?? "").trim();
      const currency = String(body.currency ?? "").trim().toUpperCase();
      if (!tierCode) {
        return response(origin, { error: "A plan is required." }, 400);
      }
      if (!["USD", "JMD"].includes(currency)) {
        return response(origin, { error: "A valid currency is required." }, 400);
      }

      // Configuration is read before the session row is created, so a
      // misconfigured deployment does not leave orphan "created" sessions
      // that were never offered to anyone.
      const config = fygaroPaymentConfigFromEnv();

      const returnUrl = String(body.returnUrl ?? "").trim() || null;
      const { data: session, error } = await client.rpc(
        "start_web_checkout_session_internal",
        {
          p_actor_id: user.id,
          p_tier_code: tierCode,
          p_currency: currency,
          p_provider: PROVIDER,
          p_return_url: returnUrl,
        },
      );
      if (error) throw error;

      const sessionId = String(session.sessionId);
      // Fygaro gives us no session id of its own, so our row id is the
      // handle: it travels as custom_reference and comes back on the webhook
      // as customReference, which is how a payment finds its church.
      const { error: attachError } = await client.rpc(
        "attach_web_checkout_session_internal",
        {
          p_session_id: sessionId,
          p_provider_session_id: sessionId,
          p_provider_customer_id: session.providerCustomerId ?? null,
        },
      );
      if (attachError) throw attachError;

      const jwt = await signFygaroCheckoutJwt({
        config,
        amountMinor: Number(session.amountMinor),
        currency,
        customReference: sessionId,
      });

      return response(origin, {
        ok: true,
        checkoutUrl: buildFygaroCheckoutUrl(config.buttonUrl, jwt),
        sessionId,
        church: {
          id: session.churchId,
          name: session.churchName,
          memberCount: session.memberCountSnapshot,
        },
        tier: session.tier,
        currency,
        amountMinor: session.amountMinor,
      });
    }

    if (action === "cancel") {
      const reason = String(body.reason ?? "").trim().slice(0, 4000) || null;
      const { data, error } = await client.rpc(
        "request_web_subscription_cancellation_internal",
        { p_actor_id: user.id, p_reason: reason },
      );
      if (error) throw error;

      const { data: context, error: contextError } = await client.rpc(
        "get_web_subscription_portal_context_internal",
        { p_actor_id: user.id },
      );
      if (contextError) throw contextError;

      return response(origin, {
        ok: true,
        ...data,
        context,
        notice:
          "Cancellation recorded. Access continues through the paid-through date. If you separately arranged recurring charges, contact billing to confirm they have stopped.",
      });
    }

    return response(origin, { error: "Unsupported request action." }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Request failed.";
    return response(origin, { error: message }, errorStatus(message));
  }
});
