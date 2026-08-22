import {
  authenticatedUser,
  handleOptions,
  jsonResponse,
  serviceClient,
} from "../_shared/grace.ts";
import {
  BibleNudgeEvent,
  bibleNudgeEventError,
  deliverBibleNudgePush,
  loadBibleNudgePushRow,
} from "../_shared/bible_nudge_push.ts";

type RequestBody = {
  nudgeId?: string;
  event?: BibleNudgeEvent;
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
    const nudgeId = String(body.nudgeId ?? "").trim();
    const event = body.event;
    if (!nudgeId) return jsonResponse({ error: "nudgeId is required." }, 400);
    if (event !== "request" && event !== "accepted" && event !== "declined") {
      return jsonResponse({ error: "Unsupported Bible Nudge event." }, 400);
    }

    const client = serviceClient();
    const nudge = await loadBibleNudgePushRow(client, nudgeId);
    if (!nudge) return jsonResponse({ error: "Bible Nudge not found." }, 404);

    const senderId = String(nudge.sender_id ?? "");
    const recipientId = String(nudge.recipient_id ?? "");
    if (event === "request" && user.id !== senderId) {
      return jsonResponse(
        { error: "Only the sender can dispatch this nudge." },
        403,
      );
    }
    if (event !== "request" && user.id !== recipientId) {
      return jsonResponse(
        { error: "Only the recipient can dispatch this response." },
        403,
      );
    }

    const eventError = bibleNudgeEventError(nudge, event);
    if (eventError) return jsonResponse({ error: eventError }, 409);

    const { data: claimData, error: claimError } = await client.rpc(
      "claim_bible_nudge_push_delivery",
      { p_nudge_id: nudgeId, p_event: event },
    );
    if (claimError) return jsonResponse({ error: claimError.message }, 500);

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

    let push: { sent: boolean; reason?: string };
    try {
      push = await deliverBibleNudgePush(client, nudge, event);
    } catch (error) {
      push = {
        sent: false,
        reason: error instanceof Error
          ? error.message
          : "Push delivery failed.",
      };
    }

    const { data: completed, error: completionError } = await client.rpc(
      "complete_bible_nudge_push_delivery",
      {
        p_nudge_id: nudgeId,
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
      : "Unable to send Bible Nudge push.";
    return jsonResponse(
      { error: message },
      message === "Not authenticated." ? 401 : 500,
    );
  }
});
