import {
  authenticatedUser,
  handleOptions,
  jamaicaDateString,
  jsonResponse,
  nextJamaicaRefresh,
  profileChurchId,
  serviceClient,
  userProfile,
} from "../_shared/grace.ts";

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "POST required." }, 405);

  try {
    const client = serviceClient();
    const user = await authenticatedUser(request);
    const profile = await userProfile(client, user.id);
    const churchId = profileChurchId(profile);
    if (!churchId) return jsonResponse({ error: "Church membership required." }, 403);

    const quizDate = jamaicaDateString();
    const refreshAt = nextJamaicaRefresh(7);
    const { data: quiz } = await client
      .from("daily_bible_quizzes")
      .select("id, quiz_date, available_at, expires_at, status")
      .eq("church_id", churchId)
      .eq("quiz_date", quizDate)
      .eq("status", "published")
      .maybeSingle();

    if (!quiz) {
      return jsonResponse({
        ok: true,
        available: false,
        can_start: false,
        status: "not_available",
        next_refresh_at: refreshAt.toISOString(),
      });
    }

    const { count: questionCount, error: questionCountError } = await client
      .from("daily_bible_quiz_questions")
      .select("id", { count: "exact", head: true })
      .eq("quiz_id", quiz.id);
    if (questionCountError || questionCount !== 5) {
      return jsonResponse({
        ok: true,
        available: false,
        can_start: false,
        status: "not_ready",
        quiz,
        question_count: questionCount ?? 0,
        next_refresh_at: refreshAt.toISOString(),
      });
    }

    const { data: attempt } = await client
      .from("quiz_attempts")
      .select("id, status, total_score, correct_answers, failure_reason, completed_at, failed_at")
      .eq("quiz_id", quiz.id)
      .eq("member_id", user.id)
      .maybeSingle();

    return jsonResponse({
      ok: true,
      available: true,
      quiz,
      attempt,
      can_start: !attempt,
      status: attempt?.status ?? "ready",
      next_refresh_at: refreshAt.toISOString(),
    });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : "Unable to load quiz status." }, 400);
  }
});
