import {
  accessTokenFromRequest,
  anonClient,
  authenticatedUser,
  callHuggingFaceJson,
  createInAppNotifications,
  handleOptions,
  hasCronSecret,
  hasReachedJamaicaHour,
  jamaicaDateString,
  jsonResponse,
  profileChurchId,
  sendTopicPush,
  serviceClient,
  shortPreview,
  userProfile,
  wordCount,
} from "../_shared/grace.ts";
import {
  BibleChapter,
  bibleChapterFromKey,
  bibleChapterFromReference,
  BibleChapterText,
  fetchBibleChapter,
  isChapterStudyDate,
  shuffledBibleChapters,
} from "../_shared/bible_chapters.ts";

type DailyMotivationAiResponse = {
  title?: string;
  message?: string;
  scripture_reference?: string;
  topic?: string;
};

type DailyWordHistoryItem = {
  title: string;
  message: string;
};

const scheduledContentMutationRoles = new Set([
  "super_developer",
  "support_developer",
  "content_moderator",
  "security_admin",
]);

function normalizedWords(value: string): Set<string> {
  return new Set(
    value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim().split(/\s+/)
      .filter((word) => word.length > 2),
  );
}

function wordSetSimilarity(left: string, right: string): number {
  const leftWords = normalizedWords(left);
  const rightWords = normalizedWords(right);
  if (leftWords.size === 0 || rightWords.size === 0) return 0;
  let overlap = 0;
  for (const word of leftWords) if (rightWords.has(word)) overlap++;
  return overlap / (leftWords.size + rightWords.size - overlap);
}

function validateMotivation(
  value: unknown,
  chapter: BibleChapter,
  history: DailyWordHistoryItem[],
): DailyMotivationAiResponse | null {
  const data = value as DailyMotivationAiResponse | null;
  if (!data) return null;
  const title = String(data.title ?? "").trim();
  const message = String(data.message ?? "").trim();
  const scripture = String(data.scripture_reference ?? "").trim();
  const topic = String(data.topic ?? "").trim();
  const words = wordCount(message);
  if (!title || !message || !scripture) return null;
  if (words < 35 || words > 70) return null;
  if (bibleChapterFromReference(scripture)?.key !== chapter.key) return null;
  const candidate = `${title} ${message}`;
  if (
    history.some((item) =>
      wordSetSimilarity(candidate, `${item.title} ${item.message}`) >= 0.68
    )
  ) return null;
  return { title, message, scripture_reference: scripture, topic };
}

async function usedChapterOwners(
  client: ReturnType<typeof serviceClient>,
): Promise<Map<string, string>> {
  const owners = new Map<string, string>();
  for (let start = 0;; start += 1000) {
    const { data, error } = await client
      .from("daily_word_chapter_history")
      .select("chapter_key,first_daily_motivation_id")
      .order("chapter_key")
      .range(start, start + 999);
    if (error) {
      throw new Error(
        `Daily Word chapter history could not be verified: ${error.message}`,
      );
    }
    for (const row of data ?? []) {
      const key = String(row.chapter_key ?? "").trim();
      if (key) owners.set(key, String(row.first_daily_motivation_id ?? ""));
    }
    if ((data ?? []).length < 1000) break;
  }
  return owners;
}

async function dailyWordHistory(
  client: ReturnType<typeof serviceClient>,
): Promise<DailyWordHistoryItem[]> {
  const history: DailyWordHistoryItem[] = [];
  for (let start = 0;; start += 500) {
    const { data, error } = await client
      .from("daily_word_content_history")
      .select("title,message")
      .order("first_seen_at", { ascending: false })
      .range(start, start + 499);
    if (error) {
      throw new Error(
        `Daily Word wording history could not be verified: ${error.message}`,
      );
    }
    for (const row of data ?? []) {
      history.push({
        title: String(row.title ?? ""),
        message: String(row.message ?? ""),
      });
    }
    if ((data ?? []).length < 500) break;
  }
  return history;
}

async function canRegenerateScheduledContent(
  request: Request,
): Promise<boolean> {
  try {
    await authenticatedUser(request);
    const accessToken = accessTokenFromRequest(request);
    if (!accessToken) return false;
    const { data, error } = await anonClient(accessToken).rpc(
      "current_developer_role",
    );
    if (error) return false;
    return scheduledContentMutationRoles.has(
      String(data ?? "").trim().toLowerCase(),
    );
  } catch (_) {
    return false;
  }
}

async function usableChapter(
  existingKey: string,
  excluded: Set<string>,
): Promise<BibleChapterText> {
  if (existingKey) {
    const existing = bibleChapterFromKey(existingKey);
    if (!existing) {
      throw new Error("The scheduled Daily Word chapter is invalid.");
    }
    return await fetchBibleChapter(existing);
  }
  let providerError = "No unused Bible chapter is available.";
  for (const chapter of shuffledBibleChapters(excluded).slice(0, 30)) {
    try {
      const loaded = await fetchBibleChapter(chapter);
      if (loaded.verses.length >= 8 && loaded.text.length >= 350) return loaded;
      providerError =
        `${chapter.book} ${chapter.chapter} was too short for a five-question study.`;
    } catch (error) {
      providerError = error instanceof Error
        ? error.message
        : "Bible chapter could not be loaded.";
    }
  }
  throw new Error(
    `A fresh study-ready Bible chapter could not be loaded: ${providerError}`,
  );
}

function dailyWordPrompt(
  chapter: BibleChapterText,
  history: DailyWordHistoryItem[],
  attempt: number,
): string {
  const recentExamples = history.slice(0, 35).map((item) =>
    `${item.title}: ${item.message}`
  ).join("\n---\n");
  return `You are preparing a fresh Christian Daily Word for Grace Connect.
Use only the supplied public-domain World English Bible chapter as your factual context.
Chapter: ${chapter.book} ${chapter.chapter}
Chapter text:
${chapter.text}

Write a warm, original 35-70 word reflection for a broad Christian audience. Accurately summarize or apply a distinct idea from this chapter in natural English suitable for a Jamaican church audience. Choose one accurate verse or verse range from this same chapter as scripture_reference. This is generation variation ${attempt}; use different imagery, structure, title, and application from prior content.
Do not copy or closely paraphrase prior Daily Words below, and do not recycle generic encouragement wording:
${recentExamples || "No prior Daily Words."}
Do not make medical, legal, financial, personal-prophecy, or prosperity claims. Do not quote a copyrighted translation.
Return JSON only with title, message, scripture_reference, and topic.`;
}

async function generateFreshDailyWord(
  chapter: BibleChapterText,
  history: DailyWordHistoryItem[],
): Promise<DailyMotivationAiResponse> {
  for (let attempt = 1; attempt <= 4; attempt++) {
    try {
      const value = await callHuggingFaceJson(
        dailyWordPrompt(chapter, history, attempt),
        1000,
      );
      const validated = validateMotivation(value, chapter, history);
      if (validated) return validated;
    } catch (_) {
      // A later variation may recover from an unavailable or malformed reply.
    }
  }
  throw new Error(
    "AI could not create a distinct, chapter-grounded Daily Word. The scheduled slot was left unchanged and will retry.",
  );
}

function dateOffset(dateKey: string, days: number): string {
  const value = new Date(`${dateKey}T12:00:00.000Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

function dailyWordReleaseAt(dateKey: string): Date {
  // Jamaica is UTC-5 year-round; 5:00 AM is 10:00 UTC.
  return new Date(`${dateKey}T10:00:00.000Z`);
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
  if (!["prepare", "release", "regenerate_scheduled"].includes(action)) {
    return jsonResponse({ error: "Unsupported Daily Word action." }, 400);
  }
  const preparing = action === "prepare";
  const regenerating = action === "regenerate_scheduled";
  const cronAuthorized = hasCronSecret(request, "DAILY_MOTIVATION_CRON_SECRET");
  if (regenerating) {
    if (!(await canRegenerateScheduledContent(request))) {
      return jsonResponse({
        error: "Daily Word refresh permission is required.",
      }, 403);
    }
  } else if (preparing && !cronAuthorized) {
    return jsonResponse({ error: "Forbidden." }, 403);
  } else if (!cronAuthorized) {
    let userId = "";
    try {
      userId = (await authenticatedUser(request)).id;
    } catch (_) {
      return jsonResponse({ error: "Forbidden." }, 403);
    }
    if (!hasReachedJamaicaHour(5)) {
      return jsonResponse({
        error: "Today's Daily Word opens at 5:00 AM Jamaica time.",
      }, 425);
    }
    const profile = await userProfile(client, userId);
    if (!profileChurchId(profile)) {
      return jsonResponse({ error: "Church membership required." }, 403);
    }
  }

  const today = jamaicaDateString();
  let publishDate = preparing ? dateOffset(today, 1) : today;
  let existingResult;
  if (regenerating) {
    const motivationId = String(requestBody.motivation_id ?? "").trim();
    if (!motivationId) {
      return jsonResponse({ error: "Daily Word ID is required." }, 400);
    }
    existingResult = await client
      .from("daily_motivations")
      .select("*")
      .eq("id", motivationId)
      .maybeSingle();
    if (!existingResult.data) {
      return jsonResponse(
        { error: "Scheduled Daily Word was not found." },
        404,
      );
    }
    publishDate = String(existingResult.data.publish_date);
    if (
      existingResult.data.status !== "scheduled" ||
      dailyWordReleaseAt(publishDate) <= new Date()
    ) {
      return jsonResponse({
        error: "Only a future scheduled Daily Word can be refreshed.",
      }, 409);
    }
  } else {
    existingResult = await client
      .from("daily_motivations")
      .select("*")
      .eq("publish_date", publishDate)
      .maybeSingle();
  }
  if (existingResult.error) {
    return jsonResponse(
      { error: "Daily Word schedule could not be loaded." },
      503,
    );
  }
  const existing = existingResult.data;

  if (
    preparing && existing?.status === "scheduled" &&
    Number(existing.generation_version ?? 1) >= 2 &&
    existing.has_study_quiz === isChapterStudyDate(publishDate)
  ) {
    return jsonResponse({
      ok: true,
      status: "already_scheduled",
      motivation_id: existing.id,
      publish_date: publishDate,
    });
  }
  if (existing?.is_published && existing?.notification_sent_at) {
    return jsonResponse({
      ok: true,
      status: "already_exists",
      motivation_id: existing.id,
    });
  }

  let saved = null;
  let source = String(existing?.source ?? "ai");

  if (!preparing && !regenerating && existing?.is_published) {
    // Never rewrite content that members may already have read. If the prior
    // delivery stopped midway, only the idempotent notification step is retried.
    saved = existing;
  }

  // Publish the exact row the developer reviewed. Release never silently
  // regenerates scheduled content or changes its date/time slot.
  if (!preparing && !regenerating && existing?.status === "scheduled") {
    const released = await client
      .from("daily_motivations")
      .update({
        status: "published",
        is_published: true,
        published_at: new Date().toISOString(),
      })
      .eq("id", existing.id)
      .select("*")
      .single();
    if (released.error || !released.data) {
      return jsonResponse({
        error: "Unable to publish the scheduled Daily Word.",
      }, 500);
    }
    saved = released.data;
  }

  if (!saved) {
    let history: DailyWordHistoryItem[];
    let chapterOwners: Map<string, string>;
    try {
      [history, chapterOwners] = await Promise.all([
        dailyWordHistory(client),
        usedChapterOwners(client),
      ]);
    } catch (error) {
      return jsonResponse({
        error: error instanceof Error
          ? error.message
          : "Daily Word history could not be verified.",
      }, 503);
    }

    let chapter: BibleChapterText;
    let content: DailyMotivationAiResponse;
    try {
      source = "ai";
      const currentKey = String(existing?.scripture_chapter_key ?? "").trim();
      const retainedKey =
        chapterOwners.get(currentKey) === String(existing?.id ?? "")
          ? currentKey
          : "";
      chapter = await usableChapter(
        retainedKey,
        new Set(chapterOwners.keys()),
      );
      content = await generateFreshDailyWord(chapter, history);
    } catch (error) {
      return jsonResponse({
        error: error instanceof Error
          ? error.message
          : "A fresh Daily Word could not be generated.",
      }, 503);
    }

    const payload = {
      publish_date: publishDate,
      title: content.title,
      message: content.message,
      scripture_reference: content.scripture_reference,
      scripture_chapter_key: chapter.key,
      has_study_quiz: isChapterStudyDate(publishDate),
      topic: content.topic,
      source,
      status: preparing || regenerating ? "scheduled" : "published",
      is_published: !preparing && !regenerating,
      generated_at: new Date().toISOString(),
      published_at: preparing || regenerating ? null : new Date().toISOString(),
      notification_sent_at: null,
      notification_claimed_at: null,
      failure_reason: null,
      generation_version: 2,
    };
    const stored = existing?.id
      ? await client
        .from("daily_motivations")
        .update(payload)
        .eq("id", existing.id)
        .eq("status", existing.status)
        .select("*")
        .single()
      : await client
        .from("daily_motivations")
        .insert(payload)
        .select("*")
        .single();
    if (stored.error || !stored.data) {
      return jsonResponse({
        error: stored.error?.message ?? "Unable to save Daily Word.",
      }, stored.error?.code === "23505" ? 409 : 500);
    }
    saved = stored.data;
  }

  if (preparing || regenerating) {
    return jsonResponse({
      ok: true,
      status: regenerating ? "regenerated" : "scheduled",
      motivation_id: saved.id,
      publish_date: publishDate,
      source,
      scripture_chapter_key: saved.scripture_chapter_key,
      has_study_quiz: saved.has_study_quiz,
    });
  }

  const title = "Grace Connect Daily Word";
  const body = shortPreview(String(saved.message), 120);
  const route = `/daily_word?id=${saved.id}`;

  // Use a reclaimable lease rather than marking delivery complete before FCM
  // accepts it. The retry job can safely reclaim a crashed/failed attempt.
  const claimedAt = new Date().toISOString();
  const staleBefore = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const { data: notificationClaim } = await client
    .from("daily_motivations")
    .update({ notification_claimed_at: claimedAt })
    .eq("id", saved.id)
    .is("notification_sent_at", null)
    .or(
      `notification_claimed_at.is.null,notification_claimed_at.lt.${staleBefore}`,
    )
    .select("id")
    .maybeSingle();
  if (!notificationClaim) {
    return jsonResponse({
      ok: true,
      status: "already_published",
      motivation_id: saved.id,
      publish_date: publishDate,
      source,
      church_topics_attempted: 0,
      push_topics_sent: 0,
    });
  }

  await createInAppNotifications(client, {
    title,
    body,
    type: "daily_motivation",
    route,
    entityTable: "daily_motivations",
    entityId: saved.id,
    preferenceColumn: "notifyDailyMotivation",
  });

  const { data: churchRows } = await client
    .from("users")
    .select("placeId")
    .eq("notifyDailyMotivation", true)
    .not("placeId", "is", null);
  const churches = new Set(
    (churchRows ?? []).map((row) => String(row.placeId ?? "").trim()).filter(
      Boolean,
    ),
  );
  let pushesSent = 0;
  let pushesFailed = 0;
  for (const churchId of churches) {
    const result = await sendTopicPush(client, {
      topic: `church_${churchId}_devotionals`,
      title,
      body,
      route,
      type: "daily_motivation",
      entityTable: "daily_motivations",
      entityId: saved.id,
    });
    if (result.sent) {
      pushesSent++;
    } else {
      pushesFailed++;
    }
  }

  if (pushesFailed === 0) {
    await client
      .from("daily_motivations")
      .update({
        notification_sent_at: new Date().toISOString(),
        notification_claimed_at: null,
      })
      .eq("id", saved.id)
      .eq("notification_claimed_at", claimedAt);
  } else {
    await client
      .from("daily_motivations")
      .update({ notification_claimed_at: null })
      .eq("id", saved.id)
      .eq("notification_claimed_at", claimedAt);
  }

  return jsonResponse({
    ok: pushesFailed === 0,
    motivation_id: saved.id,
    publish_date: publishDate,
    source,
    church_topics_attempted: churches.size,
    push_topics_sent: pushesSent,
    push_topics_failed: pushesFailed,
  });
});
