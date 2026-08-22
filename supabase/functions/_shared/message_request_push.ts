import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

import { sendTopicPush } from "./grace.ts";

export type MessageRequestEvent = "request" | "accepted" | "denied";

export type MessageRequestPushRow = {
  id: string;
  sender_id: string;
  recipient_id: string;
  status: string;
  response_message?: string | null;
  conversation_id?: string | null;
  delivered_message_id?: string | null;
};

function cleanDisplayName(row: Record<string, unknown> | null): string {
  const name = String(row?.fullName ?? row?.displayName ?? "").trim();
  if (name) return name;
  const email = String(row?.email ?? "").trim();
  return email.includes("@") ? email.split("@")[0] : "A Grace Connect member";
}

function cleanResponse(value: unknown): string {
  return String(value ?? "").replace(/\s+/g, " ").trim().slice(0, 140);
}

export function messageRequestEventError(
  row: MessageRequestPushRow,
  event: MessageRequestEvent,
): string | null {
  if (event === "request" && row.status !== "pending") {
    return "Only pending requests can be dispatched.";
  }
  if (event !== "request" && row.status !== event) {
    return `The stored request decision is ${row.status || "unavailable"}.`;
  }
  if (
    event === "accepted" &&
    (!row.conversation_id || !row.delivered_message_id)
  ) {
    return "The accepted request has not delivered its first message.";
  }
  return null;
}

export async function loadMessageRequestPushRow(
  client: SupabaseClient,
  requestId: string,
): Promise<MessageRequestPushRow | null> {
  const { data, error } = await client
    .from("direct_message_requests")
    .select(
      "id,sender_id,recipient_id,status,response_message,conversation_id,delivered_message_id",
    )
    .eq("id", requestId)
    .maybeSingle();
  if (error) {
    throw new Error(`Could not load message request: ${error.message}`);
  }
  return data ? data as MessageRequestPushRow : null;
}

export async function deliverMessageRequestPush(
  client: SupabaseClient,
  row: MessageRequestPushRow,
  event: MessageRequestEvent,
): Promise<{ sent: boolean; reason?: string }> {
  const eventError = messageRequestEventError(row, event);
  if (eventError) return { sent: false, reason: eventError };

  const senderId = String(row.sender_id ?? "");
  const recipientId = String(row.recipient_id ?? "");
  const actorId = event === "request" ? senderId : recipientId;
  const targetId = event === "request" ? recipientId : senderId;
  const { data: actorProfile } = await client
    .from("users")
    .select("fullName,displayName,email")
    .or(`id.eq.${actorId},uid.eq.${actorId}`)
    .maybeSingle();
  const actorName = cleanDisplayName(actorProfile);
  const response = cleanResponse(row.response_message);

  const notification = event === "request"
    ? {
      type: "message_request_received",
      title: "New message request",
      body: `${actorName} wants permission to message you.`,
      route: "/inbox?tab=requests",
    }
    : event === "accepted"
    ? {
      type: "message_request_accepted",
      title: "Message request accepted",
      body:
        `${actorName} accepted your request. Your first message was delivered.${
          response ? ` Response: ${response}` : ""
        }`,
      route: "/inbox?tab=messages",
    }
    : {
      type: "message_request_denied",
      title: "Message request declined",
      body: `${actorName} declined your request.${
        response ? ` Response: ${response}` : ""
      } You can request again in 30 days.`,
      route: "/inbox?tab=requests",
    };

  return await sendTopicPush(client, {
    topic: `user_${targetId}`,
    title: notification.title,
    body: notification.body,
    route: notification.route,
    type: notification.type,
    entityTable: "direct_message_requests",
    entityId: row.id,
    idempotencyKey: `${row.id}:${event}`,
  });
}
