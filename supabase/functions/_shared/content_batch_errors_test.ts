import {
  contentBatchFailure,
  contentQuotaExhausted,
} from "./content_batch_errors.ts";

Deno.test("quota detection uses the final fallback provider, not an exhausted first provider", () => {
  if (
    contentQuotaExhausted(
      "Hugging Face: HTTP 402 depleted your monthly included credits | Gemini: HTTP 503 high demand",
    )
  ) throw Error("Transient fallback outage must retain normal retry");
  if (
    !contentQuotaExhausted(
      "Hugging Face: HTTP 402 | Gemini: HTTP 429 RESOURCE_EXHAUSTED",
    )
  ) throw Error("Daily quota must pause preparation");
  if (
    !contentQuotaExhausted(
      "Hugging Face: depleted your monthly included credits",
    )
  ) throw Error("Single-provider quota must pause preparation");
  if (
    contentQuotaExhausted(null) || contentQuotaExhausted("Malformed questions")
  ) throw Error("Content errors must retain bounded retries");
});

Deno.test("batch errors expose an actionable message without leaking provider payloads", () => {
  const quota = contentBatchFailure(
    "quiz",
    "Gemini: HTTP 429 private-provider-diagnostic",
  );
  if (!quota.startsWith("[quota]") || !quota.includes("24-hour")) {
    throw Error("Missing quota recovery message");
  }
  if (quota.includes("private-provider-diagnostic")) {
    throw Error("Raw provider diagnostic escaped");
  }
  if (
    !contentBatchFailure("quiz", "invalid output").includes("generation run")
  ) throw Error("Missing content diagnostic link");
});
