import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function handleOptions(request: Request): Response | null {
  return request.method === "OPTIONS" ? new Response("ok", { headers: corsHeaders }) : null;
}

export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Server configuration is incomplete.");
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function anonClient(accessToken?: string): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !key) throw new Error("Server configuration is incomplete.");
  return createClient(url, key, {
    global: accessToken
      ? { headers: { Authorization: `Bearer ${accessToken}` } }
      : undefined,
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function requireCronSecret(request: Request, secretName: string): Response | null {
  const expected = Deno.env.get(secretName);
  if (!expected) return jsonResponse({ error: "Server configuration is incomplete." }, 500);
  const received = request.headers.get("x-cron-secret") ?? "";
  if (received !== expected) return jsonResponse({ error: "Forbidden." }, 403);
  return null;
}

export function hasCronSecret(request: Request, secretName: string): boolean {
  const expected = Deno.env.get(secretName);
  const received = request.headers.get("x-cron-secret") ?? "";
  return Boolean(expected && received && received === expected);
}

export function accessTokenFromRequest(request: Request): string | null {
  const header = request.headers.get("Authorization") ?? "";
  return header.startsWith("Bearer ") ? header.slice("Bearer ".length) : null;
}

export async function authenticatedUser(request: Request): Promise<{ id: string; email?: string }> {
  const token = accessTokenFromRequest(request);
  if (!token) throw new Error("Not authenticated.");
  const { data, error } = await anonClient(token).auth.getUser(token);
  if (error || !data.user) throw new Error("Not authenticated.");
  return { id: data.user.id, email: data.user.email ?? undefined };
}

export async function userProfile(client: SupabaseClient, uid: string): Promise<Record<string, unknown>> {
  const { data, error } = await client
    .from("users")
    .select("*")
    .or(`uid.eq.${uid},id.eq.${uid}`)
    .maybeSingle();
  if (error || !data) throw new Error("Member profile was not found.");
  return data;
}

export function profileChurchId(profile: Record<string, unknown>): string {
  return String(profile.placeId ?? profile.churchId ?? "").trim();
}

export const GLOBAL_VISITOR_CHURCH_ID = "grace_connect_global";

export function profileQuizChurchId(profile: Record<string, unknown>): string {
  return profileChurchId(profile) || GLOBAL_VISITOR_CHURCH_ID;
}

export function profileQuizScope(profile: Record<string, unknown>): "church" | "global" {
  return profileChurchId(profile) ? "church" : "global";
}

export function profileDisplayName(profile: Record<string, unknown>): string {
  return String(profile.fullName ?? profile.displayName ?? "Member").trim();
}

export function jamaicaDateString(date = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Jamaica",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const value = (type: string) => parts.find((part) => part.type === type)?.value ?? "";
  return `${value("year")}-${value("month")}-${value("day")}`;
}

export function hasReachedJamaicaHour(hour: number, from = new Date()): boolean {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Jamaica",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(from);
  const value = (type: string) => Number(parts.find((part) => part.type === type)?.value ?? "0");
  const currentHour = value("hour");
  const currentMinute = value("minute");
  return currentHour > hour || (currentHour === hour && currentMinute >= 0);
}

export function nextJamaicaRefresh(hour: number, from = new Date()): Date {
  const today = jamaicaDateString(from);
  let refresh = new Date(`${today}T${String(hour + 5).padStart(2, "0")}:00:00.000Z`);
  if (from >= refresh) {
    const tomorrow = new Date(refresh);
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    refresh = tomorrow;
  }
  return refresh;
}

export function jamaicaMonthStart(date = new Date()): Date {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Jamaica",
    year: "numeric",
    month: "2-digit",
  }).formatToParts(date);
  const year = Number(parts.find((part) => part.type === "year")?.value ?? "1970");
  const month = Number(parts.find((part) => part.type === "month")?.value ?? "1");
  return new Date(Date.UTC(year, month - 1, 1, 5, 0, 0, 0));
}

export function jamaicaMonthDateKey(monthStart = jamaicaMonthStart()): string {
  const year = monthStart.getUTCFullYear();
  const month = String(monthStart.getUTCMonth() + 1).padStart(2, "0");
  return `${year}-${month}-01`;
}

export function jamaicaMonthRange(monthStart = jamaicaMonthStart()): { start: Date; end: Date } {
  const start = new Date(Date.UTC(
    monthStart.getUTCFullYear(),
    monthStart.getUTCMonth(),
    1,
    5,
    0,
    0,
    0,
  ));
  const end = new Date(Date.UTC(
    monthStart.getUTCFullYear(),
    monthStart.getUTCMonth() + 1,
    1,
    5,
    0,
    0,
    0,
  ));
  return { start, end };
}

export function previousJamaicaMonthStart(from = new Date()): Date {
  const current = jamaicaMonthStart(from);
  return new Date(Date.UTC(
    current.getUTCFullYear(),
    current.getUTCMonth() - 1,
    1,
    5,
    0,
    0,
    0,
  ));
}

export function parseJamaicaMonthKey(value?: string | null): Date {
  if (!value) return jamaicaMonthStart();
  const match = String(value).trim().match(/^(\d{4})-(\d{2})/);
  if (!match) return jamaicaMonthStart();
  return new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, 1, 5, 0, 0, 0));
}

export function jamaicaMonthLabel(monthStart: Date): string {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Jamaica",
    month: "long",
    year: "numeric",
  }).format(monthStart);
}

export function wordCount(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length;
}

export function shortPreview(text: string, max = 120): string {
  const collapsed = text.replace(/\s+/g, " ").trim();
  return collapsed.length <= max ? collapsed : `${collapsed.slice(0, max - 1).trim()}…`;
}

export function safeJsonParse<T>(value: string): T | null {
  try {
    const first = value.indexOf("{");
    const last = value.lastIndexOf("}");
    const json = first >= 0 && last > first ? value.slice(first, last + 1) : value;
    return JSON.parse(json) as T;
  } catch (_) {
    return null;
  }
}

export async function callHuggingFaceJson(
  prompt: string,
  maxNewTokens = 900,
  timeoutMs = 45_000,
): Promise<unknown | null> {
  const hfToken = Deno.env.get("HF_TOKEN");
  if (!hfToken) throw new Error("AI configuration is incomplete.");

  // Hugging Face fully decommissioned the legacy
  // api-inference.huggingface.co serverless endpoint (it no longer even
  // resolves) in favor of this OpenAI-compatible router, which auto-selects
  // an available provider for the requested model.
  //
  // This call is bounded by an explicit timeout. Quiz generation can invoke
  // this multiple times in one run (a shared attempt plus targeted retries
  // per church); a single provider hang with no abort here previously
  // stalled the entire request indefinitely instead of failing a single
  // attempt and letting the existing retry logic move on.
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(
      "https://router.huggingface.co/v1/chat/completions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${hfToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "openai/gpt-oss-120b",
          messages: [{ role: "user", content: prompt }],
          max_tokens: Math.max(256, Math.min(maxNewTokens, 4000)),
          temperature: 0.7,
          // gpt-oss is a reasoning model: without forcing strict JSON output
          // it can wrap the answer in chain-of-thought prose, or spend part
          // of the token budget reasoning before writing the actual JSON,
          // which truncates long structured responses (like a 12-question
          // quiz) before they close their braces. This is the standard
          // OpenAI-compatible switch to stop that.
          response_format: { type: "json_object" },
        }),
        signal: controller.signal,
      },
    );

    if (!response.ok) {
      // A bare null return here previously made every AI failure
      // indistinguishable from a validation rejection. Logging the status
      // and body is the only way to tell a dead token/model apart from a
      // transient provider error in the Edge Function logs.
      const body = await response.text().catch(() => "");
      console.error(
        `Hugging Face router request failed: HTTP ${response.status} ${body}`,
      );
      return null;
    }
    const payload = await response.json();
    const text = String(payload?.choices?.[0]?.message?.content ?? "");
    const parsed = safeJsonParse(text);
    if (parsed === null) {
      // Same reasoning as above: silently returning null here made a
      // truncated/malformed response indistinguishable from every other
      // failure mode. Logging a snippet of what actually came back is what
      // would have shown this was a formatting problem, not a dead
      // integration, without needing to guess from production data.
      console.error(
        `Hugging Face router response was not parseable JSON (finish_reason=${
          String(payload?.choices?.[0]?.finish_reason ?? "?")
        }): ${text.slice(0, 500)}`,
      );
    }
    return parsed;
  } catch (error) {
    console.error(
      `Hugging Face router request threw: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function base64Url(input: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : input instanceof ArrayBuffer
      ? new Uint8Array(input)
      : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function googleAccessToken(serviceAccount: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64Url(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const signingInput = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${base64Url(signature)}`;
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!tokenResponse.ok) throw new Error("Unable to authorize push delivery.");
  const tokenPayload = await tokenResponse.json();
  return String(tokenPayload.access_token ?? "");
}

export function notificationSoundProfile(type: string): { channelId: string; sound: string } {
  const normalized = String(type || "general").toLowerCase().replace(/[^a-z0-9_]+/g, "_");
  const profiles: Record<string, { channelId: string; sound: string }> = {
    general: { channelId: "grace_default_channel_v1", sound: "grace_default.wav" },
    announcement: { channelId: "grace_default_channel_v1", sound: "grace_default.wav" },
    daily_motivation: { channelId: "grace_daily_word_channel_v1", sound: "grace_daily.wav" },
    daily_devotional: { channelId: "grace_daily_word_channel_v1", sound: "grace_daily.wav" },
    daily_bible_quiz: { channelId: "grace_daily_quiz_channel_v1", sound: "grace_quiz.wav" },
    quiz: { channelId: "grace_daily_quiz_channel_v1", sound: "grace_quiz.wav" },
    monthly_quiz_winners: { channelId: "grace_daily_quiz_channel_v1", sound: "grace_quiz.wav" },
    prayer: { channelId: "grace_prayer_channel_v1", sound: "grace_prayer.wav" },
    prayer_request: { channelId: "grace_prayer_channel_v1", sound: "grace_prayer.wav" },
    message: { channelId: "grace_messages_channel_v1", sound: "grace_message.wav" },
    direct_message: { channelId: "grace_messages_channel_v1", sound: "grace_message.wav" },
    live_stream: { channelId: "grace_live_channel_v1", sound: "grace_live.wav" },
    bible_streak_reminder: { channelId: "grace_daily_word_channel_v1", sound: "grace_daily.wav" },
    grace_room_invitation: { channelId: "grace_default_channel_v1", sound: "grace_default.wav" },
    event_rsvp_reminder: { channelId: "grace_default_channel_v1", sound: "grace_default.wav" },
  };
  return profiles[normalized] ?? profiles.general;
}

function notificationTag(params: {
  type: string;
  route: string;
  entityTable?: string;
  entityId?: string;
}): string {
  if (params.entityTable && params.entityId) {
    return `entity:${params.entityTable}:${params.entityId}`;
  }
  if (params.route) return `route:${params.route}`;
  return `type:${params.type || "general"}`;
}

const REGISTERED_DELIVERY_TOPIC = "graceconnect_registered_delivery_v1";

type FcmTarget =
  | { token: string }
  | { topic: string }
  | { condition: string };

type FcmSendResult = {
  sent: boolean;
  providerMessageId?: string;
  invalidToken?: boolean;
  providerCode?: string;
};

function fcmMessage(
  target: FcmTarget,
  params: {
    title: string;
    body: string;
    route: string;
    type: string;
    entityTable?: string;
    entityId?: string;
  },
): Record<string, unknown> {
  const sound = notificationSoundProfile(params.type);
  const tag = notificationTag(params);
  const collapseKey = `grace_${params.type}`.slice(0, 64);
  return {
    ...target,
    notification: {
      title: params.title.slice(0, 120),
      body: params.body.slice(0, 220),
    },
    data: {
      type: params.type,
      route: params.route,
      entity_table: params.entityTable ?? "",
      entity_id: params.entityId ?? "",
      notification_tag: tag,
      title: params.title.slice(0, 120),
      body: params.body.slice(0, 220),
      click_action: "FLUTTER_NOTIFICATION_CLICK",
    },
    android: {
      priority: "HIGH",
      ttl: "86400s",
      collapse_key: collapseKey,
      notification: {
        channel_id: sound.channelId,
        sound: sound.sound.replace(".wav", ""),
        tag,
        color: "#0B5C7D",
        icon: "ic_stat_grace_connect",
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-collapse-id": collapseKey,
      },
      payload: {
        aps: {
          sound: sound.sound,
        },
      },
    },
  };
}

async function sendFcmMessage(
  projectId: string,
  accessToken: string,
  message: Record<string, unknown>,
): Promise<FcmSendResult> {
  try {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ message }),
      },
    );
    const body = await response.json().catch(() => ({})) as Record<string, unknown>;
    if (response.ok) {
      return {
        sent: true,
        providerMessageId: String(body.name ?? ""),
      };
    }

    const providerError = (body.error ?? {}) as Record<string, unknown>;
    const providerCode = String(providerError.status ?? response.status);
    const details = Array.isArray(providerError.details)
      ? providerError.details as Array<Record<string, unknown>>
      : [];
    const invalidToken = response.status === 404 || details.some((detail) =>
      String(detail.errorCode ?? "") === "UNREGISTERED"
    );
    return { sent: false, invalidToken, providerCode };
  } catch (_error) {
    return { sent: false, invalidToken: false, providerCode: "NETWORK_ERROR" };
  }
}

async function sendFcmMessageWithRetry(
  projectId: string,
  accessToken: string,
  message: Record<string, unknown>,
): Promise<FcmSendResult> {
  const first = await sendFcmMessage(projectId, accessToken, message);
  if (first.sent || first.invalidToken) return first;
  return await sendFcmMessage(projectId, accessToken, message);
}

export async function sendTopicPush(
  client: SupabaseClient,
  params: {
    topic: string;
    title: string;
    body: string;
    route: string;
    type: string;
    entityTable?: string;
    entityId?: string;
    idempotencyKey?: string;
  },
): Promise<{ sent: boolean; reason?: string }> {
  // A reclaimed delivery lease must not send a topic again after the provider
  // already accepted it. Failed/skipped rows remain retryable.
  const outboxEntityId = params.idempotencyKey ?? params.entityId;
  if (params.entityTable && outboxEntityId) {
    const { data: priorSent } = await client
      .from("system_notification_outbox")
      .select("id")
      .eq("topic", params.topic)
      .eq("type", params.type)
      .eq("entity_table", params.entityTable)
      .eq("entity_id", outboxEntityId)
      .eq("status", "sent")
      .limit(1);
    if ((priorSent ?? []).length > 0) {
      return { sent: true, reason: "Push was already delivered." };
    }
  }

  const { data: outbox, error: outboxError } = await client
    .from("system_notification_outbox")
    .insert({
      topic: params.topic,
      title: params.title,
      body: params.body,
      route: params.route,
      type: params.type,
      entity_table: params.entityTable,
      entity_id: outboxEntityId,
    })
    .select("id")
    .single();
  if (outboxError || !outbox?.id) {
    return {
      sent: false,
      reason: `Unable to reserve push delivery: ${outboxError?.message ?? "outbox unavailable"}`,
    };
  }

  const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!serviceAccountJson) {
    if (outbox?.id) {
      await client
        .from("system_notification_outbox")
        .update({ status: "skipped", error_message: "Firebase service account secret missing." })
        .eq("id", outbox.id);
    }
    return { sent: false, reason: "Firebase service account secret missing." };
  }

  try {
    const cleanTopic = params.topic.trim();
    if (!/^[A-Za-z0-9_~%.-]{1,900}$/.test(cleanTopic)) {
      throw new Error("Push topic is invalid.");
    }

    const serviceAccount = JSON.parse(serviceAccountJson);
    const projectId = String(serviceAccount.project_id ?? "");
    if (!projectId) throw new Error("Firebase project configuration is incomplete.");
    const accessToken = await googleAccessToken(serviceAccount);

    // Registered installations receive a token-addressed message. App builds
    // that predate the registry continue receiving the legacy topic message.
    // The marker topic excludes registered builds from that fallback and
    // prevents duplicate notifications.
    const registrationPageSize = 500;
    const registrations: Array<{ id: string; token: string }> = [];
    let registryAvailable = true;
    for (let from = 0; ; from += registrationPageSize) {
      const registrationsResult = await client
        .from("push_device_registrations")
        .select("id,token")
        .eq("enabled", true)
        .contains("topics", [cleanTopic])
        .order("id", { ascending: true })
        .range(from, from + registrationPageSize - 1);
      if (registrationsResult.error) {
        registryAvailable = false;
        registrations.length = 0;
        break;
      }
      const page = (registrationsResult.data ?? []) as Array<{ id: string; token: string }>;
      registrations.push(...page);
      if (page.length < registrationPageSize) break;
    }

    let directSent = 0;
    let directFailed = 0;
    const providerIds: string[] = [];
    const invalidRegistrationIds: string[] = [];
    for (let offset = 0; offset < registrations.length; offset += 100) {
      const batch = registrations.slice(offset, offset + 100);
      const results = await Promise.allSettled(batch.map(async (registration) => ({
        registration,
        result: await sendFcmMessageWithRetry(
          projectId,
          accessToken,
          fcmMessage({ token: registration.token }, params),
        ),
      })));
      for (const settled of results) {
        if (settled.status === "rejected") {
          directFailed += 1;
          continue;
        }
        const { registration, result } = settled.value;
        if (result.sent) {
          directSent += 1;
          if (result.providerMessageId && providerIds.length < 2) {
            providerIds.push(result.providerMessageId);
          }
        } else {
          directFailed += 1;
          if (result.invalidToken) invalidRegistrationIds.push(registration.id);
        }
      }
    }

    if (invalidRegistrationIds.length > 0) {
      for (let offset = 0; offset < invalidRegistrationIds.length; offset += 200) {
        await client
          .from("push_device_registrations")
          .update({ enabled: false, updated_at: new Date().toISOString() })
          .in("id", invalidRegistrationIds.slice(offset, offset + 200));
      }
    }

    // User-addressed and leader-only messages must never rely on client-managed
    // Firebase topic membership as an authorization boundary. Those events are
    // delivered only to server-derived registry rows. Public/broadcast topics
    // retain the legacy fallback for older app versions.
    const registryOnlyTopic = cleanTopic.startsWith("user_") ||
      cleanTopic.endsWith("_leaders");
    const fallbackTarget: FcmTarget = registryAvailable
      ? {
        condition:
          `'${cleanTopic}' in topics && !('${REGISTERED_DELIVERY_TOPIC}' in topics)`,
      }
      : { topic: cleanTopic };
    const fallback = registryOnlyTopic
      ? { sent: false, providerCode: "REGISTRY_ONLY" } as FcmSendResult
      : await sendFcmMessageWithRetry(
        projectId,
        accessToken,
        fcmMessage(fallbackTarget, params),
      );
    if (fallback.providerMessageId) providerIds.push(fallback.providerMessageId);

    if (!fallback.sent && directSent === 0) {
      throw new Error(
        `Push provider rejected all delivery paths (${fallback.providerCode ?? "unknown"}).`,
      );
    }

    if (outbox?.id) {
      await client
        .from("system_notification_outbox")
        .update({
          status: "sent",
          provider_message_id: [
            ...providerIds.slice(0, 2),
            `direct:${directSent}`,
          ].filter(Boolean).join(" | ").slice(0, 500),
          error_message: directFailed > 0
            ? `${directFailed} registered device delivery attempt(s) failed.`
            : null,
          sent_at: new Date().toISOString(),
        })
        .eq("id", outbox.id);
    }
    return {
      sent: true,
      reason: directFailed > 0
        ? `${directFailed} registered device delivery attempt(s) failed.`
        : undefined,
    };
  } catch (error) {
    const reason = error instanceof Error ? error.message : "Push delivery failed.";
    if (outbox?.id) {
      await client
        .from("system_notification_outbox")
        .update({
          status: "failed",
          error_message: reason.slice(0, 500),
        })
        .eq("id", outbox.id);
    }
    return { sent: false, reason };
  }
}

export async function createInAppNotifications(
  client: SupabaseClient,
  params: {
    churchId?: string;
    title: string;
    body: string;
    type: string;
    route: string;
    entityTable?: string;
    entityId?: string;
    preferenceColumn?: string;
  },
): Promise<number> {
  const pageSize = 500;
  const userIds = new Set<string>();
  for (let from = 0; ; from += pageSize) {
    let query = client
      .from("users")
      .select("id, uid")
      .order("id", { ascending: true })
      .range(from, from + pageSize - 1);
    if (params.churchId) query = query.eq("placeId", params.churchId);
    if (params.preferenceColumn) query = query.eq(params.preferenceColumn, true);
    const { data: users, error } = await query;
    if (error || !users) return 0;
    for (const user of users) {
      const userId = String(user.id ?? "").trim() ||
        String(user.uid ?? "").trim();
      if (userId) userIds.add(userId);
    }
    if (users.length < pageSize) break;
  }

  let rows = [...userIds].map((userId) => ({
    user_id: userId,
    actor_id: null,
    actor_name: "Grace Connect",
    type: params.type,
    title: params.title,
    body: params.body,
    place_id: params.churchId ?? null,
    entity_table: params.entityTable ?? null,
    entity_id: params.entityId ?? null,
    route: params.route,
  }));
  if (rows.length === 0) return 0;

  // Release retries can revisit this helper after an invocation crash or a
  // provider outage. Reuse the existing in-app cards for that entity instead
  // of showing members duplicates.
  if (params.entityTable && params.entityId) {
    const existingUserIds = new Set<string>();
    for (let from = 0; ; from += pageSize) {
      const { data: existingRows, error: existingError } = await client
        .from("notifications")
        .select("user_id")
        .eq("type", params.type)
        .eq("entity_table", params.entityTable)
        .eq("entity_id", params.entityId)
        .order("user_id", { ascending: true })
        .range(from, from + pageSize - 1);
      if (existingError || !existingRows) break;
      for (const existing of existingRows) {
        const userId = String(existing.user_id ?? "").trim();
        if (userId) existingUserIds.add(userId);
      }
      if (existingRows.length < pageSize) break;
    }
    rows = rows.filter((row) => !existingUserIds.has(row.user_id));
    if (rows.length === 0) return 0;
  }

  let inserted = 0;
  for (let offset = 0; offset < rows.length; offset += pageSize) {
    const chunk = rows.slice(offset, offset + pageSize);
    const { error: insertError } = await client.from("notifications").insert(chunk);
    if (insertError) continue;
    inserted += chunk.length;
  }
  return inserted;
}
