import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  messageRequestEventError,
  type MessageRequestPushRow,
} from "./message_request_push.ts";

const pending: MessageRequestPushRow = {
  id: "request-1",
  sender_id: "sender-1",
  recipient_id: "recipient-1",
  status: "pending",
};

Deno.test("request push only accepts the stored pending lifecycle event", () => {
  assertEquals(messageRequestEventError(pending, "request"), null);
  assertStringIncludes(
    messageRequestEventError(pending, "accepted") ?? "",
    "stored request decision is pending",
  );
});

Deno.test("accepted push requires the atomically delivered conversation and message", () => {
  const incomplete: MessageRequestPushRow = {
    ...pending,
    status: "accepted",
  };
  assertStringIncludes(
    messageRequestEventError(incomplete, "accepted") ?? "",
    "has not delivered its first message",
  );

  const delivered: MessageRequestPushRow = {
    ...incomplete,
    conversation_id: "conversation-1",
    delivered_message_id: "message-1",
  };
  assertEquals(messageRequestEventError(delivered, "accepted"), null);
});

Deno.test("denial push cannot be spoofed before the database decision", () => {
  assertStringIncludes(
    messageRequestEventError(pending, "denied") ?? "",
    "stored request decision is pending",
  );
  assertEquals(
    messageRequestEventError({ ...pending, status: "denied" }, "denied"),
    null,
  );
});
