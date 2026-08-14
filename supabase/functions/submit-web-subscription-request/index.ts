import {
  accessTokenFromRequest,
  authenticatedUser,
  serviceClient,
} from "../_shared/grace.ts";
import { isAllowedWebSubscriptionOrigin } from "../_shared/web_subscription_origin.ts";

const allowedHeaders = "authorization, x-client-info, apikey, content-type";

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
    normalized.includes("forbidden")
  ) return 403;
  if (
    normalized.includes("required") ||
    normalized.includes("valid") ||
    normalized.includes("too long") ||
    normalized.includes("no longer matches")
  ) return 400;
  return 500;
}

Deno.serve(async (request) => {
  const origin = request.headers.get("Origin") ?? "";
  const configuredOrigins = Deno.env.get("GRACE_CONNECT_WEB_ORIGINS");
  if (!isAllowedWebSubscriptionOrigin(origin, configuredOrigins)) {
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

  const declaredLength = Number(request.headers.get("Content-Length") ?? 0);
  if (Number.isFinite(declaredLength) && declaredLength > 16_384) {
    return response(origin, { error: "Request body is too large." }, 413);
  }

  try {
    const token = accessTokenFromRequest(request);
    const user = await authenticatedUser(request);
    if (!token) return response(origin, { error: "Not authenticated." }, 401);

    const bodyText = await request.text();
    if (new TextEncoder().encode(bodyText).byteLength > 16_384) {
      return response(origin, { error: "Request body is too large." }, 413);
    }
    let body: Record<string, unknown>;
    try {
      body = JSON.parse(bodyText || "{}") as Record<string, unknown>;
    } catch (_) {
      return response(
        origin,
        { error: "Request body must be valid JSON." },
        400,
      );
    }

    const client = serviceClient();
    const action = String(body.action ?? "submit").trim().toLowerCase();
    if (action === "context") {
      const { data, error } = await client.rpc(
        "get_web_subscription_request_context_internal",
        { p_actor_id: user.id },
      );
      if (error) throw error;
      return response(origin, { ok: true, context: data });
    }
    if (action !== "submit") {
      return response(origin, { error: "Unsupported request action." }, 400);
    }

    const intent = String(body.intent ?? "").trim().toLowerCase();
    if (
      !["new_subscription", "change_plan", "enterprise_quote"].includes(intent)
    ) {
      return response(origin, {
        error: "A valid plan request type is required.",
      }, 400);
    }

    const { data, error } = await client.rpc(
      "submit_web_subscription_request_internal",
      {
        p_actor_id: user.id,
        p_intent: intent,
        p_contact_name: String(body.contactName ?? "").trim(),
        p_contact_email: String(body.contactEmail ?? "").trim(),
        p_contact_phone: String(body.contactPhone ?? "").trim() || null,
        p_message: String(body.message ?? "").trim() || null,
        p_terms_accepted: body.termsAccepted === true,
        p_origin: origin,
      },
    );
    if (error) throw error;
    const { data: context, error: contextError } = await client.rpc(
      "get_web_subscription_request_context_internal",
      { p_actor_id: user.id },
    );
    if (contextError) throw contextError;

    return response(origin, {
      ok: true,
      ...data,
      church: {
        name: context.churchName,
        memberCount: context.memberCount,
        tier: context.calculatedTier,
      },
      notice:
        "Request received for developer finance review. No charge, activation, enrollment, or invoice was created.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Request failed.";
    return response(origin, { error: message }, errorStatus(message));
  }
});
