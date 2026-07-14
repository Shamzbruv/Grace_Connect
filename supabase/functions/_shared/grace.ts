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

export async function callHuggingFaceJson(prompt: string): Promise<unknown | null> {
  const hfToken = Deno.env.get("HF_TOKEN");
  if (!hfToken) throw new Error("AI configuration is incomplete.");

  const response = await fetch(
    "https://api-inference.huggingface.co/models/microsoft/Phi-3-mini-4k-instruct",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${hfToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        inputs: prompt,
        parameters: {
          max_new_tokens: 900,
          return_full_text: false,
          temperature: 0.7,
        },
      }),
    },
  );

  if (!response.ok) return null;
  const payload = await response.json();
  const text = Array.isArray(payload)
    ? String(payload[0]?.generated_text ?? "")
    : String(payload.generated_text ?? payload[0]?.generated_text ?? "");
  return safeJsonParse(text);
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
  },
): Promise<{ sent: boolean; reason?: string }> {
  const { data: outbox } = await client
    .from("system_notification_outbox")
    .insert({
      topic: params.topic,
      title: params.title,
      body: params.body,
      route: params.route,
      type: params.type,
      entity_table: params.entityTable,
      entity_id: params.entityId,
    })
    .select("id")
    .single();

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
    const serviceAccount = JSON.parse(serviceAccountJson);
    const projectId = String(serviceAccount.project_id ?? "");
    const token = await googleAccessToken(serviceAccount);
    const sound = notificationSoundProfile(params.type);
    const tag = notificationTag(params);
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            topic: params.topic,
            notification: {
              title: params.title,
              body: params.body,
            },
            data: {
              type: params.type,
              route: params.route,
              entity_table: params.entityTable ?? "",
              entity_id: params.entityId ?? "",
              notification_tag: tag,
            },
            android: {
              priority: "HIGH",
              notification: {
                channel_id: sound.channelId,
                sound: sound.sound.replace(".wav", ""),
                tag,
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: sound.sound,
                },
              },
            },
          },
        }),
      },
    );
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error("Push provider rejected the message.");
    if (outbox?.id) {
      await client
        .from("system_notification_outbox")
        .update({
          status: "sent",
          provider_message_id: String(body.name ?? ""),
          sent_at: new Date().toISOString(),
        })
        .eq("id", outbox.id);
    }
    return { sent: true };
  } catch (error) {
    if (outbox?.id) {
      await client
        .from("system_notification_outbox")
        .update({
          status: "failed",
          error_message: error instanceof Error ? error.message : "Push delivery failed.",
        })
        .eq("id", outbox.id);
    }
    return { sent: false, reason: "Push delivery failed." };
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
  let query = client.from("users").select("id, uid");
  if (params.churchId) query = query.eq("placeId", params.churchId);
  if (params.preferenceColumn) query = query.eq(params.preferenceColumn, true);
  const { data: users, error } = await query;
  if (error || !users) return 0;
  const rows = users
    .map((user) => String(user.id ?? user.uid ?? ""))
    .filter(Boolean)
    .map((userId) => ({
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
  const { error: insertError } = await client.from("notifications").insert(rows);
  return insertError ? 0 : rows.length;
}
