import {
  handleOptions,
  jsonResponse,
  requireCronSecret,
  serviceClient,
} from "../_shared/grace.ts";
import { isChapterStudyDate } from "../_shared/bible_chapters.ts";

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "POST required." }, 405);
  }
  const denied = requireCronSecret(request, "DAILY_QUIZ_CRON_SECRET");
  if (denied) return denied;
  const client = serviceClient();
  const { data: job, error } = await client.rpc("daily_content_batch_worker", {
    p_action: "claim",
  });
  if (error) return jsonResponse({ error: "Batch queue unavailable." }, 503);
  if (!job) return jsonResponse({ idle: true });
  const invoke = async (
    name: string,
    secretName: string,
    body: Record<string, unknown>,
  ) => {
    const secret = Deno.env.get(secretName);
    if (!secret) throw new Error("Preparation credentials are not configured.");
    const response = await fetch(
      `${Deno.env.get("SUPABASE_URL")}/functions/v1/${name}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-cron-secret": secret,
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(100_000),
      },
    );
    const result = await response.json().catch(() => null);
    if (
      !response.ok || !result || result.error || result.failed_churches > 0 ||
      result.preparing
    ) throw new Error(`${name} did not complete. Check its generation run.`);
  };
  try {
    // Chapter-linked quizzes keep the reviewed Daily Word chapter contract.
    // Prepare every day's Daily Word too, so release has no need for fresh AI.
    if (job.stage === "word") {
      await invoke(
        "generate-daily-motivation",
        "DAILY_MOTIVATION_CRON_SECRET",
        {
          action: "prepare",
          publish_date: job.content_date,
        },
      );
    } else {
      await invoke("generate-daily-bible-quiz", "DAILY_QUIZ_CRON_SECRET", {
        action: "prepare",
        quiz_date: job.content_date,
      });
    }
    const { error: finished } = await client.rpc("daily_content_batch_worker", {
      p_action: job.stage === "word" ? "word_ready" : "complete",
      p_date: job.content_date,
      p_lease: job.lease,
    });
    if (finished) throw new Error("Completion could not be recorded.");
    return jsonResponse({
      prepared: job.content_date,
      chapter_study: isChapterStudyDate(job.content_date),
    });
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Preparation failed.";
    await client.rpc("daily_content_batch_worker", {
      p_action: "failed",
      p_date: job.content_date,
      p_lease: job.lease,
      p_error: message,
    });
    return jsonResponse({ error: message, date: job.content_date }, 503);
  }
});
