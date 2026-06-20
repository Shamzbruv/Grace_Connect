import {
  authenticatedUser,
  callHuggingFaceJson,
  createInAppNotifications,
  handleOptions,
  hasCronSecret,
  hasReachedJamaicaHour,
  jamaicaDateString,
  jsonResponse,
  nextJamaicaRefresh,
  profileChurchId,
  sendTopicPush,
  serviceClient,
  userProfile,
} from "../_shared/grace.ts";
import { fallbackQuizQuestions, QuizQuestion } from "../_shared/quiz_bank.ts";

type AiQuizResponse = { questions?: QuizQuestion[] };

async function hashQuestion(question: string): Promise<string> {
  const hash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(question.trim().toLowerCase()),
  );
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function validateQuestion(value: unknown): QuizQuestion | null {
  const q = value as QuizQuestion | null;
  if (!q || typeof q.question !== "string") return null;
  if (!Array.isArray(q.options) || q.options.length !== 4) return null;
  const options = q.options.map((option) => String(option ?? "").trim());
  if (options.some((option) => option.length < 1)) return null;
  if (new Set(options.map((option) => option.toLowerCase())).size !== 4) return null;
  const index = Number(q.correct_option_index);
  if (!Number.isInteger(index) || index < 0 || index > 3) return null;
  if (String(q.correct_answer ?? "").trim() !== options[index]) return null;
  if (!String(q.explanation ?? "").trim()) return null;
  if (!Array.isArray(q.scripture_references) || q.scripture_references.length < 1) return null;
  if (!q.scripture_references.every((ref) => /^[1-3]?\s?[A-Za-z]+(?:\s[A-Za-z]+)*\s+\d{1,3}:\d{1,3}/.test(String(ref)))) {
    return null;
  }
  return {
    question: q.question.trim(),
    options: options as [string, string, string, string],
    correct_option_index: index,
    correct_answer: options[index],
    explanation: String(q.explanation).trim(),
    scripture_references: q.scripture_references.map((ref) => String(ref).trim()),
    category: String(q.category ?? "Bible").trim(),
    difficulty: (["easy", "medium", "hard"].includes(String(q.difficulty))
      ? q.difficulty
      : "easy") as "easy" | "medium" | "hard",
  };
}

function selectFiveQuestions(aiResponse: unknown): { questions: QuizQuestion[]; source: "ai" | "fallback" } {
  const candidates = Array.isArray((aiResponse as AiQuizResponse | null)?.questions)
    ? (aiResponse as AiQuizResponse).questions ?? []
    : [];
  const valid = candidates.map(validateQuestion).filter((q): q is QuizQuestion => q != null);
  const unique = new Map<string, QuizQuestion>();
  for (const question of valid) {
    unique.set(question.question.toLowerCase(), question);
  }
  if (unique.size >= 5) {
    return { questions: Array.from(unique.values()).slice(0, 5), source: "ai" };
  }
  return { questions: fallbackQuizQuestions.slice(0, 5), source: "fallback" };
}

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "POST required." }, 405);

  const client = serviceClient();
  const cronAuthorized = hasCronSecret(request, "DAILY_QUIZ_CRON_SECRET");
  const quizDate = jamaicaDateString();
  const availableAt = nextJamaicaRefresh(7, new Date(Date.now() - 24 * 60 * 60 * 1000));
  const expiresAt = nextJamaicaRefresh(7);
  let churchIds: string[] = [];

  if (cronAuthorized) {
    const { data: churchRows } = await client
      .from("users")
      .select("placeId")
      .not("placeId", "is", null);
    churchIds = Array.from(
      new Set((churchRows ?? []).map((row) => String(row.placeId ?? "").trim()).filter(Boolean)),
    );
  } else {
    let userId = "";
    try {
      userId = (await authenticatedUser(request)).id;
    } catch (_) {
      return jsonResponse({ error: "Forbidden." }, 403);
    }
    if (!hasReachedJamaicaHour(7)) {
      return jsonResponse({ error: "Today's quiz opens at 7:00 AM Jamaica time." }, 425);
    }
    const profile = await userProfile(client, userId);
    const churchId = profileChurchId(profile);
    if (!churchId) return jsonResponse({ error: "Church membership required." }, 403);
    churchIds = [churchId];
  }

  const prompt = `You are creating Bible Quiz questions for Grace Connect, a Christian church app.
Generate 12 fact-based, respectful, clear multiple-choice questions strictly grounded in Scripture.
Each question must have four options and one unambiguous correct answer.
Provide a concise explanation and one or more accurate Bible references supporting the answer.
Avoid denomination-specific interpretations, trick questions, unclear wording, prophecy-date predictions, prosperity claims, and copyrighted Bible quotations.
Use broadly accepted Bible facts that can be verified against a Bible text.
Return valid JSON only in this shape:
{"questions":[{"question":"string","options":["string","string","string","string"],"correct_option_index":0,"correct_answer":"string","explanation":"string","scripture_references":["Book Chapter:Verse"],"category":"string","difficulty":"easy"}]}`;

  let aiResponse: unknown = null;
  try {
    aiResponse = await callHuggingFaceJson(prompt);
  } catch (_) {
    aiResponse = null;
  }
  const selected = selectFiveQuestions(aiResponse);

  let published = 0;
  for (const churchId of churchIds) {
    const existing = await client
      .from("daily_bible_quizzes")
      .select("id, status, notification_sent_at")
      .eq("church_id", churchId)
      .eq("quiz_date", quizDate)
      .maybeSingle();

    if (existing.data?.status === "published" && existing.data?.notification_sent_at) {
      continue;
    }

    const { data: quiz, error: quizError } = await client
      .from("daily_bible_quizzes")
      .upsert({
        id: existing.data?.id,
        church_id: churchId,
        quiz_date: quizDate,
        available_at: availableAt.toISOString(),
        expires_at: expiresAt.toISOString(),
        status: "published",
        generation_source: selected.source,
        generation_status: selected.source === "ai" ? "generated" : "fallback",
        validation_notes: selected.source === "fallback" ? "Fallback question bank used." : null,
      }, { onConflict: "church_id,quiz_date" })
      .select("id")
      .single();

    if (quizError || !quiz) continue;

    await client.from("daily_bible_quiz_questions").delete().eq("quiz_id", quiz.id);
    const questionRows = [];
    for (let index = 0; index < selected.questions.length; index++) {
      const question = selected.questions[index];
      questionRows.push({
        quiz_id: quiz.id,
        question_order: index + 1,
        question_text: question.question,
        option_a: question.options[0],
        option_b: question.options[1],
        option_c: question.options[2],
        option_d: question.options[3],
        correct_option_index: question.correct_option_index,
        correct_answer: question.correct_answer,
        explanation: question.explanation,
        scripture_references: question.scripture_references,
        category: question.category,
        difficulty: question.difficulty,
        question_hash: await hashQuestion(question.question),
      });
    }
    const { error: questionError } = await client
      .from("daily_bible_quiz_questions")
      .insert(questionRows);
    if (questionError) continue;

    const title = "Daily Bible Quiz Is Ready";
    const body = "Today’s 5-question Bible challenge is now live. Can you earn 100 points?";
    const route = `/daily_bible_quiz?quizId=${quiz.id}`;

    await createInAppNotifications(client, {
      churchId,
      title,
      body,
      type: "daily_bible_quiz",
      route,
      entityTable: "daily_bible_quizzes",
      entityId: quiz.id,
      preferenceColumn: "notifyDailyQuiz",
    });

    await sendTopicPush(client, {
      topic: `church_${churchId}_quiz`,
      title,
      body,
      route,
      type: "daily_bible_quiz",
      entityTable: "daily_bible_quizzes",
      entityId: quiz.id,
    });

    await client
      .from("daily_bible_quizzes")
      .update({ notification_sent_at: new Date().toISOString() })
      .eq("id", quiz.id);
    published++;
  }

  return jsonResponse({
    ok: true,
    quiz_date: quizDate,
    churches_checked: churchIds.length,
    quizzes_published: published,
    source: selected.source,
  });
});
