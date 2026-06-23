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

function sanitizeQuestion(row: Record<string, unknown>) {
  return {
    id: row.id,
    order: row.question_order,
    question: row.question_text,
    options: [row.option_a, row.option_b, row.option_c, row.option_d],
    category: row.category,
    difficulty: row.difficulty,
  };
}

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

    const { data: quiz } = await client
      .from("daily_bible_quizzes")
      .select("id, expires_at")
      .eq("church_id", churchId)
      .eq("quiz_date", jamaicaDateString())
      .eq("status", "published")
      .maybeSingle();
    if (!quiz) return jsonResponse({ error: "Daily Quiz is not available yet." }, 404);

    const { count: questionCount, error: questionCountError } = await client
      .from("daily_bible_quiz_questions")
      .select("id", { count: "exact", head: true })
      .eq("quiz_id", quiz.id);
    if (questionCountError || questionCount !== 5) {
      return jsonResponse({
        error: "Daily Quiz is still being prepared. Please refresh in a moment.",
      }, 409);
    }

    const { data: existing } = await client
      .from("quiz_attempts")
      .select("id, status, total_score, correct_answers, failure_reason")
      .eq("quiz_id", quiz.id)
      .eq("member_id", user.id)
      .maybeSingle();
    if (existing) {
      return jsonResponse({
        error: "You already used today’s Daily Bible Quiz attempt.",
        attempt: existing,
        next_refresh_at: nextJamaicaRefresh(7).toISOString(),
      }, 409);
    }

    const now = new Date().toISOString();
    const { data: attempt, error: attemptError } = await client
      .from("quiz_attempts")
      .insert({
        quiz_id: quiz.id,
        member_id: user.id,
        church_id: churchId,
        church_id_at_attempt: churchId,
        status: "active",
        started_at: now,
        question_started_at: now,
        last_heartbeat_at: now,
      })
      .select("id, status, total_score, correct_answers, current_question_order, question_started_at")
      .single();
    if (attemptError || !attempt) return jsonResponse({ error: "Unable to start quiz." }, 500);

    await client.from("quiz_security_events").insert({
      attempt_id: attempt.id,
      member_id: user.id,
      church_id: churchId,
      event_type: "quiz_started",
    });

    const { data: question } = await client
      .from("daily_bible_quiz_questions")
      .select("id, question_order, question_text, option_a, option_b, option_c, option_d, category, difficulty")
      .eq("quiz_id", quiz.id)
      .eq("question_order", 1)
      .single();

    return jsonResponse({
      ok: true,
      quiz_id: quiz.id,
      attempt,
      question: sanitizeQuestion(question),
      question_time_limit_seconds: 30,
      next_refresh_at: nextJamaicaRefresh(7).toISOString(),
    });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : "Unable to start quiz." }, 400);
  }
});
