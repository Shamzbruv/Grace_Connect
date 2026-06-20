import {
  authenticatedUser,
  handleOptions,
  jsonResponse,
  nextJamaicaRefresh,
  serviceClient,
} from "../_shared/grace.ts";

function sanitizeQuestion(row: Record<string, unknown> | null) {
  if (!row) return null;
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
    const body = await request.json().catch(() => ({}));
    const attemptId = String(body.attempt_id ?? "");
    const questionId = String(body.question_id ?? "");
    const selected = Number(body.selected_option_index);
    if (!attemptId || !questionId || !Number.isInteger(selected)) {
      return jsonResponse({ error: "Missing answer details." }, 400);
    }

    const { data: attempt } = await client
      .from("quiz_attempts")
      .select("*")
      .eq("id", attemptId)
      .eq("member_id", user.id)
      .maybeSingle();
    if (!attempt || attempt.status !== "active") {
      return jsonResponse({ error: "This quiz attempt is not active." }, 409);
    }

    const { data: question } = await client
      .from("daily_bible_quiz_questions")
      .select("*")
      .eq("id", questionId)
      .eq("quiz_id", attempt.quiz_id)
      .eq("question_order", attempt.current_question_order)
      .maybeSingle();
    if (!question) return jsonResponse({ error: "Question is no longer active." }, 409);

    const startedAt = new Date(attempt.question_started_at ?? attempt.started_at);
    const nowDate = new Date();
    const responseTimeMs = Math.max(0, nowDate.getTime() - startedAt.getTime());
    const timedOut = responseTimeMs > 30000;
    const isCorrect = !timedOut && selected === Number(question.correct_option_index);
    const points = isCorrect ? 20 : 0;

    const { data: existingAnswer } = await client
      .from("quiz_attempt_answers")
      .select("id")
      .eq("attempt_id", attemptId)
      .eq("question_id", questionId)
      .maybeSingle();
    if (existingAnswer) {
      return jsonResponse({ error: "This question has already been answered." }, 409);
    }

    await client.from("quiz_attempt_answers").insert({
      attempt_id: attemptId,
      question_id: questionId,
      selected_option_index: selected,
      is_correct: isCorrect,
      points_awarded: points,
      answered_at: nowDate.toISOString(),
      response_time_ms: responseTimeMs,
      timed_out: timedOut,
    });

    const nextOrder = Number(attempt.current_question_order) + 1;
    const completed = nextOrder > 5;
    const totalScore = Number(attempt.total_score ?? 0) + points;
    const correctAnswers = Number(attempt.correct_answers ?? 0) + (isCorrect ? 1 : 0);
    const totalResponseTime = Number(attempt.total_response_time_ms ?? 0) + responseTimeMs;
    const update = completed
      ? {
        status: "completed",
        completed_at: nowDate.toISOString(),
        total_score: totalScore,
        correct_answers: correctAnswers,
        total_response_time_ms: totalResponseTime,
        last_heartbeat_at: nowDate.toISOString(),
      }
      : {
        current_question_order: nextOrder,
        question_started_at: nowDate.toISOString(),
        last_heartbeat_at: nowDate.toISOString(),
        total_score: totalScore,
        correct_answers: correctAnswers,
        total_response_time_ms: totalResponseTime,
      };
    await client.from("quiz_attempts").update(update).eq("id", attemptId);
    await client.from("quiz_security_events").insert({
      attempt_id: attemptId,
      member_id: user.id,
      church_id: attempt.church_id,
      event_type: timedOut ? "question_timed_out" : "answer_submitted",
      metadata: { question_id: questionId, is_correct: isCorrect, response_time_ms: responseTimeMs },
    });

    let nextQuestion = null;
    if (!completed) {
      const { data } = await client
        .from("daily_bible_quiz_questions")
        .select("id, question_order, question_text, option_a, option_b, option_c, option_d, category, difficulty")
        .eq("quiz_id", attempt.quiz_id)
        .eq("question_order", nextOrder)
        .maybeSingle();
      nextQuestion = sanitizeQuestion(data);
    }

    return jsonResponse({
      ok: true,
      completed,
      feedback: {
        correct: isCorrect,
        timed_out: timedOut,
        points_awarded: points,
        correct_answer: question.correct_answer,
        explanation: question.explanation,
        scripture_references: question.scripture_references,
        total_score: totalScore,
        correct_answers: correctAnswers,
      },
      next_question: nextQuestion,
      next_refresh_at: nextJamaicaRefresh(7).toISOString(),
    });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : "Unable to submit answer." }, 400);
  }
});
