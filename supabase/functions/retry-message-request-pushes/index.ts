import {
  handleOptions,
  jsonResponse,
  requireCronSecret,
  serviceClient,
} from "../_shared/grace.ts";
import {
  BibleNudgeEvent,
  deliverBibleNudgePush,
  loadBibleNudgePushRow,
} from "../_shared/bible_nudge_push.ts";
import {
  deliverMessageRequestPush,
  loadMessageRequestPushRow,
  MessageRequestEvent,
} from "../_shared/message_request_push.ts";

type MessageRequestClaim = {
  request_id: string;
  event: MessageRequestEvent;
  lease_token: string;
};

type BibleNudgeClaim = {
  nudge_id: string;
  event: BibleNudgeEvent;
  lease_token: string;
};

type DeliveryResult = { sent: boolean; reason?: string };

async function runBatches<T>(
  claims: T[],
  deliver: (claim: T) => Promise<DeliveryResult>,
): Promise<{ sent: number; failed: number; errors: string[] }> {
  let sent = 0;
  let failed = 0;
  const errors: string[] = [];

  for (let offset = 0; offset < claims.length; offset += 5) {
    const outcomes = await Promise.allSettled(
      claims.slice(offset, offset + 5).map(deliver),
    );
    for (const outcome of outcomes) {
      if (outcome.status === "fulfilled" && outcome.value.sent) {
        sent += 1;
      } else {
        failed += 1;
        const reason = outcome.status === "rejected"
          ? outcome.reason
          : outcome.value.reason;
        if (errors.length < 10) {
          errors.push(String(reason ?? "Delivery failed."));
        }
      }
    }
  }

  return { sent, failed, errors };
}

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "POST required." }, 405);
  }

  const forbidden = requireCronSecret(request, "DAILY_QUIZ_CRON_SECRET");
  if (forbidden) return forbidden;

  const client = serviceClient();
  const [messageClaimsResult, nudgeClaimsResult] = await Promise.all([
    client.rpc("claim_due_message_request_push_deliveries", { p_limit: 50 }),
    client.rpc("claim_due_bible_nudge_push_deliveries", { p_limit: 50 }),
  ]);
  if (messageClaimsResult.error) {
    return jsonResponse({ error: messageClaimsResult.error.message }, 500);
  }
  if (nudgeClaimsResult.error) {
    return jsonResponse({ error: nudgeClaimsResult.error.message }, 500);
  }

  const messageClaims =
    (messageClaimsResult.data ?? []) as MessageRequestClaim[];
  const nudgeClaims = (nudgeClaimsResult.data ?? []) as BibleNudgeClaim[];

  const messageResults = await runBatches(messageClaims, async (claim) => {
    const requestId = String(claim.request_id ?? "").trim();
    const event = claim.event;
    const leaseToken = String(claim.lease_token ?? "").trim();
    if (
      !requestId || !leaseToken ||
      (event !== "request" && event !== "accepted" && event !== "denied")
    ) {
      throw new Error("Message-request delivery claim was incomplete.");
    }

    let push: DeliveryResult;
    try {
      const row = await loadMessageRequestPushRow(client, requestId);
      push = row
        ? await deliverMessageRequestPush(client, row, event)
        : { sent: false, reason: "Message request no longer exists." };
    } catch (error) {
      push = {
        sent: false,
        reason: error instanceof Error
          ? error.message
          : "Push delivery failed.",
      };
    }

    const { data: completed, error } = await client.rpc(
      "complete_message_request_push_delivery",
      {
        p_request_id: requestId,
        p_event: event,
        p_lease_token: leaseToken,
        p_sent: push.sent,
        p_error: push.reason ?? null,
      },
    );
    if (error || completed !== true) {
      throw new Error(error?.message ?? "Message-request lease was stale.");
    }
    return push;
  });

  const nudgeResults = await runBatches(nudgeClaims, async (claim) => {
    const nudgeId = String(claim.nudge_id ?? "").trim();
    const event = claim.event;
    const leaseToken = String(claim.lease_token ?? "").trim();
    if (
      !nudgeId || !leaseToken ||
      (event !== "request" && event !== "accepted" && event !== "declined")
    ) {
      throw new Error("Bible-Nudge delivery claim was incomplete.");
    }

    let push: DeliveryResult;
    try {
      const row = await loadBibleNudgePushRow(client, nudgeId);
      push = row
        ? await deliverBibleNudgePush(client, row, event)
        : { sent: false, reason: "Bible Nudge no longer exists." };
    } catch (error) {
      push = {
        sent: false,
        reason: error instanceof Error
          ? error.message
          : "Push delivery failed.",
      };
    }

    const { data: completed, error } = await client.rpc(
      "complete_bible_nudge_push_delivery",
      {
        p_nudge_id: nudgeId,
        p_event: event,
        p_lease_token: leaseToken,
        p_sent: push.sent,
        p_error: push.reason ?? null,
      },
    );
    if (error || completed !== true) {
      throw new Error(error?.message ?? "Bible-Nudge lease was stale.");
    }
    return push;
  });

  const failed = messageResults.failed + nudgeResults.failed;
  return jsonResponse({
    ok: failed === 0,
    messageRequests: {
      claimed: messageClaims.length,
      sent: messageResults.sent,
      failed: messageResults.failed,
    },
    bibleNudges: {
      claimed: nudgeClaims.length,
      sent: nudgeResults.sent,
      failed: nudgeResults.failed,
    },
    errors: [...messageResults.errors, ...nudgeResults.errors].slice(0, 10),
  }, failed === 0 ? 200 : 502);
});
