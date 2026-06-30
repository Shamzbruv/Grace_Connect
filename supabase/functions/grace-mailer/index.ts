import {
  accessTokenFromRequest,
  anonClient,
  corsHeaders,
  handleOptions,
  jsonResponse,
  serviceClient,
} from "../_shared/grace.ts";

type MailRequest =
  | {
      action: "auth-signup";
      email?: string;
      password?: string;
      redirectTo?: string;
      flowType?: string;
      userData?: Record<string, unknown>;
    }
  | {
      action: "flush-queue";
      limit?: number;
    }
  | {
      action: "flush-support-ticket";
      ticketId?: string;
    }
  | {
      action?: string;
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

function requireResendKey(): string {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) {
    throw new Error("RESEND_API_KEY is not configured in Supabase Edge Function secrets.");
  }
  return key;
}

function mailFrom(): string {
  const name = Deno.env.get("RESEND_FROM_NAME") ?? "Grace Connect";
  const email = Deno.env.get("RESEND_FROM_EMAIL") ?? "onboarding@resend.dev";
  return `${name} <${email}>`;
}

function replyTo(): string | undefined {
  return Deno.env.get("RESEND_REPLY_TO") ?? Deno.env.get("RESEND_FROM_EMAIL") ?? undefined;
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

function allowedRedirect(rawRedirect?: string): string {
  const fallback = `${Deno.env.get("PUBLIC_SITE_URL") ?? defaultSiteUrl}/`;
  const url = new URL(rawRedirect || fallback, fallback);
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

function normalizeEmail(email?: string): string {
  const value = String(email ?? "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
    throw new Error("A valid email address is required.");
  }
  return value;
}

function normalizeSignupData(data: Record<string, unknown> | undefined, flowType: string): Record<string, unknown> {
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
  const cta = params.ctaUrl
    ? `<p style="margin:32px 0 8px;"><a href="${params.ctaUrl}" style="display:inline-block;background:#102655;color:#ffffff;text-decoration:none;font-weight:700;padding:14px 22px;border-radius:8px;">${params.ctaLabel ?? "Open Grace Connect"}</a></p>`
    : "";
  const html = `
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;">${params.preview}</div>
    <div style="font-family:Arial,Helvetica,sans-serif;background:#f7f3ea;padding:32px 16px;color:#12213d;">
      <div style="max-width:620px;margin:0 auto;background:#ffffff;border-radius:16px;padding:34px;border:1px solid #eadcb6;">
        <p style="margin:0 0 18px;color:#c39213;font-size:13px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;">Grace Connect</p>
        <h1 style="margin:0 0 18px;font-family:Georgia,serif;font-size:30px;line-height:1.15;color:#0d1f4c;">${params.title}</h1>
        <div style="font-size:16px;line-height:1.65;color:#263852;">${params.body}</div>
        ${cta}
        <p style="margin:28px 0 0;font-size:13px;line-height:1.5;color:#69768b;">If you did not request this email, you can ignore it.</p>
      </div>
    </div>
  `;
  return {
    html,
    text: `${params.title}\n\n${plainText(params.body)}${params.ctaUrl ? `\n\n${params.ctaLabel ?? "Open Grace Connect"}: ${params.ctaUrl}` : ""}`,
  };
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
    const message = String(payload?.message ?? payload?.error ?? "Resend rejected the message.");
    throw new Error(message);
  }
  return String(payload?.id ?? "");
}

function actionLinkFromGenerateLink(data: Record<string, unknown> | null): string {
  const properties = data?.properties as Record<string, unknown> | undefined;
  const actionLink = String(properties?.action_link ?? properties?.actionLink ?? "");
  if (!actionLink) throw new Error("Supabase did not return a verification link.");
  return actionLink;
}

async function sendSignupVerification(body: MailRequest): Promise<Response> {
  requireResendKey();
  const email = normalizeEmail(body.email);
  const password = String(body.password ?? "");
  if (password.length < 8) throw new Error("Password must be at least 8 characters.");
  const flowType = String(body.flowType ?? "web_signup").trim();
  if (!["web_church_registration", "web_member_signup"].includes(flowType)) {
    throw new Error("Unsupported signup flow.");
  }
  const redirectTo = allowedRedirect(body.redirectTo);
  const supabase = serviceClient();
  let actionLink = "";
  let usedExistingAccount = false;
  const userData = normalizeSignupData(body.userData, flowType);

  const signupResult = await supabase.auth.admin.generateLink({
    type: "signup",
    email,
    password,
    options: {
      data: userData,
      redirectTo,
    },
  });

  if (signupResult.error) {
    const message = signupResult.error.message.toLowerCase();
    if (!message.includes("already") && !message.includes("registered") && !message.includes("exists")) {
      throw signupResult.error;
    }
    usedExistingAccount = true;
    const magicResult = await supabase.auth.admin.generateLink({
      type: "magiclink",
      email,
      options: { redirectTo },
    });
    if (magicResult.error) throw magicResult.error;
    actionLink = actionLinkFromGenerateLink(magicResult.data as Record<string, unknown>);
  } else {
    actionLink = actionLinkFromGenerateLink(signupResult.data as Record<string, unknown>);
  }

  const isChurch = flowType === "web_church_registration";
  const emailBody = brandedEmail({
    title: isChurch ? "Verify Your Church Registration Email" : "Verify Your Grace Connect Email",
    preview: "Use this secure link to verify your email and continue Grace Connect signup.",
    body: `<p>Hello${userData.full_name ? ` ${userData.full_name}` : ""},</p><p>Use the button below to verify your email address and continue your ${isChurch ? "church registration" : "membership request"}.</p><p>This link is time-sensitive and should only be used by you.</p>`,
    ctaLabel: "Verify Email",
    ctaUrl: actionLink,
  });

  const resendId = await sendResendEmail({
    to: email,
    subject: isChurch ? "Verify your Grace Connect church registration" : "Verify your Grace Connect email",
    html: emailBody.html,
    text: emailBody.text,
  });

  return jsonResponse({ ok: true, provider: "resend", id: resendId, existing_account: usedExistingAccount });
}

async function requireDeveloper(request: Request): Promise<void> {
  const token = accessTokenFromRequest(request);
  if (!token) throw new Error("Developer sign-in is required.");
  const { error } = await anonClient(token).rpc("developer_get_session");
  if (error) throw new Error("Developer access is required.");
}

async function currentUser(request: Request): Promise<{ id: string; email: string }> {
  const token = accessTokenFromRequest(request);
  if (!token) throw new Error("Sign-in is required.");
  const { data, error } = await anonClient(token).auth.getUser(token);
  if (error || !data.user?.id) throw new Error("Sign-in is required.");
  return { id: data.user.id, email: data.user.email ?? "" };
}

async function queuedRowsForSupportTicket(request: Request, ticketId?: string): Promise<EmailRow[]> {
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

  const isReporter = [ticket.userId, ticket.uid].map((value) => String(value ?? "")).includes(user.id) ||
    String(ticket.reporterEmail ?? "").toLowerCase() === user.email.toLowerCase();
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

async function deliverRows(rows: EmailRow[]): Promise<{ ok: boolean; total: number; sent: number; failed: number }> {
  requireResendKey();
  const supabase = serviceClient();
  let sent = 0;
  let failed = 0;

  for (const row of rows) {
    try {
      const providerId = await sendResendEmail({
        to: row.to_email,
        subject: row.subject,
        html: row.html_body,
        text: row.text_body,
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
          error_message: error instanceof Error ? error.message : "Email delivery failed.",
        })
        .eq("id", row.id);
    }
  }

  return { ok: failed === 0, total: rows.length, sent, failed };
}

async function flushDeveloperQueue(request: Request, limit?: number): Promise<Response> {
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
    if (request.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);
    const body = (await request.json().catch(() => ({}))) as MailRequest;

    if (body.action === "auth-signup") return await sendSignupVerification(body);
    if (body.action === "flush-queue") return await flushDeveloperQueue(request, body.limit);
    if (body.action === "flush-support-ticket") {
      const rows = await queuedRowsForSupportTicket(request, body.ticketId);
      return jsonResponse(await deliverRows(rows));
    }

    return jsonResponse({ error: "Unsupported mail action." }, 400);
  } catch (error) {
    return new Response(
      JSON.stringify({ ok: false, error: error instanceof Error ? error.message : "Email delivery failed." }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
