import {
  authenticatedUser,
  callHuggingFaceJson,
  createInAppNotifications,
  GLOBAL_VISITOR_CHURCH_ID,
  handleOptions,
  hasCronSecret,
  hasReachedJamaicaHour,
  jamaicaDateString,
  jsonResponse,
  profileQuizChurchId,
  sendTopicPush,
  serviceClient,
  userProfile,
} from "../_shared/grace.ts";
import { fallbackQuizQuestions, QuizQuestion } from "../_shared/quiz_bank.ts";

type AiQuizResponse = { questions?: QuizQuestion[] };
type GenerationRunPatch = {
  completed_at?: string;
  churches_checked?: number;
  quizzes_published?: number;
  ai_status?: string;
  source_summary?: string;
  error_message?: string | null;
  metadata?: Record<string, unknown>;
};

type GenerationIssue = {
  church_id: string;
  stage: string;
  message: string;
};

function canonicalFact(question: QuizQuestion): string {
  const references = question.scripture_references
    .map((reference) => reference.toLowerCase().replace(/[^a-z0-9]/g, ""))
    .sort()
    .join("|");
  const answer = question.correct_answer.toLowerCase().replace(/[^a-z0-9]/g, "");
  // A paraphrased question about the same answer and passage is still a
  // repeated fact. This fingerprint catches that without relying on wording.
  return `${references}:${answer}`;
}

async function hashQuestion(question: QuizQuestion): Promise<string> {
  const hash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(canonicalFact(question)),
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

function seedScore(seed: string): number {
  let hash = 2166136261;
  for (let index = 0; index < seed.length; index++) {
    hash ^= seed.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

async function seededQuestionSet(
  questions: QuizQuestion[],
  seed: string,
  blockedHashes: Set<string>,
): Promise<{ questions: QuizQuestion[]; reusedRecent: boolean }> {
  const uniqueByFact = new Map<
    string,
    { question: QuizQuestion; hash: string; index: number }
  >();
  for (let index = 0; index < questions.length; index++) {
    const question = questions[index];
    const hash = await hashQuestion(question);
    // AI can phrase the same Bible fact several ways in one response. Keep one
    // candidate per reference+answer fingerprint for both AI and fallback sets.
    if (!uniqueByFact.has(hash)) {
      uniqueByFact.set(hash, { question, hash, index });
    }
  }

  const annotated = Array.from(uniqueByFact.values());
  const fresh = annotated.filter((item) => !blockedHashes.has(item.hash));
  const pool = fresh.length >= 5 ? fresh : annotated;
  const decorated = pool.map((item) => ({
    question: item.question,
    score: seedScore(`${seed}:${item.index}:${item.question.question}`),
  }));
  decorated.sort((left, right) => left.score - right.score);
  return {
    questions: decorated.slice(0, 5).map((item) => item.question),
    reusedRecent: fresh.length < 5,
  };
}

async function selectFiveQuestions(
  aiResponse: unknown,
  seed: string,
  recentQuestionHashes: Set<string>,
): Promise<{
  questions: QuizQuestion[];
  source: "ai" | "fallback";
  reusedRecent: boolean;
}> {
  const candidates = Array.isArray((aiResponse as AiQuizResponse | null)?.questions)
    ? (aiResponse as AiQuizResponse).questions ?? []
    : [];
  const valid = candidates.map(validateQuestion).filter((q): q is QuizQuestion => q != null);
  if (valid.length >= 5) {
    const selected = await seededQuestionSet(
      valid,
      seed,
      recentQuestionHashes,
    );
    if (selected.questions.length === 5 && !selected.reusedRecent) {
      return { ...selected, source: "ai" };
    }
  }
  const selected = await seededQuestionSet(
    fallbackQuizQuestions,
    seed,
    recentQuestionHashes,
  );
  if (selected.questions.length !== 5) {
    throw new Error("The curated Bible quiz bank does not contain five unique facts.");
  }
  return { ...selected, source: "fallback" };
}

async function quizHasExactlyFiveQuestions(
  client: ReturnType<typeof serviceClient>,
  quizId: string,
): Promise<boolean> {
  try {
    const { data: rows, error } = await client
      .from("daily_bible_quiz_questions")
      .select("id")
      .eq("quiz_id", quizId);
    return !error && rows?.length === 5;
  } catch (_) {
    return false;
  }
}

function daysBeforeJamaicaDate(dateKey: string, days: number): string {
  const date = new Date(`${dateKey}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
}

async function recentQuestionHashes(
  client: ReturnType<typeof serviceClient>,
  churchId: string,
  quizDate: string,
): Promise<Set<string>> {
  try {
    const cutoffDate = daysBeforeJamaicaDate(quizDate, 60);
    const { data: quizzes } = await client
      .from("daily_bible_quizzes")
      .select("id")
      .eq("church_id", churchId)
      .neq("quiz_date", quizDate)
      .gte("quiz_date", cutoffDate)
      .order("quiz_date", { ascending: false })
      .limit(80);

    const quizIds = (quizzes ?? [])
      .map((quiz) => String(quiz.id ?? "").trim())
      .filter(Boolean);
    if (quizIds.length === 0) return new Set();

    const { data: rows } = await client
      .from("daily_bible_quiz_questions")
      .select("question_hash, question_text, correct_answer, scripture_references, category, difficulty, option_a, option_b, option_c, option_d, correct_option_index, explanation")
      .in("quiz_id", quizIds)
      .limit(500);

    const hashes = new Set<string>();
    for (const row of rows ?? []) {
      const storedHash = String(row.question_hash ?? "").trim();
      if (storedHash) hashes.add(storedHash);
      const candidate = validateQuestion({
        question: row.question_text,
        options: [row.option_a, row.option_b, row.option_c, row.option_d],
        correct_option_index: row.correct_option_index,
        correct_answer: row.correct_answer,
        explanation: row.explanation,
        scripture_references: row.scripture_references,
        category: row.category,
        difficulty: row.difficulty,
      });
      if (candidate) hashes.add(await hashQuestion(candidate));
    }
    return hashes;
  } catch (_) {
    return new Set();
  }
}

function dateOffset(dateKey: string, days: number): string {
  const value = new Date(`${dateKey}T12:00:00.000Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

function quizReleaseAt(dateKey: string): Date {
  // Jamaica is UTC-5 year-round; 7:00 AM is 12:00 UTC.
  return new Date(`${dateKey}T12:00:00.000Z`);
}

async function createGenerationRun(
  client: ReturnType<typeof serviceClient>,
  quizDate: string,
  triggerSource: string,
): Promise<string | null> {
  try {
    const { data, error } = await client
      .from("quiz_generation_runs")
      .insert({
        run_date: quizDate,
        trigger_source: triggerSource,
        ai_status: "not_called",
      })
      .select("id")
      .single();
    if (error || !data?.id) return null;
    return String(data.id);
  } catch (_) {
    return null;
  }
}

async function updateGenerationRun(
  client: ReturnType<typeof serviceClient>,
  runId: string | null,
  patch: GenerationRunPatch,
): Promise<void> {
  if (!runId) return;
  try {
    await client.from("quiz_generation_runs").update(patch).eq("id", runId);
  } catch (_) {
    // Observability must never block quiz publishing.
  }
}

const scheduledQuizMutationRoles = new Set([
  "super_developer",
  "support_developer",
  "content_moderator",
  "security_admin",
]);

async function canRegenerateScheduledQuiz(
  client: ReturnType<typeof serviceClient>,
  request: Request,
): Promise<boolean> {
  try {
    const user = await authenticatedUser(request);
    const { data: linkedAccount } = await client
      .from("developer_accounts")
      .select("developer_role")
      .eq("status", "active")
      .eq("user_id", user.id)
      .maybeSingle();
    if (linkedAccount) {
      return scheduledQuizMutationRoles.has(
        String(linkedAccount.developer_role ?? "").trim().toLowerCase(),
      );
    }
    if (!user.email) return false;
    const { data: emailAccount } = await client
      .from("developer_accounts")
      .select("developer_role")
      .eq("status", "active")
      .eq("email", user.email.toLowerCase())
      .maybeSingle();
    return scheduledQuizMutationRoles.has(
      String(emailAccount?.developer_role ?? "").trim().toLowerCase(),
    );
  } catch (_) {
    return false;
  }
}

async function publishQuiz(
  client: ReturnType<typeof serviceClient>,
  quiz: Record<string, unknown>,
  churchId: string,
  issues: GenerationIssue[],
): Promise<void> {
  const quizId = String(quiz.id);
  await client.from("daily_bible_quizzes").update({ status: "published" }).eq("id", quizId);
  if (quiz.notification_sent_at) return;
  if (churchId === GLOBAL_VISITOR_CHURCH_ID) {
    await client
      .from("daily_bible_quizzes")
      .update({
        notification_sent_at: new Date().toISOString(),
        notification_claimed_at: null,
      })
      .eq("id", quizId)
      .is("notification_sent_at", null);
    return;
  }

  // Claim a short delivery lease. Failed or crashed invocations can be
  // reclaimed, while the shared in-app/outbox guards make that retry
  // idempotent after either side of delivery already succeeded.
  const claimedAt = new Date().toISOString();
  const staleBefore = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const { data: claimed } = await client
    .from("daily_bible_quizzes")
    .update({ notification_claimed_at: claimedAt })
    .eq("id", quizId)
    .is("notification_sent_at", null)
    .or(
      `notification_claimed_at.is.null,notification_claimed_at.lt.${staleBefore}`,
    )
    .select("id")
    .maybeSingle();
  if (!claimed) return;

  const title = "Daily Bible Quiz Is Ready";
  const body = "Today’s 5-question Bible challenge is now live. Can you earn 100 points?";
  const route = `/daily_bible_quiz?quizId=${quizId}`;
  await createInAppNotifications(client, {
    churchId,
    title,
    body,
    type: "daily_bible_quiz",
    route,
    entityTable: "daily_bible_quizzes",
    entityId: quizId,
    preferenceColumn: "notifyDailyQuiz",
  });
  const push = await sendTopicPush(client, {
    topic: `church_${churchId}_quiz`,
    title,
    body,
    route,
    type: "daily_bible_quiz",
    entityTable: "daily_bible_quizzes",
    entityId: quizId,
  });
  if (push.sent) {
    await client
      .from("daily_bible_quizzes")
      .update({
        notification_sent_at: new Date().toISOString(),
        notification_claimed_at: null,
      })
      .eq("id", quizId)
      .eq("notification_claimed_at", claimedAt);
  } else {
    await client
      .from("daily_bible_quizzes")
      .update({ notification_claimed_at: null })
      .eq("id", quizId)
      .eq("notification_claimed_at", claimedAt);
    issues.push({
      church_id: churchId,
      stage: "push_notification",
      message: push.reason ?? "Quiz push notification was not sent.",
    });
  }
}

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "POST required." }, 405);

  const client = serviceClient();
  const requestBody = await request.json().catch(() => ({}));
  const action = String(requestBody.action ?? "release");
  const preparing = action === "prepare";
  const regenerating = action === "regenerate_scheduled";
  const shouldPublish = !preparing && !regenerating;
  const cronAuthorized = hasCronSecret(request, "DAILY_QUIZ_CRON_SECRET");
  const today = jamaicaDateString();
  let quizDate = preparing ? dateOffset(today, 1) : today;
  let churchIds: string[] = [];
  let requestedQuiz: Record<string, unknown> | null = null;

  if (regenerating) {
    if (!(await canRegenerateScheduledQuiz(client, request))) {
      return jsonResponse({ error: "Quiz refresh permission is required." }, 403);
    }
    const quizId = String(requestBody.quiz_id ?? "").trim();
    if (!quizId) return jsonResponse({ error: "Quiz ID is required." }, 400);
    const { data: quiz } = await client
      .from("daily_bible_quizzes")
      .select("*")
      .eq("id", quizId)
      .maybeSingle();
    if (!quiz || quiz.status !== "scheduled" || new Date(quiz.available_at) <= new Date()) {
      return jsonResponse({ error: "Only an upcoming scheduled quiz can be refreshed." }, 409);
    }
    requestedQuiz = quiz;
    quizDate = String(quiz.quiz_date);
    churchIds = [String(quiz.church_id)];
  } else if (cronAuthorized) {
    const { data: churchRows } = await client
      .from("users")
      .select("placeId")
      .not("placeId", "is", null);
    churchIds = Array.from(new Set([
      GLOBAL_VISITOR_CHURCH_ID,
      ...(churchRows ?? []).map((row) => String(row.placeId ?? "").trim()).filter(Boolean),
    ]));
  } else {
    let userId = "";
    try {
      userId = (await authenticatedUser(request)).id;
    } catch (_) {
      return jsonResponse({ error: "Forbidden." }, 403);
    }
    if (preparing) return jsonResponse({ error: "Forbidden." }, 403);
    if (!hasReachedJamaicaHour(7)) {
      return jsonResponse({ error: "Today's quiz opens at 7:00 AM Jamaica time." }, 425);
    }
    churchIds = [profileQuizChurchId(await userProfile(client, userId))];
  }

  const runId = await createGenerationRun(
    client,
    quizDate,
    regenerating ? "developer_refresh" : preparing ? "cron_prepare" : cronAuthorized ? "cron_release" : "user",
  );
  const availableAt = quizReleaseAt(quizDate);
  const expiresAt = quizReleaseAt(dateOffset(quizDate, 1));
  const prompt = `You are creating Bible Quiz questions for Grace Connect, a Christian church app.
Generate 12 varied, fact-based, respectful multiple-choice questions strictly grounded in Scripture.
The Jamaica release date is ${quizDate}. Avoid famous starter questions and paraphrases of the same fact.
Mix Old Testament, Gospels, Acts, Epistles, wisdom, prophets, parables, miracles, women and men of faith, and Christian living.
Each question needs four distinct options, one unambiguous correct answer, a concise explanation, and accurate references.
Avoid denomination-specific interpretations, tricks, prophecy-date predictions, prosperity claims, and copyrighted quotations.
Return valid JSON only in this shape:
{"questions":[{"question":"string","options":["string","string","string","string"],"correct_option_index":0,"correct_answer":"string","explanation":"string","scripture_references":["Book Chapter:Verse"],"category":"string","difficulty":"easy"}]}`;

  let aiResponse: unknown = null;
  let aiStatus = "not_called";
  let aiAttempted = false;
  const ensureAiResponse = async () => {
    if (aiAttempted) return;
    aiAttempted = true;
    try {
      aiResponse = await callHuggingFaceJson(prompt, 1800);
      aiStatus = Array.isArray((aiResponse as AiQuizResponse | null)?.questions)
        ? "received"
        : "invalid";
    } catch (_) {
      aiStatus = "failed";
    }
  };
  await updateGenerationRun(client, runId, {
    churches_checked: churchIds.length,
    ai_status: aiStatus,
  });

  let published = 0;
  let scheduled = 0;
  let skippedExisting = 0;
  let failedChurches = 0;
  const sources = new Set<string>();
  const issues: GenerationIssue[] = [];

  for (const churchId of churchIds) {
    const existingResult = requestedQuiz
      ? { data: requestedQuiz }
      : await client
        .from("daily_bible_quizzes")
        .select("*")
        .eq("church_id", churchId)
        .eq("quiz_date", quizDate)
        .maybeSingle();
    const existing = existingResult.data as Record<string, unknown> | null;

    if (existing?.status === "published") {
      if (shouldPublish) await publishQuiz(client, existing, churchId, issues);
      skippedExisting++;
      continue;
    }

    const existingReady = existing?.id
      ? await quizHasExactlyFiveQuestions(client, String(existing.id))
      : false;
    if (!regenerating && existingReady && existing?.status === "scheduled") {
      if (shouldPublish) {
        await publishQuiz(client, existing, churchId, issues);
        published++;
      } else {
        scheduled++;
      }
      skippedExisting++;
      continue;
    }

    const recentHashes = await recentQuestionHashes(client, churchId, quizDate);
    if (regenerating && existing?.id) {
      const { data: currentRows } = await client
        .from("daily_bible_quiz_questions")
        .select("question_hash, question_text, correct_answer, scripture_references, category, difficulty, option_a, option_b, option_c, option_d, correct_option_index, explanation")
        .eq("quiz_id", existing.id);
      for (const row of currentRows ?? []) {
        const hash = String(row.question_hash ?? "").trim();
        if (hash) recentHashes.add(hash);
        const candidate = validateQuestion({
          question: row.question_text,
          options: [row.option_a, row.option_b, row.option_c, row.option_d],
          correct_option_index: row.correct_option_index,
          correct_answer: row.correct_answer,
          explanation: row.explanation,
          scripture_references: row.scripture_references,
          category: row.category,
          difficulty: row.difficulty,
        });
        if (candidate) recentHashes.add(await hashQuestion(candidate));
      }
    }

    // Scheduled quizzes publish exactly as reviewed. AI is only called when a
    // quiz really needs to be generated or deliberately refreshed.
    await ensureAiResponse();
    const selected = await selectFiveQuestions(
      aiResponse,
      `${quizDate}:${churchId}:${regenerating ? crypto.randomUUID() : "scheduled"}`,
      recentHashes,
    );
    sources.add(selected.source);
    const validationNotes = selected.source === "fallback"
      ? selected.reusedRecent
        ? "AI response was unavailable or invalid; curated questions were used and recent repeats were avoided where possible."
        : "AI response was unavailable or invalid; a varied curated set was used."
      : selected.reusedRecent
        ? "AI generated the quiz; recent semantic repeats were avoided where possible."
        : null;

    let quiz = existing;
    let quizError: { message: string } | null = null;
    if (!quiz) {
      const inserted = await client
        .from("daily_bible_quizzes")
        .insert({
          church_id: churchId,
          quiz_date: quizDate,
          available_at: availableAt.toISOString(),
          expires_at: expiresAt.toISOString(),
          status: "draft",
          generation_source: selected.source,
          generation_status: "pending",
          notification_sent_at: null,
          validation_notes: validationNotes,
        })
        .select("*")
        .single();
      quiz = inserted.data;
      quizError = inserted.error;
    }
    if (quizError || !quiz) {
      failedChurches++;
      issues.push({ church_id: churchId, stage: "quiz_upsert", message: quizError?.message ?? "Quiz row could not be saved." });
      continue;
    }

    const questions = [];
    for (const question of selected.questions) {
      questions.push({
        ...question,
        question_hash: await hashQuestion(question),
      });
    }
    const targetStatus = shouldPublish ? "published" : "scheduled";
    const { error: replacementError } = await client.rpc(
      "replace_daily_bible_quiz_questions",
      {
        p_quiz_id: quiz.id,
        p_questions: questions,
        p_generation_source: selected.source,
        p_generation_status: selected.source === "ai" ? "generated" : "fallback",
        p_validation_notes: validationNotes,
        p_status: targetStatus,
      },
    );
    if (replacementError) {
      failedChurches++;
      issues.push({ church_id: churchId, stage: "atomic_question_replace", message: replacementError.message });
      if (!regenerating) {
        await client.from("daily_bible_quizzes").update({ status: "failed", generation_status: "failed" }).eq("id", quiz.id);
      }
      continue;
    }

    if (shouldPublish) {
      await publishQuiz(client, { ...quiz, status: "published", notification_sent_at: null }, churchId, issues);
      published++;
    } else {
      scheduled++;
    }
  }

  await updateGenerationRun(client, runId, {
    completed_at: new Date().toISOString(),
    churches_checked: churchIds.length,
    quizzes_published: published,
    ai_status: aiStatus,
    source_summary: Array.from(sources).join(",") || "none",
    error_message: issues.length
      ? issues.map((issue) => `${issue.church_id}:${issue.stage}:${issue.message}`).slice(0, 5).join(" | ")
      : null,
    metadata: { action, scheduled, skipped_existing: skippedExisting, failed_churches: failedChurches, issues },
  });

  if (regenerating && failedChurches > 0) {
    return jsonResponse({ error: issues[0]?.message ?? "Unable to refresh scheduled quiz." }, 500);
  }
  return jsonResponse({
    ok: true,
    action,
    quiz_date: quizDate,
    churches_checked: churchIds.length,
    quizzes_published: published,
    quizzes_scheduled: scheduled,
    source: Array.from(sources).join(",") || "existing",
  });
});
