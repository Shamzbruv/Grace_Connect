import {
  handleOptions,
  jsonResponse,
  requireCronSecret,
  sendTopicPush,
  serviceClient,
} from "../_shared/grace.ts";

type EventReminderClaim = {
  event_id: string;
  user_id: string;
  reminder_minutes: number;
  reminder_version: string;
  claim_token: string;
  event_title: string;
  event_start: string;
  event_location?: string | null;
};

function leadTimeLabel(minutes: number): string {
  if (minutes >= 1440) return "tomorrow";
  if (minutes >= 120) return "in about 2 hours";
  return "in about 30 minutes";
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
  const { data, error } = await client.rpc("claim_due_event_reminders", {
    p_limit: 50,
  });
  if (error) return jsonResponse({ error: error.message }, 500);

  const claims = (data ?? []) as EventReminderClaim[];
  let sent = 0;
  let failed = 0;
  const errors: string[] = [];

  // Small concurrent groups keep FCM delivery responsive without opening an
  // unbounded number of provider/token requests for a large church.
  for (let offset = 0; offset < claims.length; offset += 5) {
    const batch = claims.slice(offset, offset + 5);
    const outcomes = await Promise.allSettled(batch.map(async (claim) => {
      const eventId = String(claim.event_id ?? "").trim();
      const userId = String(claim.user_id ?? "").trim();
      const reminderVersion = String(claim.reminder_version ?? "").trim();
      const claimToken = String(claim.claim_token ?? "").trim();
      if (!eventId || !userId || !reminderVersion || !claimToken) {
        throw new Error("Reminder claim is missing its delivery identity.");
      }

      let push: { sent: boolean; reason?: string };
      try {
        const title = "Your RSVP event is coming up";
        const location = String(claim.event_location ?? "").trim();
        const body = `${claim.event_title} starts ${
          leadTimeLabel(
            Number(claim.reminder_minutes ?? 1440),
          )
        }${location ? ` at ${location}` : ""}.`;
        push = await sendTopicPush(client, {
          topic: `user_${userId}`,
          title,
          body,
          route: "/events",
          type: "event_rsvp_reminder",
          entityTable: "events",
          entityId: eventId,
          idempotencyKey: `event-rsvp:${eventId}:${reminderVersion}`,
        });
      } catch (error) {
        push = {
          sent: false,
          reason: error instanceof Error
            ? error.message
            : "Push delivery failed.",
        };
      }

      const { data: completed, error: completionError } = await client.rpc(
        "complete_event_reminder_delivery",
        {
          p_event_id: eventId,
          p_user_id: userId,
          p_claim_token: claimToken,
          p_sent: push.sent,
          p_error: push.reason ?? null,
        },
      );
      if (completionError) {
        throw new Error(
          `Could not complete reminder lease: ${completionError.message}`,
        );
      }
      if (completed !== true) {
        throw new Error("Reminder lease was superseded before completion.");
      }
      return push;
    }));

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

  return jsonResponse({
    ok: failed === 0,
    claimed: claims.length,
    sent,
    failed,
    errors,
  }, failed === 0 ? 200 : 502);
});
