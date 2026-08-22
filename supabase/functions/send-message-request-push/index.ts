import {
  authenticatedUser,
  handleOptions,
  jsonResponse,
  serviceClient,
} from "../_shared/grace.ts";
import {
  deliverMessageRequestPush,
  loadMessageRequestPushRow,
  MessageRequestEvent,
  messageRequestEventError,
} from "../_shared/message_request_push.ts";

type RequestBody = {
  requestId?: string;
  event?: MessageRequestEvent;
};

type DeliveryClaim = {
  claimed?: boolean;
  status?: string;
  lease_token?: string;
};

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;

  if (request.method !== "POST") {
    return jsonResponse({ error: "POST required." }, 405);
  }

  try {
    const user = await authenticatedUser(request);
    const body = (await request.json().catch(() => ({}))) as RequestBody;
    const requestId = String(body.requestId ?? "").trim();
    const event = body.event;
    if (!requestId) {
      return jsonResponse({ error: "requestId is required." }, 400);
    }
    if (event !== "request" && event !== "accepted" && event !== "denied") {
      return jsonResponse({ error: "Unsupported message-request event." }, 400);
    }

    const client = serviceClient();
    const messageRequest = await loadMessageRequestPushRow(client, requestId);
    if (!messageRequest) {
      return jsonResponse({ error: "Message request not found." }, 404);
    }

    const senderId = String(messageRequest.sender_id ?? "");
    const recipientId = String(messageRequest.recipient_id ?? "");
    if (event === "request" && user.id !== senderId) {
      return jsonResponse(
        { error: "Only the sender can dispatch this request notification." },
        403,
      );
    }
    if (event !== "request" && user.id !== recipientId) {
      return jsonResponse(
        { error: "Only the recipient can dispatch a request decision." },
        403,
      );
    }

    const eventError = messageRequestEventError(messageRequest, event);
    if (eventError) return jsonResponse({ error: eventError }, 409);

    const { data: claimData, error: claimError } = await client.rpc(
      "claim_message_request_push_delivery",
      { p_request_id: requestId, p_event: event },
    );
    if (claimError) {
      return jsonResponse({ error: claimError.message }, 500);
    }
    const claim = (claimData ?? {}) as DeliveryClaim;
    if (claim.claimed !== true) {
      const alreadySent = claim.status === "sent";
      return jsonResponse({
        ok: alreadySent,
        sent: alreadySent,
        queued: !alreadySent,
        reason: alreadySent
          ? "Push was already delivered."
          : `Delivery is ${claim.status ?? "queued"}.`,
      }, alreadySent ? 200 : 202);
    }

    const leaseToken = String(claim.lease_token ?? "").trim();
    if (!leaseToken) {
      return jsonResponse({ error: "Delivery lease was incomplete." }, 500);
    }

    const push = await deliverMessageRequestPush(client, messageRequest, event);
    const { data: completed, error: completionError } = await client.rpc(
      "complete_message_request_push_delivery",
      {
        p_request_id: requestId,
        p_event: event,
        p_lease_token: leaseToken,
        p_sent: push.sent,
        p_error: push.reason ?? null,
      },
    );
    if (completionError || completed !== true) {
      return jsonResponse({
        ok: push.sent,
        sent: push.sent,
        queued: true,
        reason: completionError?.message ??
          "Delivery will be reconciled by retry.",
      }, 202);
    }

    return jsonResponse({
      ok: push.sent,
      sent: push.sent,
      queued: !push.sent,
      reason: push.reason ?? null,
    }, push.sent ? 200 : 202);
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Unable to send message-request push.";
    const status = message === "Not authenticated." ? 401 : 500;
    return jsonResponse({ error: message }, status);
  }
});
