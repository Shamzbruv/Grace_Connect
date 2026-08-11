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

async function replaySavedAnswer(
  client: ReturnType<typeof serviceClient>,
  attemptId: string,
  question: Record<string, unknown>,
  answer: Record<string, unknown>,
  deferNextQuestionStart: boolean,
): Promise<Record<string, unknown>> {
  const { data } = await client
    .from("quiz_attempts")
    .select("*")
    .eq("id", attemptId)
    .single();
  let currentAttempt = data;
  const answeredOrder = Number(question.question_order ?? 0);
  if (currentAttempt?.status === "active" &&
    Number(currentAttempt.current_question_order ?? 1) <= answeredOrder) {
    const { data: savedAnswers } = await client
      .from("quiz_attempt_answers")
      .select("points_awarded, is_correct, response_time_ms")
      .eq("attempt_id", attemptId);
    const score = (savedAnswers ?? []).reduce(
      (total, row) => total + Number(row.points_awarded ?? 0),
      0,
    );
    const correct = (savedAnswers ?? []).filter((row) => row.is_correct === true).length;
    const responseTime = (savedAnswers ?? []).reduce(
      (total, row) => total + Number(row.response_time_ms ?? 0),
      0,
    );
    const nextOrder = answeredOrder + 1;
    const completedNow = nextOrder > 5;
    const repaired = await client
      .from("quiz_attempts")
      .update(completedNow
        ? {
          status: "completed",
          completed_at: new Date().toISOString(),
          total_score: score,
          correct_answers: correct,
          total_response_time_ms: responseTime,
        }
        : {
          current_question_order: nextOrder,
          // The next clock starts when the member actually opens the next
          // question, not while they are reading this answer's explanation.
          question_started_at: deferNextQuestionStart ? null : new Date().toISOString(),
          total_score: score,
          correct_answers: correct,
          total_response_time_ms: responseTime,
        })
      .eq("id", attemptId)
      .eq("current_question_order", currentAttempt.current_question_order)
      .select("*")
      .maybeSingle();
    if (repaired.data) {
      currentAttempt = repaired.data;
    } else {
      // Another retry may have advanced this attempt concurrently. Re-read it
      // so both callers return the same next question instead of replaying the
      // question that was already saved.
      const { data: refreshedAttempt } = await client
        .from("quiz_attempts")
        .select("*")
        .eq("id", attemptId)
        .single();
      if (refreshedAttempt) currentAttempt = refreshedAttempt;
    }
  }
  const completed = currentAttempt?.status === "completed";
  let nextQuestion = null;
  if (!completed) {
    const { data } = await client
      .from("daily_bible_quiz_questions")
      .select("id, question_order, question_text, option_a, option_b, option_c, option_d, category, difficulty")
      .eq("quiz_id", currentAttempt.quiz_id)
      .eq("question_order", currentAttempt.current_question_order)
      .maybeSingle();
    nextQuestion = sanitizeQuestion(data);
  }
  return {
    ok: true,
    replayed: true,
    completed,
    feedback: {
      correct: answer.is_correct === true,
      timed_out: answer.timed_out === true,
      points_awarded: Number(answer.points_awarded ?? 0),
      correct_answer: question.correct_answer,
      explanation: question.explanation,
      scripture_references: question.scripture_references,
      total_score: Number(currentAttempt?.total_score ?? 0),
      correct_answers: Number(currentAttempt?.correct_answers ?? 0),
    },
    next_question: nextQuestion,
    question_deadline_at: completed || !currentAttempt?.question_started_at
      ? null
      : new Date(new Date(currentAttempt.question_started_at).getTime() + 30_000).toISOString(),
    next_refresh_at: nextJamaicaRefresh(7).toISOString(),
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
    const deferNextQuestionStart = body.defer_next_question_start === true;
    if (!attemptId || !questionId || !Number.isInteger(selected) || selected < -1 || selected > 3) {
      return jsonResponse({ error: "Missing answer details." }, 400);
    }

    const { data: attempt } = await client
      .from("quiz_attempts")
      .select("*")
      .eq("id", attemptId)
      .eq("member_id", user.id)
      .maybeSingle();
    if (!attempt) return jsonResponse({ error: "This quiz attempt was not found." }, 404);

    const { data: question } = await client
      .from("daily_bible_quiz_questions")
      .select("*")
      .eq("id", questionId)
      .eq("quiz_id", attempt.quiz_id)
      .maybeSingle();
    if (!question) return jsonResponse({ error: "Quiz question was not found." }, 404);

    const { data: existingAnswer } = await client
      .from("quiz_attempt_answers")
      .select("id, is_correct, timed_out, points_awarded")
      .eq("attempt_id", attemptId)
      .eq("question_id", questionId)
      .maybeSingle();
    if (existingAnswer) {
      return jsonResponse(await replaySavedAnswer(
        client,
        attemptId,
        question,
        existingAnswer,
        deferNextQuestionStart,
      ));
    }

    if (attempt.status !== "active") {
      return jsonResponse({ error: "This quiz attempt is not active." }, 409);
    }
    if (Number(question.question_order) !== Number(attempt.current_question_order)) {
      return jsonResponse({ error: "Question is no longer active." }, 409);
    }

    const startedAt = new Date(attempt.question_started_at ?? attempt.started_at);
    const nowDate = new Date();
    const responseTimeMs = Math.max(0, nowDate.getTime() - startedAt.getTime());
    // Keep the visible limit at 30 seconds while allowing a small transport
    // grace period for a tap made at the deadline on a slow mobile connection.
    const timedOut = selected === -1 || responseTimeMs > 35000;
    const isCorrect = !timedOut && selected === Number(question.correct_option_index);
    const points = isCorrect ? 20 : 0;

    const { error: answerError } = await client.from("quiz_attempt_answers").insert({
      attempt_id: attemptId,
      question_id: questionId,
      selected_option_index: selected,
      is_correct: isCorrect,
      points_awarded: points,
      answered_at: nowDate.toISOString(),
      response_time_ms: responseTimeMs,
      timed_out: timedOut,
    });
    if (answerError) {
      if (answerError.code === "23505") {
        const { data: racedAnswer } = await client
          .from("quiz_attempt_answers")
          .select("id, is_correct, timed_out, points_awarded")
          .eq("attempt_id", attemptId)
          .eq("question_id", questionId)
          .single();
        return jsonResponse(await replaySavedAnswer(
          client,
          attemptId,
          question,
          racedAnswer ?? {},
          deferNextQuestionStart,
        ));
      }
      return jsonResponse({ error: "Unable to save this answer. Please try again." }, 500);
    }

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
        // Activated by start-daily-bible-quiz when the next question becomes
        // visible; explanation-reading time must not consume answer time.
        question_started_at: deferNextQuestionStart ? null : nowDate.toISOString(),
        last_heartbeat_at: nowDate.toISOString(),
        total_score: totalScore,
        correct_answers: correctAnswers,
        total_response_time_ms: totalResponseTime,
      };
    const { data: updatedAttempt, error: updateError } = await client
      .from("quiz_attempts")
      .update(update)
      .eq("id", attemptId)
      .eq("current_question_order", attempt.current_question_order)
      .select("id")
      .maybeSingle();
    if (updateError || !updatedAttempt) {
      return jsonResponse(await replaySavedAnswer(
        client,
        attemptId,
        question,
        {
          is_correct: isCorrect,
          timed_out: timedOut,
          points_awarded: points,
        },
        deferNextQuestionStart,
      ));
    }
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
      question_deadline_at: completed || deferNextQuestionStart
        ? null
        : new Date(nowDate.getTime() + 30_000).toISOString(),
      next_refresh_at: nextJamaicaRefresh(7).toISOString(),
    });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : "Unable to submit answer." }, 400);
  }
});
