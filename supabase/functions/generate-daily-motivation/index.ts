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
  {
    title: "Courage For Today",
    message:
      "Move through today with courage rooted in God’s presence. You may not know every step ahead, but you can answer this moment with trust, humility, and obedience. Let faith steady your words and give your heart strength to keep going.",
    scripture_reference: "Joshua 1:9",
    topic: "courage",
  },
  {
    title: "Wisdom For Each Step",
    message:
      "Before the day becomes crowded, ask God for wisdom. He is able to guide your choices, soften your tone, and help you notice what matters most. A listening heart can walk with patience even when the path feels busy.",
    scripture_reference: "James 1:5",
    topic: "wisdom",
  },
  {
    title: "Renewed In The Lord",
    message:
      "When your strength feels small, remember that God is not weary. Bring Him your pressure, your questions, and your responsibilities. Let Him renew your spirit so you can serve with grace instead of moving only by exhaustion.",
    scripture_reference: "Isaiah 40:31",
    topic: "renewal",
  },
  {
    title: "Rooted And Steady",
    message:
      "Stay rooted in what is true today. The noise around you does not have to rule your spirit. Let Christ shape your attitude, your speech, and your decisions so your life carries the quiet strength of faith.",
    scripture_reference: "Colossians 2:6-7",
    topic: "steadfastness",
  },
  {
    title: "Mercy In Motion",
    message:
      "Look for one way to show mercy today. A patient answer, a helping hand, or a quiet prayer can reflect the heart of Christ. God can use ordinary kindness to remind someone that they are seen and loved.",
    scripture_reference: "Micah 6:8",
    topic: "mercy",
  },
  {
    title: "Peace That Guards",
    message:
      "Invite God into every concern before anxiety takes the lead. Prayer does not mean pretending everything is easy; it means placing the weight in faithful hands. Let His peace guard your heart as you walk through today.",
    scripture_reference: "Philippians 4:6-7",
    topic: "prayer",
  },
  {
    title: "Faith That Works",
    message:
      "Let your faith become visible through love today. Small acts of service matter when they are offered with a sincere heart. Ask God to make your belief active, compassionate, and useful to the people around you.",
    scripture_reference: "James 2:17",
    topic: "service",
  },
  {
    title: "Light For Your Path",
    message:
      "God’s Word can steady the next step even when the whole road is unclear. Take time to listen, reflect, and obey what He has already shown. A faithful step today can become light for tomorrow.",
    scripture_reference: "Psalm 119:105",
    topic: "guidance",
  },
  {
    title: "Love That Builds",
    message:
      "Choose words that build up today. Encouragement can carry more weight than you realize, especially when someone is tired or discouraged. Let love guide your conversations so your presence strengthens the people God places near you.",
    scripture_reference: "Ephesians 4:29",
    topic: "encouragement",
  },
  {
    title: "Hope Held Firm",
    message:
      "Hold tightly to hope today, not because circumstances are perfect, but because God is faithful. Let your confidence rest in His character. Keep doing good, keep praying, and keep trusting Him with what you cannot control.",
    scripture_reference: "Hebrews 10:23",
    topic: "hope",
  },
  {
    title: "Serve With Gladness",
    message:
      "Whatever responsibility is in front of you, offer it with a willing heart. Service done in love honors God and blesses people. Let gratitude shape your effort, and allow joy to rise even in simple tasks.",
    scripture_reference: "Psalm 100:2",
    topic: "service",
  },
  {
    title: "Grace For The Moment",
    message:
      "You do not need tomorrow’s strength before tomorrow arrives. Receive grace for this moment and answer it faithfully. God can meet you in ordinary places, giving patience for the next conversation and courage for the next step.",
    scripture_reference: "2 Corinthians 12:9",
    topic: "grace",
  },
];

function normalizeReference(reference: string): string {
  return reference.toLowerCase().replace(/\s+/g, " ").trim();
}

function validateMotivation(
  value: unknown,
  blockedReferences = new Set<string>(),
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
  if (!/^[1-3]?\s?[A-Za-z]+(?:\s[A-Za-z]+)*\s+\d{1,3}:\d{1,3}/.test(scripture)) {
    return null;
  }
  if (blockedReferences.has(normalizeReference(scripture))) return null;
  return { title, message, scripture_reference: scripture, topic };
}

function seedScore(seed: string): number {
  let hash = 2166136261;
  for (let index = 0; index < seed.length; index++) {
    hash ^= seed.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

async function recentScriptureReferences(
  client: ReturnType<typeof serviceClient>,
  publishDate: string,
): Promise<Set<string>> {
  try {
    const cutoff = new Date(`${publishDate}T00:00:00.000Z`);
    cutoff.setUTCDate(cutoff.getUTCDate() - 120);
    const { data } = await client
      .from("daily_motivations")
      .select("scripture_reference")
      .neq("publish_date", publishDate)
      .gte("publish_date", cutoff.toISOString().slice(0, 10))
      .eq("is_published", true)
      .order("publish_date", { ascending: false })
      .limit(120);
    return new Set(
      (data ?? [])
        .map((row) => normalizeReference(String(row.scripture_reference ?? "")))
        .filter(Boolean),
    );
  } catch (_) {
    return new Set();
  }
}

function selectFallbackMotivation(
  publishDate: string,
  blockedReferences: Set<string>,
): Required<DailyMotivationAiResponse> {
  const fresh = fallbackMotivations.filter(
    (item) => !blockedReferences.has(normalizeReference(item.scripture_reference)),
  );
  const pool = fresh.length > 0 ? fresh : fallbackMotivations;
  return [...pool].sort((left, right) =>
    seedScore(`${publishDate}:${left.scripture_reference}:${left.title}`) -
    seedScore(`${publishDate}:${right.scripture_reference}:${right.title}`)
  )[0];
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
  const blockedReferences = await recentScriptureReferences(client, publishDate);

  const existing = await client
    .from("daily_motivations")
    .select("*")
    .eq("publish_date", publishDate)
    .maybeSingle();

  const existingReference = normalizeReference(String(existing.data?.scripture_reference ?? ""));
  const existingRepeatsRecent = existingReference.length > 0 && blockedReferences.has(existingReference);
  if (existing.data?.is_published && existing.data?.notification_sent_at && !existingRepeatsRecent) {
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
Do not use any of these recently used scripture references: ${Array.from(blockedReferences).slice(0, 40).join(", ") || "none"}.
Do not invent Bible passages or claim God has personally promised a specific outcome to an individual.
Do not make medical, legal, financial, or prophetic claims.
Do not use prosperity-gospel language.
Do not quote a Bible translation word-for-word unless it is confirmed public-domain.
Return valid JSON only, with title, message, scripture_reference, and topic.`;

  let content: DailyMotivationAiResponse | null = null;
  let source = "ai";
  try {
    content = validateMotivation(await callHuggingFaceJson(prompt), blockedReferences);
  } catch (_) {
    content = null;
  }

  if (!content) {
    content = selectFallbackMotivation(publishDate, blockedReferences);
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
      failure_reason: source === "fallback"
        ? "AI response unavailable, repeated a recent scripture, or failed validation."
        : existingRepeatsRecent
          ? "Regenerated because the previous Daily Word repeated a recent scripture."
          : null,
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
