import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  bibleNudgeEventError,
  type BibleNudgePushRow,
} from "./bible_nudge_push.ts";

const pending: BibleNudgePushRow = {
  id: "nudge-1",
  sender_id: "sender-1",
  recipient_id: "recipient-1",
  sender_name: "Sender",
  recipient_name: "Recipient",
  status: "pending",
};

Deno.test("Bible Nudge request push requires a pending stored nudge", () => {
  assertEquals(bibleNudgeEventError(pending, "request"), null);
  assertStringIncludes(
    bibleNudgeEventError(pending, "accepted") ?? "",
    "stored nudge response is pending",
  );
});

Deno.test("Bible Nudge response push must match the stored decision", () => {
  assertEquals(
    bibleNudgeEventError({ ...pending, status: "accepted" }, "accepted"),
    null,
  );
  assertEquals(
    bibleNudgeEventError({ ...pending, status: "declined" }, "declined"),
    null,
  );
  assertStringIncludes(
    bibleNudgeEventError({ ...pending, status: "accepted" }, "declined") ??
      "",
    "stored nudge response is accepted",
  );
});
