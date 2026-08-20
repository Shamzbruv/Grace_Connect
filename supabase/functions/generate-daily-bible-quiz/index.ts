import {
  accessTokenFromRequest,
  anonClient,
  authenticatedUser,
  callAiJson,
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
import {
  canonicalQuizFactKeys,
  rotatingQuizFactExclusions,
} from "../_shared/quiz_uniqueness.ts";
import {
  bibleChapterFromKey,
  bibleChapterFromReference,
  BibleChapterText,
  fetchBibleChapter,
  isChapterStudyDate,
} from "../_shared/bible_chapters.ts";

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

type QuizUniquenessSettings = {
  guaranteeUnique: boolean;
  relaxedHistoryDays: number;
};

async function hashQuestion(question: QuizQuestion): Promise<string> {
  const factKeys = canonicalQuizFactKeys(question);
  if (factKeys.length === 0) {
    throw new Error("A canonical Scripture fact key could not be created.");
  }
  const hash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(factKeys.join("|")),
  );
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function validateQuestion(
  value: unknown,
  requiredChapterKey: string | null = null,
): QuizQuestion | null {
  const q = value as QuizQuestion | null;
  if (!q || typeof q.question !== "string") return null;
  if (!Array.isArray(q.options) || q.options.length !== 4) return null;
  const options = q.options.map((option) => String(option ?? "").trim());
  if (options.some((option) => option.length < 1)) return null;
  if (new Set(options.map((option) => option.toLowerCase())).size !== 4) {
    return null;
  }
  const index = Number(q.correct_option_index);
  if (!Number.isInteger(index) || index < 0 || index > 3) return null;
  if (String(q.correct_answer ?? "").trim() !== options[index]) return null;
  if (!String(q.explanation ?? "").trim()) return null;
  if (
    !Array.isArray(q.scripture_references) || q.scripture_references.length < 1
  ) return null;
  if (
    !q.scripture_references.every((ref) =>
      /^[1-3]?\s?[A-Za-z]+(?:\s[A-Za-z]+)*\s+\d{1,3}:\d{1,3}/.test(String(ref))
    )
  ) {
    return null;
  }
  if (
    requiredChapterKey &&
    !q.scripture_references.every((ref) =>
      bibleChapterFromReference(String(ref))?.key === requiredChapterKey
    )
  ) return null;

  // AI-generated multiple choice reliably puts the correct answer first.
  // Shuffle each question's options into a random order so the correct
  // answer's on-screen letter is unpredictable, and recompute
  // correct_option_index/correct_answer to match the new order.
  const shuffledOrder = [0, 1, 2, 3];
  for (let i = shuffledOrder.length - 1; i > 0; i--) {
    const random = new Uint32Array(1);
    crypto.getRandomValues(random);
    const j = random[0] % (i + 1);
    [shuffledOrder[i], shuffledOrder[j]] = [shuffledOrder[j], shuffledOrder[i]];
  }
  const shuffledOptions = shuffledOrder.map((originalIndex) =>
    options[originalIndex]
  ) as [string, string, string, string];
  const shuffledIndex = shuffledOrder.indexOf(index);

  return {
    question: q.question.trim(),
    options: shuffledOptions,
    correct_option_index: shuffledIndex,
    correct_answer: shuffledOptions[shuffledIndex],
    explanation: String(q.explanation).trim(),
    scripture_references: q.scripture_references.map((ref) =>
      String(ref).trim()
    ),
    category: String(q.category ?? "Bible").trim(),
    difficulty:
      (["easy", "medium", "hard"].includes(String(q.difficulty))
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

function seededQuestionSet(
  questions: QuizQuestion[],
  seed: string,
  blockedFactKeys: Set<string>,
): QuizQuestion[] {
  const uniqueByFact = new Map<
    string,
    { question: QuizQuestion; factKeys: string[]; index: number }
  >();
  for (let index = 0; index < questions.length; index++) {
    const question = questions[index];
    const factKeys = canonicalQuizFactKeys(question);
    if (factKeys.length === 0) continue;
    // A question with multiple references collides when any passage+answer
    // key was already used. This also rejects paraphrases inside one AI reply.
    if (factKeys.some((key) => uniqueByFact.has(key))) continue;
    const item = { question, factKeys, index };
    for (const key of factKeys) {
      uniqueByFact.set(key, item);
    }
  }

  const annotated = Array.from(new Set(uniqueByFact.values()));
  const pool = annotated.filter((item) =>
    !item.factKeys.some((key) => blockedFactKeys.has(key))
  );
  const decorated = pool.map((item) => ({
    question: item.question,
    factKeys: item.factKeys,
    score: seedScore(`${seed}:${item.index}:${item.question.question}`),
  }));
  decorated.sort((left, right) => left.score - right.score);
  const selected: typeof decorated = [];
  const selectedKeys = new Set<string>();
  for (const item of decorated) {
    if (item.factKeys.some((key) => selectedKeys.has(key))) continue;
    selected.push(item);
    item.factKeys.forEach((key) => selectedKeys.add(key));
    if (selected.length === 5) break;
  }
  return selected.map((item) => item.question);
}

async function selectFiveQuestions(
  aiResponse: unknown,
  seed: string,
  blockedFactKeys: Set<string>,
  guaranteeUnique: boolean,
  requiredChapterKey: string | null = null,
): Promise<{
  questions: QuizQuestion[];
  source: "ai" | "fallback" | "mixed";
  reusedRecent: boolean;
}> {
  const candidates =
    Array.isArray((aiResponse as AiQuizResponse | null)?.questions)
      ? (aiResponse as AiQuizResponse).questions ?? []
      : [];
  const valid = candidates.map((candidate) =>
    validateQuestion(candidate, requiredChapterKey)
  ).filter((
    q,
  ): q is QuizQuestion => q != null);
  if (valid.length >= 5) {
    const selected = await seededQuestionSet(
      valid,
      seed,
      blockedFactKeys,
    );
    if (selected.length === 5) {
      return { questions: selected, reusedRecent: false, source: "ai" };
    }
  }

  // Merge fresh AI candidates with the curated bank. The fallback order is
  // deterministic for a release slot and blocked facts are never reintroduced.
  // In relaxed mode the RPC only blocks the configured recent-history window,
  // so an older fact can return without violating that window.
  const selected = await seededQuestionSet(
    [...valid, ...(requiredChapterKey ? [] : fallbackQuizQuestions)],
    seed,
    blockedFactKeys,
  );
  if (selected.length === 5) {
    const selectedAiFacts = new Set(
      valid.flatMap((question) => canonicalQuizFactKeys(question)),
    );
    const aiCount = selected.filter((question) =>
      canonicalQuizFactKeys(question).some((key) =>
        selectedAiFacts.has(key)
      )
    ).length;
    return {
      questions: selected,
      source: aiCount === 0 ? "fallback" : aiCount === 5 ? "ai" : "mixed",
      reusedRecent: false,
    };
  }

  // A bare "fewer than five facts available" message was indistinguishable
  // between "the AI returned nothing usable" and "it returned plenty, but
  // none passed validation" -- these have completely different fixes, and
  // guessing between them from production data alone is what cost the most
  // time diagnosing this. The counts below make that visible directly in
  // quiz_generation_runs.error_message without needing Edge Function logs.
  throw new Error(
    (guaranteeUnique
      ? "Strict quiz uniqueness is enabled, but fewer than five unseen Scripture facts are available. No questions were replaced."
      : "Fewer than five facts outside the configured recent-history window are available. No questions were replaced.") +
      ` [diagnostic: ${candidates.length} raw candidate(s) received, ${valid.length} passed validation, ${blockedFactKeys.size} fact(s) already blocked]`,
  );
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

async function quizUniquenessSettings(
  client: ReturnType<typeof serviceClient>,
): Promise<QuizUniquenessSettings> {
  const { data, error } = await client
    .from("daily_content_generation_settings")
    .select("quiz_guarantee_unique, relaxed_quiz_history_days")
    .eq("id", true)
    .single();
  if (error || !data) {
    throw new Error(
      `Quiz uniqueness settings could not be verified: ${
        error?.message ?? "missing singleton row"
      }`,
    );
  }
  return {
    guaranteeUnique: data.quiz_guarantee_unique !== false,
    relaxedHistoryDays: Math.max(
      1,
      Math.min(Number(data.relaxed_quiz_history_days ?? 60), 3650),
    ),
  };
}

async function blockedQuestionFactKeys(
  client: ReturnType<typeof serviceClient>,
  churchId: string,
  quizDate: string,
): Promise<Set<string>> {
  // The aggregate RPC has no PostgREST row cap or giant quiz-id URL. It reads
  // the singleton setting itself and returns every retained canonical key in
  // strict mode (plus all same-day global/church variants).
  const { data, error } = await client.rpc(
    "get_blocked_daily_bible_quiz_fact_keys",
    { p_church_id: churchId, p_quiz_date: quizDate },
  );
  if (error) {
    throw new Error(
      `Quiz fact history could not be verified: ${error.message}`,
    );
  }
  if (!Array.isArray(data)) {
    throw new Error("Quiz fact history returned an invalid response.");
  }
  return new Set(
    data.map(String).map((key) => key.trim()).filter(Boolean),
  );
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
  _client: ReturnType<typeof serviceClient>,
  request: Request,
): Promise<boolean> {
  try {
    await authenticatedUser(request);
    const accessToken = accessTokenFromRequest(request);
    if (!accessToken) return false;
    // Reuse the database's exact developer identity contract. It performs the
    // linked-user check first and only falls back to a case-insensitive exact
    // email match for an unlinked account, avoiding ILIKE wildcard semantics.
    const { data: developerRole, error } = await anonClient(accessToken).rpc(
      "current_developer_role",
    );
    if (error) return false;
    return scheduledQuizMutationRoles.has(
      String(developerRole ?? "").trim().toLowerCase(),
    );
  } catch (_) {
    return false;
  }
}

type DailyWordStudyContext = {
  motivationId: string;
  chapter: BibleChapterText;
};

async function dailyWordStudyContext(
  client: ReturnType<typeof serviceClient>,
  quizDate: string,
): Promise<DailyWordStudyContext> {
  const { data, error } = await client
    .from("daily_motivations")
    .select("id,status,has_study_quiz,scripture_chapter_key")
    .eq("publish_date", quizDate)
    .maybeSingle();
  if (error || !data) {
    throw new Error(
      "The linked Daily Word must be prepared before this chapter-study quiz.",
    );
  }
  const key = String(data.scripture_chapter_key ?? "").trim();
  const chapter = bibleChapterFromKey(key);
  if (
    data.has_study_quiz !== true ||
    !["scheduled", "published"].includes(String(data.status)) ||
    !chapter
  ) {
    throw new Error(
      "The linked Daily Word does not have a valid study chapter.",
    );
  }
  return {
    motivationId: String(data.id),
    chapter: await fetchBibleChapter(chapter),
  };
}

async function publishQuiz(
  client: ReturnType<typeof serviceClient>,
  quiz: Record<string, unknown>,
  churchId: string,
  issues: GenerationIssue[],
): Promise<boolean> {
  const quizId = String(quiz.id);
  const { data: publishedQuiz, error: publishError } = await client.rpc(
    "publish_daily_bible_quiz_if_unique",
    { p_quiz_id: quizId },
  );
  if (publishError || !publishedQuiz) {
    issues.push({
      church_id: churchId,
      stage: "strict_uniqueness_validation",
      message: publishError?.message ??
        "Quiz uniqueness could not be validated before release.",
    });
    return false;
  }
  if (quiz.notification_sent_at || publishedQuiz.notification_sent_at) {
    return true;
  }
  if (churchId === GLOBAL_VISITOR_CHURCH_ID) {
    await client
      .from("daily_bible_quizzes")
      .update({
        notification_sent_at: new Date().toISOString(),
        notification_claimed_at: null,
      })
      .eq("id", quizId)
      .is("notification_sent_at", null);
    return true;
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
  if (!claimed) return true;

  const title = "Daily Bible Quiz Is Ready";
  const body = quiz.quiz_mode === "chapter_study"
    ? "Your 5-question Daily Word chapter challenge is live. See what you remember from today’s reading."
    : "Today’s 5-question Bible pop quiz is live. Can you earn 100 points?";
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
    return true;
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
    return true;
  }
}

// Every audience is meant to see identical content. If Grace Connect
// Global's quiz for the day already published in an earlier run (the
// common case -- Global is processed first and usually succeeds well
// before a later run tries a church that doesn't have one yet), reuse its
// exact stored questions instead of making a fresh AI call. This is what
// makes "always the same as Global" hold across separate invocations, not
// just within a single run.
async function loadPublishedGlobalSelection(
  client: ReturnType<typeof serviceClient>,
  quizDate: string,
  expectedChapterKey: string | null,
  expectedDailyWordId: string | null,
): Promise<
  {
    questions: QuizQuestion[];
    source: "ai" | "fallback" | "mixed";
    reusedRecent: boolean;
  } | null
> {
  // "scheduled" counts, not just "published": Global is routinely prepared
  // well ahead of release, so by the time a still-missing church is retried,
  // Global's real question set usually already exists but hasn't been
  // released to members yet. Both states have already passed
  // replace_daily_bible_quiz_questions (the DB-level fact-conflict guard),
  // so both are equally safe to mirror.
  const { data: quiz } = await client
    .from("daily_bible_quizzes")
    .select(
      "id, generation_source, quiz_mode, study_chapter_key, source_daily_motivation_id",
    )
    .eq("church_id", GLOBAL_VISITOR_CHURCH_ID)
    .eq("quiz_date", quizDate)
    .in("status", ["scheduled", "published"])
    .maybeSingle();
  if (!quiz?.id) return null;
  // Only mirror Global if it was built for today's exact contract. A stale
  // or mismatched row (wrong chapter link, wrong quiz_mode) must never be
  // copied onto another church just because it happens to exist.
  const contractMatches = expectedChapterKey
    ? quiz.quiz_mode === "chapter_study" &&
      quiz.study_chapter_key === expectedChapterKey &&
      quiz.source_daily_motivation_id === expectedDailyWordId
    : quiz.quiz_mode === "pop_quiz" && quiz.study_chapter_key == null &&
      quiz.source_daily_motivation_id == null;
  if (!contractMatches) return null;

  const { data: rows, error } = await client
    .from("daily_bible_quiz_questions")
    .select(
      "question_order, question_text, option_a, option_b, option_c, option_d, correct_option_index, correct_answer, explanation, scripture_references, category, difficulty",
    )
    .eq("quiz_id", quiz.id)
    .order("question_order");
  if (error || !rows || rows.length !== 5) return null;

  const questions: QuizQuestion[] = rows.map((row) => ({
    question: String(row.question_text ?? ""),
    options: [
      String(row.option_a ?? ""),
      String(row.option_b ?? ""),
      String(row.option_c ?? ""),
      String(row.option_d ?? ""),
    ],
    correct_option_index: Number(row.correct_option_index),
    correct_answer: String(row.correct_answer ?? ""),
    explanation: String(row.explanation ?? ""),
    scripture_references: Array.isArray(row.scripture_references)
      ? row.scripture_references.map(String)
      : [],
    category: String(row.category ?? "Bible"),
    difficulty: (["easy", "medium", "hard"].includes(
        String(row.difficulty),
      )
      ? row.difficulty
      : "easy") as "easy" | "medium" | "hard",
  }));
  const source = (["ai", "fallback", "mixed"].includes(
      String(quiz.generation_source),
    )
    ? quiz.generation_source
    : "ai") as "ai" | "fallback" | "mixed";
  return { questions, source, reusedRecent: false };
}

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "POST required." }, 405);
  }

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
      return jsonResponse(
        { error: "Quiz refresh permission is required." },
        403,
      );
    }
    const quizId = String(requestBody.quiz_id ?? "").trim();
    if (!quizId) return jsonResponse({ error: "Quiz ID is required." }, 400);
    const { data: quiz } = await client
      .from("daily_bible_quizzes")
      .select("*")
      .eq("id", quizId)
      .maybeSingle();
    if (
      !quiz || quiz.status !== "scheduled" ||
      new Date(quiz.available_at) <= new Date()
    ) {
      return jsonResponse({
        error: "Only an upcoming scheduled quiz can be refreshed.",
      }, 409);
    }
    requestedQuiz = quiz;
    quizDate = String(quiz.quiz_date);
    churchIds = [String(quiz.church_id)];
  } else if (cronAuthorized) {
    const { data: churchRows } = await client
      .from("users")
      .select("placeId")
      .not("placeId", "is", null);
    churchIds = Array.from(
      new Set([
        GLOBAL_VISITOR_CHURCH_ID,
        ...(churchRows ?? []).map((row) => String(row.placeId ?? "").trim())
          .filter(Boolean),
      ]),
    );
  } else {
    let userId = "";
    try {
      userId = (await authenticatedUser(request)).id;
    } catch (_) {
      return jsonResponse({ error: "Forbidden." }, 403);
    }
    if (preparing) return jsonResponse({ error: "Forbidden." }, 403);
    if (!hasReachedJamaicaHour(7)) {
      return jsonResponse({
        error: "Today's quiz opens at 7:00 AM Jamaica time.",
      }, 425);
    }
    churchIds = [profileQuizChurchId(await userProfile(client, userId))];
  }

  const runId = await createGenerationRun(
    client,
    quizDate,
    regenerating
      ? "developer_refresh"
      : preparing
      ? "cron_prepare"
      : cronAuthorized
      ? "cron_release"
      : "user",
  );
  let uniquenessSettings: QuizUniquenessSettings;
  try {
    uniquenessSettings = await quizUniquenessSettings(client);
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Quiz uniqueness settings could not be verified.";
    await updateGenerationRun(client, runId, {
      completed_at: new Date().toISOString(),
      churches_checked: churchIds.length,
      ai_status: "not_called",
      error_message: message,
    });
    return jsonResponse({ error: message }, 503);
  }
  const availableAt = quizReleaseAt(quizDate);
  const expiresAt = quizReleaseAt(dateOffset(quizDate, 1));
  const chapterStudy = isChapterStudyDate(quizDate);
  let studyContext: DailyWordStudyContext | null = null;
  if (chapterStudy) {
    try {
      studyContext = await dailyWordStudyContext(client, quizDate);
    } catch (error) {
      const message = error instanceof Error
        ? error.message
        : "The Daily Word study chapter could not be loaded.";
      await updateGenerationRun(client, runId, {
        completed_at: new Date().toISOString(),
        churches_checked: churchIds.length,
        ai_status: "not_called",
        error_message: message,
        metadata: { action, quiz_mode: "chapter_study" },
      });
      return jsonResponse({ error: message }, 503);
    }
  }
  const quizPrompt = (blockedFactKeys: Set<string>, variationBatch = 0) =>
    chapterStudy && studyContext
      ? `You are creating a chapter-study Bible Quiz for Grace Connect.
The Daily Word asked members to study ${studyContext.chapter.book} ${studyContext.chapter.chapter}. Every question and every scripture reference MUST be answerable solely from this exact chapter. Do not refer to any other Bible chapter.
Public-domain World English Bible chapter text:
${studyContext.chapter.text}

Generate 12 varied, fact-based multiple-choice questions. Cover different people, actions, statements, sequence, places, causes, and outcomes found in the supplied chapter. Avoid five paraphrases of one event.
The Jamaica release date is ${quizDate}. This is variation batch ${variationBatch}.
Each question needs four distinct options, one unambiguous correct answer, a concise explanation grounded in the supplied text, and references only in the form "${studyContext.chapter.book} ${studyContext.chapter.chapter}:Verse".
Do not reuse these canonical passage-and-answer facts: ${
        rotatingQuizFactExclusions(blockedFactKeys, variationBatch).join(
          ", ",
        ) ||
        "none"
      }.
Avoid tricks, denomination-specific interpretation, prophecy-date predictions, prosperity claims, and copyrighted quotations.
Return valid JSON only in this shape:
{"questions":[{"question":"string","options":["string","string","string","string"],"correct_option_index":0,"correct_answer":"string","explanation":"string","scripture_references":["Book Chapter:Verse"],"category":"string","difficulty":"easy"}]}`
      : `You are creating Bible Quiz questions for Grace Connect, a Christian church app.
Generate 12 varied, fact-based, respectful multiple-choice questions strictly grounded in Scripture.
The Jamaica release date is ${quizDate}. Avoid famous starter questions and paraphrases of the same fact.
This is variation batch ${variationBatch}; deliberately explore less commonly used passages and facts.
Mix Old Testament, Gospels, Acts, Epistles, wisdom, prophets, parables, miracles, women and men of faith, and Christian living.
Each question needs four distinct options, one unambiguous correct answer, a concise explanation, and accurate references.
Do not reuse these canonical passage-and-answer facts: ${
        rotatingQuizFactExclusions(blockedFactKeys, variationBatch).join(
          ", ",
        ) ||
        "none"
      }.
Avoid denomination-specific interpretations, tricks, prophecy-date predictions, prosperity claims, and copyrighted quotations.
Return valid JSON only in this shape:
{"questions":[{"question":"string","options":["string","string","string","string"],"correct_option_index":0,"correct_answer":"string","explanation":"string","scripture_references":["Book Chapter:Verse"],"category":"string","difficulty":"easy"}]}`;

  let sharedAiResponse: unknown = null;
  let aiStatus = "not_called";
  let sharedAiAttempted = false;
  // Populated whenever both AI providers come back empty, so the eventual
  // "fewer than five facts available" error can say *why* -- an HTTP
  // failure, a truncated/malformed response, quota, etc. -- instead of
  // leaving every AI failure mode indistinguishable from genuine fact
  // exhaustion, which is what made this expensive to diagnose in production.
  let lastAiDiagnostic: string | null = null;
  // Which provider actually produced the current sharedAiResponse -- surfaced
  // in the run metadata so a Hugging Face outage being silently covered by
  // Gemini (or vice versa) is visible, not just inferred from the absence of
  // an error.
  let lastAiProvider: "huggingface" | "gemini" | null = null;
  const ensureSharedAiResponse = async (blockedFactKeys: Set<string>) => {
    if (sharedAiAttempted) return;
    sharedAiAttempted = true;
    try {
      // The baseline is shared for cron scalability, but is seeded with a real
      // audience history (global is processed first for cron runs). Any later
      // church that needs more candidates gets its own rotating targeted calls.
      // callAiJson tries Hugging Face first and only calls Gemini if Hugging
      // Face fails -- Gemini is a backup provider, not a second independent
      // source, so the two must never be blended into one prompt response.
      const { data, diagnostic, provider } = await callAiJson(
        quizPrompt(blockedFactKeys, 0),
        3600,
      );
      sharedAiResponse = data;
      if (diagnostic) lastAiDiagnostic = diagnostic;
      if (provider) lastAiProvider = provider;
      aiStatus =
        Array.isArray((sharedAiResponse as AiQuizResponse | null)?.questions)
          ? "received"
          : "invalid";
    } catch (error) {
      aiStatus = "failed";
      lastAiDiagnostic = `callAiJson threw: ${
        error instanceof Error ? error.message : String(error)
      }`;
    }
  };
  const targetedAiResponse = async (
    blockedFactKeys: Set<string>,
    variationBatch: number,
  ) => {
    try {
      const { data, diagnostic, provider } = await callAiJson(
        quizPrompt(blockedFactKeys, variationBatch),
        3600,
      );
      if (diagnostic) lastAiDiagnostic = diagnostic;
      if (provider) lastAiProvider = provider;
      if (Array.isArray((data as AiQuizResponse | null)?.questions)) {
        aiStatus = "received";
        return data;
      }
      aiStatus = "invalid";
    } catch (error) {
      aiStatus = "failed";
      lastAiDiagnostic = `callAiJson threw: ${
        error instanceof Error ? error.message : String(error)
      }`;
    }
    return null;
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
  const expectedChapterKey = studyContext?.chapter.key ?? null;
  const expectedDailyWordId = studyContext?.motivationId ?? null;
  // Grace Connect Global and every church are meant to see the identical
  // Daily Bible Quiz every day, not an independently generated variant per
  // audience. Whichever audience is processed first in this run selects the
  // real question set; everyone after it reuses that exact selection
  // instead of making its own AI call -- one generation per day total,
  // regardless of how many churches exist, not one per church.
  let canonicalSelection: Awaited<ReturnType<typeof selectFiveQuestions>> | null =
    null;
  // Global is very often already published by the time a later run (a cron
  // retry, or a member opening the app) processes a church that still needs
  // one -- without this, that later run would go straight to its own fresh
  // AI call and could produce different content than what Global already
  // has, defeating "always identical" the moment the two runs don't overlap.
  if (!regenerating) {
    canonicalSelection = await loadPublishedGlobalSelection(
      client,
      quizDate,
      expectedChapterKey,
      expectedDailyWordId,
    );
  }

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
    const existingContractReady = chapterStudy
      ? existing?.quiz_mode === "chapter_study" &&
        existing?.study_chapter_key === expectedChapterKey &&
        existing?.source_daily_motivation_id === expectedDailyWordId
      : existing?.quiz_mode === "pop_quiz" &&
        existing?.study_chapter_key == null &&
        existing?.source_daily_motivation_id == null;
    if (
      !regenerating && existingReady && existingContractReady &&
      existing?.status === "scheduled"
    ) {
      const { error: uniquenessError } = await client.rpc(
        "validate_daily_bible_quiz_uniqueness",
        { p_quiz_id: existing.id },
      );
      if (!uniquenessError) {
        if (shouldPublish) {
          if (await publishQuiz(client, existing, churchId, issues)) {
            published++;
          } else {
            failedChurches++;
          }
        } else {
          scheduled++;
        }
        skippedExisting++;
        continue;
      }
      // A scheduled row created before strict mode may already repeat retained
      // history. Regenerate it in this same release slot instead of skipping it
      // and discovering the conflict only when members try to open the quiz.
    }

    let blockedFactKeys: Set<string>;
    try {
      blockedFactKeys = await blockedQuestionFactKeys(
        client,
        churchId,
        quizDate,
      );
    } catch (error) {
      failedChurches++;
      issues.push({
        church_id: churchId,
        stage: "strict_uniqueness_history",
        message: error instanceof Error
          ? error.message
          : "Quiz fact history could not be verified.",
      });
      continue;
    }
    if (regenerating && existing?.id) {
      const { data: currentRows, error: currentRowsError } = await client
        .from("daily_bible_quiz_questions")
        .select(
          "fact_keys, question_text, correct_answer, scripture_references, category, difficulty, option_a, option_b, option_c, option_d, correct_option_index, explanation",
        )
        .eq("quiz_id", existing.id);
      if (currentRowsError) {
        failedChurches++;
        issues.push({
          church_id: churchId,
          stage: "strict_uniqueness_current_quiz",
          message: currentRowsError.message,
        });
        continue;
      }
      for (const row of currentRows ?? []) {
        if (Array.isArray(row.fact_keys)) {
          row.fact_keys.map(String).map((key) => key.trim()).filter(Boolean)
            .forEach((key) => blockedFactKeys.add(key));
        }
        const candidate = validateQuestion(
          {
            question: row.question_text,
            options: [row.option_a, row.option_b, row.option_c, row.option_d],
            correct_option_index: row.correct_option_index,
            correct_answer: row.correct_answer,
            explanation: row.explanation,
            scripture_references: row.scripture_references,
            category: row.category,
            difficulty: row.difficulty,
          },
          expectedChapterKey,
        );
        if (candidate) {
          canonicalQuizFactKeys(candidate).forEach((key) =>
            blockedFactKeys.add(key)
          );
        }
      }
    }

    // Scheduled quizzes publish exactly as reviewed. AI is only called when a
    // quiz really needs to be generated or deliberately refreshed.
    let selected: Awaited<ReturnType<typeof selectFiveQuestions>> | null =
      null;
    if (!regenerating && canonicalSelection != null) {
      // Mirroring is only safe if none of the canonical facts were already
      // used in *this* church's own retained history -- e.g. Global picked a
      // fact fresh for itself, but this specific church already asked it in
      // an earlier quiz. Falling through to this church's own generation
      // below is what keeps that case from turning into "no quiz today",
      // the exact failure this whole change exists to prevent.
      const canonicalFactKeys = canonicalSelection.questions.flatMap((q) =>
        canonicalQuizFactKeys(q)
      );
      const hasConflict = canonicalFactKeys.some((key) =>
        blockedFactKeys.has(key)
      );
      if (!hasConflict) selected = canonicalSelection;
    }
    if (selected != null) {
      // Another audience earlier in this same run already produced the
      // day's real question set; every later audience gets the identical
      // five questions instead of triggering its own AI call.
    } else {
    await ensureSharedAiResponse(blockedFactKeys);
    const seed = `${quizDate}:${churchId}:${
      regenerating ? crypto.randomUUID() : "scheduled"
    }`;
    try {
      selected = await selectFiveQuestions(
        sharedAiResponse,
        seed,
        blockedFactKeys,
        uniquenessSettings.guaranteeUnique,
        expectedChapterKey,
      );
    } catch (initialError) {
      // Once the shared pool and curated bank are exhausted, make focused AI
      // requests containing this church's actual canonical exclusions. Merge
      // valid candidates across batches; never weaken the blocked set.
      const accumulated = Array.isArray(
          (sharedAiResponse as AiQuizResponse | null)?.questions,
        )
        ? [...((sharedAiResponse as AiQuizResponse).questions ?? [])]
        : ([] as QuizQuestion[]);
      let targetedError: unknown = initialError;
      for (let batch = 1; batch <= 3; batch++) {
        const targeted = await targetedAiResponse(blockedFactKeys, batch);
        if (Array.isArray((targeted as AiQuizResponse | null)?.questions)) {
          accumulated.push(
            ...((targeted as AiQuizResponse).questions ?? []),
          );
        }
        try {
          selected = await selectFiveQuestions(
            { questions: accumulated },
            seed,
            blockedFactKeys,
            uniquenessSettings.guaranteeUnique,
            expectedChapterKey,
          );
          targetedError = null;
          break;
        } catch (error) {
          targetedError = error;
        }
      }
      if (targetedError != null) {
        failedChurches++;
        const baseMessage = targetedError instanceof Error
          ? targetedError.message
          : initialError instanceof Error
          ? initialError.message
          : "Five unseen Scripture facts were not available.";
        issues.push({
          church_id: churchId,
          stage: "strict_uniqueness_exhausted",
          message: lastAiDiagnostic
            ? `${baseMessage} [last AI call: ${lastAiDiagnostic}]`
            : baseMessage,
        });
        continue;
      }
    }
    }
    if (!regenerating && selected != null) canonicalSelection = selected;
    if (selected == null) {
      failedChurches++;
      issues.push({
        church_id: churchId,
        stage: "strict_uniqueness_exhausted",
        message: lastAiDiagnostic
          ? `Five unseen Scripture facts were not available. [last AI call: ${lastAiDiagnostic}]`
          : "Five unseen Scripture facts were not available.",
      });
      continue;
    }
    sources.add(selected.source);
    const uniquenessNote = uniquenessSettings.guaranteeUnique
      ? "Strict uniqueness verified against all retained published and scheduled Scripture facts."
      : selected.reusedRecent
      ? `Relaxed uniqueness reused a fact after checking the configured ${uniquenessSettings.relaxedHistoryDays}-day window.`
      : `Relaxed uniqueness checked the configured ${uniquenessSettings.relaxedHistoryDays}-day window.`;
    const validationNotes = chapterStudy && studyContext
      ? `All five questions are grounded in ${studyContext.chapter.book} ${studyContext.chapter.chapter}, the linked Daily Word chapter. ${uniquenessNote}`
      : `Pop quiz. ${uniquenessNote}`;

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
          quiz_mode: chapterStudy ? "chapter_study" : "pop_quiz",
          study_chapter_key: expectedChapterKey,
          source_daily_motivation_id: expectedDailyWordId,
        })
        .select("*")
        .single();
      quiz = inserted.data;
      quizError = inserted.error;
    }
    if (quizError || !quiz) {
      failedChurches++;
      issues.push({
        church_id: churchId,
        stage: "quiz_upsert",
        message: quizError?.message ?? "Quiz row could not be saved.",
      });
      continue;
    }

    if (existing) {
      const configured = await client
        .from("daily_bible_quizzes")
        .update({
          quiz_mode: chapterStudy ? "chapter_study" : "pop_quiz",
          study_chapter_key: expectedChapterKey,
          source_daily_motivation_id: expectedDailyWordId,
        })
        .eq("id", quiz.id)
        .select("*")
        .single();
      if (configured.error || !configured.data) {
        failedChurches++;
        issues.push({
          church_id: churchId,
          stage: "quiz_study_contract",
          message: configured.error?.message ??
            "Quiz study linkage could not be saved.",
        });
        continue;
      }
      quiz = configured.data;
    }
    if (!quiz) {
      failedChurches++;
      issues.push({
        church_id: churchId,
        stage: "quiz_study_contract",
        message: "Quiz study linkage returned no row.",
      });
      continue;
    }
    const readyQuiz = quiz;

    const questions = [];
    for (const question of selected.questions) {
      questions.push({
        ...question,
        fact_keys: canonicalQuizFactKeys(question),
        question_hash: await hashQuestion(question),
      });
    }
    const targetStatus = shouldPublish ? "published" : "scheduled";
    const { error: replacementError } = await client.rpc(
      "replace_daily_bible_quiz_questions",
      {
        p_quiz_id: readyQuiz.id,
        p_questions: questions,
        p_generation_source: selected.source,
        p_generation_status: selected.source === "fallback"
          ? "fallback"
          : "generated",
        p_validation_notes: validationNotes,
        p_status: targetStatus,
      },
    );
    if (replacementError) {
      failedChurches++;
      issues.push({
        church_id: churchId,
        stage: "atomic_question_replace",
        message: replacementError.message,
      });
      if (!regenerating) {
        await client.from("daily_bible_quizzes").update({
          status: "failed",
          generation_status: "failed",
        }).eq("id", readyQuiz.id);
      }
      continue;
    }

    if (shouldPublish) {
      if (
        await publishQuiz(
          client,
          { ...readyQuiz, status: "published", notification_sent_at: null },
          churchId,
          issues,
        )
      ) {
        published++;
      } else {
        failedChurches++;
      }
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
      ? issues.map((issue) =>
        `${issue.church_id}:${issue.stage}:${issue.message}`
      ).slice(0, 5).join(" | ")
      : null,
    metadata: {
      action,
      quiz_mode: chapterStudy ? "chapter_study" : "pop_quiz",
      study_chapter_key: expectedChapterKey,
      scheduled,
      skipped_existing: skippedExisting,
      failed_churches: failedChurches,
      ai_provider: lastAiProvider,
      issues,
    },
  });

  if (failedChurches > 0) {
    return jsonResponse({
      error: issues[0]?.message ??
        "One or more quizzes could not be generated without repeating a fact.",
      action,
      quiz_date: quizDate,
      quiz_mode: chapterStudy ? "chapter_study" : "pop_quiz",
      study_chapter_key: expectedChapterKey,
      churches_checked: churchIds.length,
      quizzes_published: published,
      quizzes_scheduled: scheduled,
      failed_churches: failedChurches,
    }, uniquenessSettings.guaranteeUnique ? 409 : 500);
  }
  return jsonResponse({
    ok: true,
    action,
    quiz_date: quizDate,
    quiz_mode: chapterStudy ? "chapter_study" : "pop_quiz",
    study_chapter_key: expectedChapterKey,
    churches_checked: churchIds.length,
    quizzes_published: published,
    quizzes_scheduled: scheduled,
    source: Array.from(sources).join(",") || "existing",
  });
});
