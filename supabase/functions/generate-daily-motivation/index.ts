import {
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

type DailyMotivationAiResponse = {
  title?: string;
  message?: string;
  scripture_reference?: string;
  topic?: string;
};

const fallbackMotivations: Required<DailyMotivationAiResponse>[] = [
  {
    title: "Walk With Grace Today",
    message:
      "Let today be shaped by faithfulness, patience, and love. Even small acts of obedience can strengthen your witness and encourage someone nearby. Keep your heart steady in God’s Word and take the next right step with grace.",
    scripture_reference: "Galatians 6:9",
    topic: "faithfulness",
  },
  {
    title: "Strength For The Step Ahead",
    message:
      "You do not have to carry today in your own strength. Pause, pray, and let God guide your words, choices, and attitude. A surrendered heart can find peace even when the day feels full.",
    scripture_reference: "Psalm 46:1",
    topic: "strength",
  },
  {
    title: "Choose Peace And Purpose",
    message:
      "Begin today with a quiet confidence that God sees you. Let peace rule your responses, let wisdom guide your pace, and let kindness show others the character of Christ through you.",
    scripture_reference: "Colossians 3:15",
    topic: "peace",
  },
];

function validateMotivation(value: unknown): DailyMotivationAiResponse | null {
  const data = value as DailyMotivationAiResponse | null;
  if (!data) return null;
  const title = String(data.title ?? "").trim();
  const message = String(data.message ?? "").trim();
  const scripture = String(data.scripture_reference ?? "").trim();
  const topic = String(data.topic ?? "").trim();
  const words = wordCount(message);
  if (!title || !message || !scripture) return null;
  if (words < 35 || words > 70) return null;
  if (!/^[1-3]?\s?[A-Za-z]+(?:\s[A-Za-z]+)*\s+\d{1,3}:\d{1,3}/.test(scripture)) {
    return null;
  }
  return { title, message, scripture_reference: scripture, topic };
}

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "POST required." }, 405);

  const client = serviceClient();
  const cronAuthorized = hasCronSecret(request, "DAILY_MOTIVATION_CRON_SECRET");
  if (!cronAuthorized) {
    let userId = "";
    try {
      userId = (await authenticatedUser(request)).id;
    } catch (_) {
      return jsonResponse({ error: "Forbidden." }, 403);
    }
    if (!hasReachedJamaicaHour(5)) {
      return jsonResponse({ error: "Today's Daily Word opens at 5:00 AM Jamaica time." }, 425);
    }
    const profile = await userProfile(client, userId);
    if (!profileChurchId(profile)) return jsonResponse({ error: "Church membership required." }, 403);
  }

  const publishDate = jamaicaDateString();

  const existing = await client
    .from("daily_motivations")
    .select("*")
    .eq("publish_date", publishDate)
    .maybeSingle();

  if (existing.data?.is_published && existing.data?.notification_sent_at) {
    return jsonResponse({
      ok: true,
      status: "already_exists",
      motivation_id: existing.data.id,
    });
  }

  const prompt = `You are preparing a short Christian Daily Word for a church app called Grace Connect.
Create a warm, encouraging, Bible-centered message for a broad Christian audience.
Use respectful, clear English that feels natural for a Jamaican church audience.
Keep the message between 35 and 70 words.
Include one accurate Bible verse reference only, such as "Isaiah 41:10".
Do not invent Bible passages or claim God has personally promised a specific outcome to an individual.
Do not make medical, legal, financial, or prophetic claims.
Do not use prosperity-gospel language.
Do not quote a Bible translation word-for-word unless it is confirmed public-domain.
Return valid JSON only, with title, message, scripture_reference, and topic.`;

  let content: DailyMotivationAiResponse | null = null;
  let source = "ai";
  try {
    content = validateMotivation(await callHuggingFaceJson(prompt));
  } catch (_) {
    content = null;
  }

  if (!content) {
    const dayIndex = Math.abs(
      publishDate.split("-").join("").split("").reduce((sum, digit) => sum + Number(digit), 0),
    ) % fallbackMotivations.length;
    content = fallbackMotivations[dayIndex];
    source = "fallback";
  }

  const { data: saved, error: saveError } = await client
    .from("daily_motivations")
    .upsert({
      id: existing.data?.id,
      publish_date: publishDate,
      title: content.title,
      message: content.message,
      scripture_reference: content.scripture_reference,
      topic: content.topic,
      source,
      status: "published",
      is_published: true,
      generated_at: new Date().toISOString(),
      published_at: new Date().toISOString(),
      failure_reason: source === "fallback" ? "AI response unavailable or failed validation." : null,
    }, { onConflict: "publish_date" })
    .select("*")
    .single();

  if (saveError || !saved) {
    return jsonResponse({ error: "Unable to save Daily Word." }, 500);
  }

  const title = "Grace Connect Daily Word";
  const body = shortPreview(String(saved.message), 120);
  const route = `/daily_word?id=${saved.id}`;

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
  const churches = new Set((churchRows ?? []).map((row) => String(row.placeId ?? "").trim()).filter(Boolean));
  let pushesSent = 0;
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
    if (result.sent) pushesSent++;
  }

  if (pushesSent > 0 || churches.size === 0) {
    await client
      .from("daily_motivations")
      .update({ notification_sent_at: new Date().toISOString() })
      .eq("id", saved.id);
  }

  return jsonResponse({
    ok: true,
    motivation_id: saved.id,
    publish_date: publishDate,
    source,
    church_topics_attempted: churches.size,
    push_topics_sent: pushesSent,
  });
});
