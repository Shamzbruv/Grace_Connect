import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

import { sendTopicPush } from "./grace.ts";

export type BibleNudgeEvent = "request" | "accepted" | "declined";

export type BibleNudgePushRow = {
  id: string;
  sender_id: string;
  recipient_id: string;
  sender_name?: string | null;
  recipient_name?: string | null;
  status: string;
};

function cleanName(value: unknown, fallback: string): string {
  const name = String(value ?? "").replace(/\s+/g, " ").trim();
  return name ? name.slice(0, 80) : fallback;
}

export function bibleNudgeEventError(
  row: BibleNudgePushRow,
  event: BibleNudgeEvent,
): string | null {
  if (event === "request" && row.status !== "pending") {
    return "Only pending nudges can be dispatched.";
  }
  if (event !== "request" && row.status !== event) {
    return `The stored nudge response is ${row.status || "unavailable"}.`;
  }
  return null;
}

export async function loadBibleNudgePushRow(
  client: SupabaseClient,
  nudgeId: string,
): Promise<BibleNudgePushRow | null> {
  const { data, error } = await client
    .from("bible_nudges")
    .select(
      "id,sender_id,recipient_id,sender_name,recipient_name,status",
    )
    .eq("id", nudgeId)
    .maybeSingle();
  if (error) throw new Error(`Could not load Bible Nudge: ${error.message}`);
  return data ? data as BibleNudgePushRow : null;
}

export async function deliverBibleNudgePush(
  client: SupabaseClient,
  row: BibleNudgePushRow,
  event: BibleNudgeEvent,
): Promise<{ sent: boolean; reason?: string }> {
  const eventError = bibleNudgeEventError(row, event);
  if (eventError) return { sent: false, reason: eventError };

  const senderId = String(row.sender_id ?? "").trim();
  const recipientId = String(row.recipient_id ?? "").trim();
  if (!senderId || !recipientId) {
    return { sent: false, reason: "Bible Nudge participants are incomplete." };
  }

  const targetId = event === "request" ? recipientId : senderId;
  const actorId = event === "request" ? senderId : recipientId;
  const actorName = event === "request"
    ? cleanName(row.sender_name, "A Grace Connect member")
    : cleanName(row.recipient_name, "A Grace Connect member");

  const notification = event === "request"
    ? {
      type: "bible_nudge_request",
      title: "Bible Nudge",
      body: `${actorName} wants to encourage you in Scripture.`,
      route: "/notifications",
    }
    : event === "accepted"
    ? {
      type: "bible_nudge_response",
      title: "Bible Nudge accepted",
      body: `${actorName} accepted your Bible Nudge.`,
      route: `/public_profile?id=${encodeURIComponent(actorId)}`,
    }
    : {
      type: "bible_nudge_response",
      title: "Bible Nudge declined",
      body: `${actorName} declined your Bible Nudge.`,
      route: "/notifications",
    };

  return await sendTopicPush(client, {
    topic: `user_${targetId}`,
    title: notification.title,
    body: notification.body,
    route: notification.route,
    type: notification.type,
    entityTable: "bible_nudges",
    entityId: row.id,
    idempotencyKey: `${row.id}:${event}`,
  });
}
