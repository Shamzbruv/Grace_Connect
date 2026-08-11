import {
  accessTokenFromRequest,
  anonClient,
  corsHeaders,
  handleOptions,
  jsonResponse,
  serviceClient,
} from "../_shared/grace.ts";

type SignupMailRequest = {
  action: "auth-signup";
  email?: string;
  password?: string;
  redirectTo?: string;
  flowType?: string;
  userData?: Record<string, unknown>;
  captchaToken?: string;
};

type PasswordResetMailRequest = {
  action: "password-reset";
  email?: string;
  redirectTo?: string;
  captchaToken?: string;
};

type FlushQueueMailRequest = {
  action: "flush-queue";
  limit?: number;
};

type FlushSupportTicketMailRequest = {
  action: "flush-support-ticket";
  ticketId?: string;
};

type ManagedAppMailRequest = {
  action: "send-app-email";
  to?: string[];
  subject?: string;
  htmlBody?: string;
};

type UnknownMailRequest = {
  action?: unknown;
  [key: string]: unknown;
};

type EmailRow = {
  id: string;
  to_email: string;
  subject: string;
  html_body: string;
  text_body?: string | null;
  metadata?: Record<string, unknown> | null;
};

const defaultSiteUrl = "https://www.graceconnect.love";

type PublicMailAction = "auth-signup" | "password-reset";

class MailHttpError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly retryAfterSeconds?: number,
  ) {
    super(message);
    this.name = "MailHttpError";
  }
}

function requireResendKey(): string {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) {
    throw new Error(
      "RESEND_API_KEY is not configured in Supabase Edge Function secrets.",
    );
  }
  return key;
}

function mailFrom(): string {
  const name = Deno.env.get("RESEND_FROM_NAME") ?? "Grace Connect";
  const email = Deno.env.get("RESEND_FROM_EMAIL") ?? "onboarding@resend.dev";
  return `${name} <${email}>`;
}

function replyTo(): string | undefined {
  return Deno.env.get("RESEND_REPLY_TO") ?? Deno.env.get("RESEND_FROM_EMAIL") ??
    undefined;
}

function plainText(html: string): string {
  return String(html)
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function allowedRedirect(
  rawRedirect?: string,
  options: { allowNativeApp?: boolean } = {},
): string {
  const fallback = `${Deno.env.get("PUBLIC_SITE_URL") ?? defaultSiteUrl}/`;
  const url = new URL(rawRedirect || fallback, fallback);
  if (options.allowNativeApp && url.protocol === "app.graceconnect.church:") {
    return url.href;
  }
  const allowed = (Deno.env.get("MAIL_ALLOWED_REDIRECT_ORIGINS") ??
    [
      "https://www.graceconnect.love",
      "https://graceconnect.love",
      "http://localhost:3000",
      "http://localhost:5173",
      "http://127.0.0.1:5500",
    ].join(","))
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
  if (!allowed.includes(url.origin)) {
    throw new Error("This verification redirect is not allowed.");
  }
  return url.href;
}

function publicAuthCallbackUrl(params: {
  nextUrl: string;
  flowType: string;
  tokenHash?: string | null;
  token?: string | null;
  email?: string | null;
  type?: string | null;
}): string {
  const siteUrl = Deno.env.get("PUBLIC_SITE_URL") ?? defaultSiteUrl;
  const callback = new URL("/auth-callback.html", siteUrl);
  const next = new URL(params.nextUrl, siteUrl);
  callback.searchParams.set("flow", params.flowType);
  callback.searchParams.set(
    "next",
    `${next.pathname}${next.search}${next.hash}`,
  );
  if (params.tokenHash) {
    callback.searchParams.set("token_hash", params.tokenHash);
  }
  if (params.token) callback.searchParams.set("token", params.token);
  if (params.email) callback.searchParams.set("email", params.email);
  callback.searchParams.set("type", params.type || "signup");
  return callback.href;
}

function normalizeEmail(email?: string): string {
  const value = String(email ?? "").trim().toLowerCase();
  if (value.length > 320 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
    throw new Error("A valid email address is required.");
  }
  return value;
}

function configuredFlag(name: string): boolean {
  const rawValue = Deno.env.get(name);
  if (rawValue == null || rawValue.trim() === "") return false;

  const value = rawValue.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(value)) return true;
  if (["0", "false", "no", "off"].includes(value)) return false;
  throw new MailHttpError("Email protection is temporarily unavailable.", 503);
}

function requestClientIp(request: Request): string | null {
  const rawValue = request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-forwarded-for")?.split(",")[0] ??
    request.headers.get("x-real-ip") ??
    "";
  const value = rawValue.trim();
  return value ? value.slice(0, 128) : null;
}

async function privacyRateKey(
  kind: "email" | "ip",
  value: string,
): Promise<string> {
  const configuredPepper = Deno.env.get("MAIL_RATE_LIMIT_PEPPER")?.trim();
  const pepper = configuredPepper || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!pepper || pepper.length < 32) {
    throw new MailHttpError(
      "Email protection is temporarily unavailable.",
      503,
    );
  }

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(pepper),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`grace-mail:${kind}:v1:${value}`),
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function verifyPublicMailCaptcha(
  request: Request,
  action: PublicMailAction,
  rawToken?: string,
): Promise<void> {
  const actionRequiredEnvironmentName = action === "auth-signup"
    ? "MAIL_CAPTCHA_SIGNUP_REQUIRED"
    : "MAIL_CAPTCHA_RESET_REQUIRED";
  const hasActionOverride = Boolean(
    Deno.env.get(actionRequiredEnvironmentName)?.trim(),
  );
  const captchaRequired = hasActionOverride
    ? configuredFlag(actionRequiredEnvironmentName)
    : configuredFlag("MAIL_CAPTCHA_REQUIRED");
  if (!captchaRequired) return;

  const token = String(rawToken ?? "").trim();
  if (!token || token.length > 4096) {
    throw new MailHttpError("Complete the security check and try again.", 403);
  }

  const secret = Deno.env.get("MAIL_CAPTCHA_SECRET")?.trim();
  if (!secret) {
    throw new MailHttpError(
      "Email protection is temporarily unavailable.",
      503,
    );
  }

  const rawEndpoint = Deno.env.get("MAIL_CAPTCHA_VERIFY_URL")?.trim() ||
    "https://challenges.cloudflare.com/turnstile/v0/siteverify";
  let endpoint: URL;
  try {
    endpoint = new URL(rawEndpoint);
    if (endpoint.protocol !== "https:") throw new Error("HTTPS is required.");
  } catch (_) {
    throw new MailHttpError(
      "Email protection is temporarily unavailable.",
      503,
    );
  }

  const form = new URLSearchParams({ secret, response: token });
  const clientIp = requestClientIp(request);
  if (clientIp) form.set("remoteip", clientIp);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  let response: Response;
  try {
    response = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
      signal: controller.signal,
    });
  } catch (_) {
    throw new MailHttpError(
      "Security verification is temporarily unavailable.",
      503,
    );
  } finally {
    clearTimeout(timeout);
  }

  if (!response.ok) {
    throw new MailHttpError(
      "Security verification is temporarily unavailable.",
      503,
    );
  }

  const result = await response.json().catch(() => null) as {
    success?: boolean;
    hostname?: string;
    action?: string;
  } | null;
  if (result?.success !== true) {
    throw new MailHttpError("Complete the security check and try again.", 403);
  }

  const allowedHostnames =
    (Deno.env.get("MAIL_CAPTCHA_ALLOWED_HOSTNAMES") ?? "")
      .split(",")
      .map((hostname) => hostname.trim().toLowerCase())
      .filter(Boolean);
  if (
    allowedHostnames.length > 0 &&
    !allowedHostnames.includes(
      String(result.hostname ?? "").trim().toLowerCase(),
    )
  ) {
    throw new MailHttpError("Complete the security check and try again.", 403);
  }

  const actionEnvironmentName = action === "auth-signup"
    ? "MAIL_CAPTCHA_SIGNUP_ACTION"
    : "MAIL_CAPTCHA_RESET_ACTION";
  const expectedAction = Deno.env.get(actionEnvironmentName)?.trim();
  if (expectedAction && result.action !== expectedAction) {
    throw new MailHttpError("Complete the security check and try again.", 403);
  }
}

async function consumePublicMailRateLimit(
  request: Request,
  action: PublicMailAction,
  email: string,
): Promise<void> {
  const clientIp = requestClientIp(request);
  const emailKey = await privacyRateKey("email", email);
  const ipKey = clientIp ? await privacyRateKey("ip", clientIp) : null;
  const { data, error } = await serviceClient().rpc(
    "consume_grace_mail_public_rate_limit",
    {
      target_action: action,
      target_email_key: emailKey,
      target_ip_key: ipKey,
    },
  );
  if (error) {
    throw new MailHttpError(
      "Email protection is temporarily unavailable.",
      503,
    );
  }

  const result = (Array.isArray(data) ? data[0] : data) as {
    allowed?: boolean;
    retry_after_seconds?: number;
  } | null;
  if (result?.allowed === true) return;
  if (result?.allowed !== false) {
    throw new MailHttpError(
      "Email protection is temporarily unavailable.",
      503,
    );
  }

  const rawRetryAfter = Number(result.retry_after_seconds ?? 60);
  const retryAfter = Number.isFinite(rawRetryAfter)
    ? Math.max(1, Math.min(Math.ceil(rawRetryAfter), 86400))
    : 60;
  throw new MailHttpError(
    "Too many email requests. Please wait before trying again.",
    429,
    retryAfter,
  );
}

function normalizeSignupData(
  data: Record<string, unknown> | undefined,
  flowType: string,
): Record<string, unknown> {
  const source = data ?? {};
  return {
    full_name: String(source.full_name ?? source.fullName ?? "").trim(),
    phone: String(source.phone ?? "").trim(),
    signupSource: flowType,
  };
}

function brandedEmail(params: {
  title: string;
  preview: string;
  body: string;
  ctaLabel?: string;
  ctaUrl?: string;
}): { html: string; text: string } {
  const safeTitle = escapeHtml(params.title);
  const safePreview = escapeHtml(params.preview);
  const cta = params.ctaUrl
    ? `<p style="margin:32px 0 8px;"><a href="${params.ctaUrl}" style="display:inline-block;background:#102655;color:#ffffff;text-decoration:none;font-weight:700;padding:14px 22px;border-radius:8px;">${
      params.ctaLabel ?? "Open Grace Connect"
    }</a></p>`
    : "";
  const html = `
    <div data-grace-email="true" style="display:none;max-height:0;overflow:hidden;opacity:0;">${safePreview}</div>
    <div style="font-family:Arial,Helvetica,sans-serif;background:#f7f3ea;padding:32px 16px;color:#12213d;">
      <div style="max-width:620px;margin:0 auto;background:#ffffff;border-radius:16px;padding:34px;border:1px solid #eadcb6;">
        <p style="margin:0 0 18px;color:#c39213;font-size:13px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;">Grace Connect</p>
        <h1 style="margin:0 0 18px;font-family:Georgia,serif;font-size:30px;line-height:1.15;color:#0d1f4c;">${safeTitle}</h1>
        <div style="font-size:16px;line-height:1.65;color:#263852;">${params.body}</div>
        ${cta}
        <p style="margin:28px 0 0;font-size:13px;line-height:1.5;color:#69768b;">If you did not request this email, you can ignore it.</p>
      </div>
    </div>
  `;
  return {
    html,
    text: `${params.title}\n\n${plainText(params.body)}${
      params.ctaUrl
        ? `\n\n${params.ctaLabel ?? "Open Grace Connect"}: ${params.ctaUrl}`
        : ""
    }`,
  };
}

function queuedEmailBody(row: EmailRow): { html: string; text: string } {
  const existingHtml = String(row.html_body ?? "");
  if (existingHtml.includes('data-grace-email="true"')) {
    return {
      html: existingHtml,
      text: row.text_body ?? plainText(existingHtml),
    };
  }

  const body = existingHtml.trim().startsWith("<")
    ? existingHtml
    : `<p>${existingHtml.replace(/\n/g, "<br>")}</p>`;
  return brandedEmail({
    title: row.subject || "Grace Connect Update",
    preview: plainText(body).slice(0, 140) ||
      "Grace Connect has an update for you.",
    body,
  });
}

async function sendResendEmail(params: {
  to: string;
  subject: string;
  html: string;
  text?: string | null;
}): Promise<string> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${requireResendKey()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: mailFrom(),
      to: [params.to],
      subject: params.subject,
      html: params.html,
      text: params.text ?? plainText(params.html),
      reply_to: replyTo(),
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = String(
      payload?.message ?? payload?.error ?? "Resend rejected the message.",
    );
    throw new Error(message);
  }
  return String(payload?.id ?? "");
}

function actionLinkFromGenerateLink(
  data: Record<string, unknown> | null,
): string {
  const properties = data?.properties as Record<string, unknown> | undefined;
  const actionLink = String(
    properties?.action_link ?? properties?.actionLink ?? "",
  );
  if (!actionLink) {
    throw new Error("Supabase did not return a verification link.");
  }
  return actionLink;
}

function verificationUrlFromGenerateLink(
  data: Record<string, unknown> | null,
  nextUrl: string,
  flowType: string,
  email: string,
): string {
  const properties = data?.properties as Record<string, unknown> | undefined;
  const actionLink = actionLinkFromGenerateLink(data);
  let tokenHash = String(
    properties?.token_hash ??
      properties?.hashed_token ??
      properties?.hashedToken ??
      "",
  );
  let token = String(properties?.email_otp ?? properties?.token ?? "");
  let type = String(properties?.type ?? "signup");

  try {
    const parsed = new URL(actionLink);
    tokenHash = tokenHash || parsed.searchParams.get("token_hash") || "";
    token = token || parsed.searchParams.get("token") || "";
    type = parsed.searchParams.get("type") || type;
  } catch (_) {
    // If Supabase changes the shape, the fallback below still sends the raw link.
  }

  if (tokenHash || token) {
    return publicAuthCallbackUrl({
      nextUrl,
      flowType,
      tokenHash,
      token,
      email,
      type,
    });
  }

  return actionLink;
}

async function sendSignupVerification(
  request: Request,
  body: SignupMailRequest,
): Promise<Response> {
  requireResendKey();
  const email = normalizeEmail(body.email);
  const password = String(body.password ?? "");
  if (password.length < 8) {
    throw new Error("Password must be at least 8 characters.");
  }
  const flowType = String(body.flowType ?? "web_signup").trim();
  if (!["web_church_registration", "web_member_signup"].includes(flowType)) {
    throw new Error("Unsupported signup flow.");
  }
  const redirectTo = allowedRedirect(body.redirectTo);
  await verifyPublicMailCaptcha(request, "auth-signup", body.captchaToken);
  await consumePublicMailRateLimit(request, "auth-signup", email);
  const authRedirectTo = publicAuthCallbackUrl({
    nextUrl: redirectTo,
    flowType,
  });
  const supabase = serviceClient();
  let verificationUrl = "";
  const userData = normalizeSignupData(body.userData, flowType);

  const signupResult = await supabase.auth.admin.generateLink({
    type: "signup",
    email,
    password,
    options: {
      data: userData,
      redirectTo: authRedirectTo,
    },
  });

  if (signupResult.error) {
    const message = signupResult.error.message.toLowerCase();
    if (
      !message.includes("already") && !message.includes("registered") &&
      !message.includes("exists")
    ) {
      throw signupResult.error;
    }
    const magicResult = await supabase.auth.admin.generateLink({
      type: "magiclink",
      email,
      options: { redirectTo: authRedirectTo },
    });
    if (magicResult.error) throw magicResult.error;
    verificationUrl = verificationUrlFromGenerateLink(
      magicResult.data as Record<string, unknown>,
      redirectTo,
      flowType,
      email,
    );
  } else {
    verificationUrl = verificationUrlFromGenerateLink(
      signupResult.data as Record<string, unknown>,
      redirectTo,
      flowType,
      email,
    );
  }

  const isChurch = flowType === "web_church_registration";
  const emailBody = brandedEmail({
    title: isChurch
      ? "Verify Your Church Registration Email"
      : "Verify Your Grace Connect Email",
    preview:
      "Use this secure link to verify your email and continue Grace Connect signup.",
    body: `<p>Hello${
      userData.full_name ? ` ${escapeHtml(userData.full_name)}` : ""
    },</p><p>Use the button below to verify your email address and continue your ${
      isChurch ? "church registration" : "membership request"
    }.</p><p>This link is time-sensitive and should only be used by you.</p>`,
    ctaLabel: "Verify Email",
    ctaUrl: verificationUrl,
  });

  const resendId = await sendResendEmail({
    to: email,
    subject: isChurch
      ? "Verify your Grace Connect church registration"
      : "Verify your Grace Connect email",
    html: emailBody.html,
    text: emailBody.text,
  });

  return jsonResponse({
    ok: true,
    provider: "resend",
    id: resendId,
  });
}

async function sendPasswordReset(
  request: Request,
  body: PasswordResetMailRequest,
): Promise<Response> {
  requireResendKey();
  const email = normalizeEmail(body.email);
  const redirectTo = allowedRedirect(body.redirectTo, { allowNativeApp: true });
  await verifyPublicMailCaptcha(request, "password-reset", body.captchaToken);
  await consumePublicMailRateLimit(request, "password-reset", email);
  const supabase = serviceClient();

  const recoveryResult = await supabase.auth.admin.generateLink({
    type: "recovery",
    email,
    options: { redirectTo },
  });
  if (recoveryResult.error) {
    const message = recoveryResult.error.message.toLowerCase();
    if (
      message.includes("not found") || message.includes("does not exist") ||
      message.includes("no user")
    ) {
      // Public recovery must not reveal whether an email is registered.
      return jsonResponse({ ok: true });
    }
    throw recoveryResult.error;
  }

  const resetUrl = actionLinkFromGenerateLink(
    recoveryResult.data as Record<string, unknown>,
  );

  const emailBody = brandedEmail({
    title: "Reset Your Grace Connect Password",
    preview: "Use this secure Grace Connect link to create a new password.",
    body:
      "<p>Hello,</p><p>We received a request to reset your Grace Connect password.</p><p>Tap the button below to create a new password in the app. This link is time-sensitive and should only be used by you.</p>",
    ctaLabel: "Reset Password",
    ctaUrl: resetUrl,
  });

  await sendResendEmail({
    to: email,
    subject: "Reset your Grace Connect password",
    html: emailBody.html,
    text: emailBody.text,
  });

  // Keep the public response indistinguishable from the unknown-user path.
  return jsonResponse({ ok: true });
}

async function requireDeveloper(request: Request): Promise<void> {
  const token = accessTokenFromRequest(request);
  if (!token) throw new Error("Developer sign-in is required.");
  const { error } = await anonClient(token).rpc("developer_get_session");
  if (error) throw new Error("Developer access is required.");
}

async function currentUser(
  request: Request,
): Promise<{ id: string; email: string }> {
  const token = accessTokenFromRequest(request);
  if (!token) throw new Error("Sign-in is required.");
  const { data, error } = await anonClient(token).auth.getUser(token);
  if (error || !data.user?.id) throw new Error("Sign-in is required.");
  return { id: data.user.id, email: data.user.email ?? "" };
}

async function requireManagedEmailSender(request: Request): Promise<void> {
  const token = accessTokenFromRequest(request);
  if (!token) throw new Error("Sign-in is required.");
  const client = anonClient(token);

  const developer = await client.rpc("developer_get_session");
  if (!developer.error) return;

  const membership = await client.rpc("get_current_membership_context");
  const context = membership.data as Record<string, unknown> | null;
  const churchId = String(context?.churchId ?? "").trim();
  if (membership.error || !churchId || context?.membershipStatus !== "active") {
    throw new Error("Church email permission is required.");
  }

  const permission = await client.rpc("can_manage_church_members", {
    target_church_id: churchId,
  });
  if (permission.error || permission.data !== true) {
    throw new Error("Church email permission is required.");
  }
}

async function sendManagedAppEmail(
  request: Request,
  body: ManagedAppMailRequest,
): Promise<Response> {
  await requireManagedEmailSender(request);
  requireResendKey();

  const rawRecipients = Array.isArray(body.to) ? body.to : [];
  const recipients = Array.from(
    new Set(rawRecipients.map((email) => normalizeEmail(String(email)))),
  );
  if (recipients.length < 1 || recipients.length > 200) {
    throw new Error("Between 1 and 200 recipients are required.");
  }

  const subject = String(body.subject ?? "").trim();
  if (!subject || subject.length > 160) {
    throw new Error("Email subject must be between 1 and 160 characters.");
  }
  const suppliedHtml = String(body.htmlBody ?? "").trim();
  if (!suppliedHtml || suppliedHtml.length > 100_000) {
    throw new Error("Email content is empty or too large.");
  }

  const emailBody = suppliedHtml.includes('data-grace-email="true"')
    ? { html: suppliedHtml, text: plainText(suppliedHtml) }
    : brandedEmail({
      title: subject,
      preview: plainText(suppliedHtml).slice(0, 140) || "Grace Connect update",
      body: suppliedHtml,
    });

  const providerIds: string[] = [];
  for (const recipient of recipients) {
    providerIds.push(
      await sendResendEmail({
        to: recipient,
        subject,
        html: emailBody.html,
        text: emailBody.text,
      }),
    );
  }

  return jsonResponse({
    ok: true,
    provider: "resend",
    sent: recipients.length,
    ids: providerIds,
  });
}

async function queuedRowsForSupportTicket(
  request: Request,
  ticketId?: string,
): Promise<EmailRow[]> {
  const identifier = String(ticketId ?? "").trim();
  if (!identifier) throw new Error("Ticket ID is required.");
  const user = await currentUser(request);
  const supabase = serviceClient();

  const { data: ticket, error } = await supabase
    .from("support_tickets")
    .select("id, ticketId, userId, uid, reporterEmail")
    .or(`id.eq.${identifier},ticketId.eq.${identifier}`)
    .maybeSingle();
  if (error || !ticket) throw new Error("Support ticket was not found.");

  const isReporter =
    [ticket.userId, ticket.uid].map((value) => String(value ?? "")).includes(
      user.id,
    ) ||
    String(ticket.reporterEmail ?? "").toLowerCase() ===
      user.email.toLowerCase();
  if (!isReporter) {
    await requireDeveloper(request);
  }

  const { data: rows, error: queueError } = await supabase
    .from("email_notification_queue")
    .select("*")
    .eq("status", "queued")
    .eq("related_type", "support_ticket")
    .eq("related_id", String(ticket.id))
    .order("created_at", { ascending: true })
    .limit(10);
  if (queueError) throw queueError;
  return (rows ?? []) as EmailRow[];
}

async function deliverRows(
  rows: EmailRow[],
): Promise<{ ok: boolean; total: number; sent: number; failed: number }> {
  requireResendKey();
  const supabase = serviceClient();
  let sent = 0;
  let failed = 0;

  for (const row of rows) {
    try {
      const emailBody = queuedEmailBody(row);
      const providerId = await sendResendEmail({
        to: row.to_email,
        subject: row.subject,
        html: emailBody.html,
        text: emailBody.text,
      });
      sent += 1;
      await supabase
        .from("email_notification_queue")
        .update({
          status: "sent",
          sent_at: new Date().toISOString(),
          error_message: null,
          metadata: {
            ...(row.metadata ?? {}),
            provider: "resend",
            provider_message_id: providerId,
          },
        })
        .eq("id", row.id);
    } catch (error) {
      failed += 1;
      await supabase
        .from("email_notification_queue")
        .update({
          status: "failed",
          error_message: error instanceof Error
            ? error.message
            : "Email delivery failed.",
        })
        .eq("id", row.id);
    }
  }

  return { ok: failed === 0, total: rows.length, sent, failed };
}

async function flushDeveloperQueue(
  request: Request,
  limit?: number,
): Promise<Response> {
  await requireDeveloper(request);
  requireResendKey();
  const safeLimit = Math.max(1, Math.min(Number(limit ?? 25), 50));
  const { data, error } = await serviceClient()
    .from("email_notification_queue")
    .select("*")
    .eq("status", "queued")
    .order("created_at", { ascending: true })
    .limit(safeLimit);
  if (error) throw error;
  return jsonResponse(await deliverRows((data ?? []) as EmailRow[]));
}

Deno.serve(async (request) => {
  const optionsResponse = handleOptions(request);
  if (optionsResponse) return optionsResponse;

  try {
    if (request.method !== "POST") {
      return jsonResponse({ error: "Method not allowed." }, 405);
    }
    const body = (await request.json().catch(() => ({}))) as UnknownMailRequest;

    if (body.action === "auth-signup") {
      return await sendSignupVerification(request, body as SignupMailRequest);
    }
    if (body.action === "password-reset") {
      return await sendPasswordReset(request, body as PasswordResetMailRequest);
    }
    if (body.action === "send-app-email") {
      return await sendManagedAppEmail(request, body as ManagedAppMailRequest);
    }
    if (body.action === "flush-queue") {
      const flushRequest = body as FlushQueueMailRequest;
      return await flushDeveloperQueue(request, flushRequest.limit);
    }
    if (body.action === "flush-support-ticket") {
      const flushRequest = body as FlushSupportTicketMailRequest;
      const rows = await queuedRowsForSupportTicket(
        request,
        flushRequest.ticketId,
      );
      return jsonResponse(await deliverRows(rows));
    }

    return jsonResponse({ error: "Unsupported mail action." }, 400);
  } catch (error) {
    const status = error instanceof MailHttpError ? error.status : 400;
    const retryAfter = error instanceof MailHttpError
      ? error.retryAfterSeconds
      : undefined;
    return new Response(
      JSON.stringify({
        ok: false,
        error: error instanceof Error
          ? error.message
          : "Email delivery failed.",
      }),
      {
        status,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
          ...(retryAfter ? { "Retry-After": String(retryAfter) } : {}),
        },
      },
    );
  }
});
