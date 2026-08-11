import {
  authenticatedUser,
  handleOptions,
  jamaicaDateString,
  jsonResponse,
  nextJamaicaRefresh,
  profileQuizChurchId,
  profileQuizScope,
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

function questionDeadline(startedAt: string | null | undefined): string {
  const start = new Date(startedAt ?? Date.now());
  return new Date(start.getTime() + 30_000).toISOString();
}

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "POST required." }, 405);

  try {
    const client = serviceClient();
    const user = await authenticatedUser(request);
    const profile = await userProfile(client, user.id);
    const churchId = profileQuizChurchId(profile);
    const leaderboardScope = profileQuizScope(profile);

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
      .select("id, status, total_score, correct_answers, failure_reason, current_question_order, question_started_at, started_at, last_heartbeat_at")
      .eq("quiz_id", quiz.id)
      .eq("member_id", user.id)
      .maybeSingle();
    if (existing) {
      if (existing.status === "completed") {
        return jsonResponse({
          ok: true,
          completed: true,
          quiz_id: quiz.id,
          attempt: existing,
          leaderboard_scope: leaderboardScope,
          next_refresh_at: nextJamaicaRefresh(7).toISOString(),
        });
      }

      // Network loss, an Android lifecycle transition, or an older 10-second
      // heartbeat cleanup must not consume the member's only daily attempt.
      const resumedAt = existing.question_started_at ?? new Date().toISOString();
      const { data: resumedAttempt, error: resumeError } = await client
        .from("quiz_attempts")
        .update({
          status: "active",
          failed_at: null,
          failure_reason: null,
          question_started_at: resumedAt,
          last_heartbeat_at: new Date().toISOString(),
        })
        .eq("id", existing.id)
        .select("id, status, total_score, correct_answers, current_question_order, question_started_at, started_at")
        .single();
      if (resumeError || !resumedAttempt) {
        return jsonResponse({ error: "Unable to resume today's quiz." }, 500);
      }
      const { data: resumedQuestion } = await client
        .from("daily_bible_quiz_questions")
        .select("id, question_order, question_text, option_a, option_b, option_c, option_d, category, difficulty")
        .eq("quiz_id", quiz.id)
        .eq("question_order", resumedAttempt.current_question_order)
        .maybeSingle();
      if (!resumedQuestion) {
        return jsonResponse({ error: "The current quiz question is unavailable." }, 409);
      }
      return jsonResponse({
        ok: true,
        resumed: true,
        quiz_id: quiz.id,
        attempt: resumedAttempt,
        question: sanitizeQuestion(resumedQuestion),
        question_time_limit_seconds: 30,
        question_deadline_at: questionDeadline(resumedAttempt.question_started_at),
        leaderboard_scope: leaderboardScope,
        next_refresh_at: nextJamaicaRefresh(7).toISOString(),
      });
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
    if (!question) {
      return jsonResponse({ error: "The first quiz question is unavailable." }, 409);
    }

    return jsonResponse({
      ok: true,
      quiz_id: quiz.id,
      attempt,
      question: sanitizeQuestion(question),
      question_time_limit_seconds: 30,
      question_deadline_at: questionDeadline(attempt.question_started_at),
      leaderboard_scope: leaderboardScope,
      next_refresh_at: nextJamaicaRefresh(7).toISOString(),
    });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : "Unable to start quiz." }, 400);
  }
});
