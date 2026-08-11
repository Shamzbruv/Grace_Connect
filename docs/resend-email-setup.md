# Resend Email Setup

Grace Connect sends public signup verification links, password reset links, and
queued platform emails through the `grace-mailer` Supabase Edge Function. App
code never receives the Resend API key.

## Required deployment order

The public mail actions fail closed if their database rate limiter is missing.
Apply and verify
`supabase/migrations/20260805200000_grace_mailer_public_abuse_protection.sql`
before deploying the matching `grace-mailer` code. Do not deploy the function
first.

1. Back up and test all pending migrations in a staging project.
2. Run `supabase db push --dry-run --linked` and review the complete ordered
   migration list.
3. Apply the approved migrations through the normal release pipeline.
4. Set or confirm the Edge Function secrets below.
5. Deploy `grace-mailer` and smoke-test signup and password reset delivery.

Required Supabase Edge Function secrets:

```bash
supabase secrets set \
  RESEND_API_KEY="re_xxxxxxxxxxxxxxxxx" \
  RESEND_FROM_EMAIL="notifications@graceconnect.love" \
  RESEND_FROM_NAME="Grace Connect" \
  RESEND_REPLY_TO="support@graceconnect.love" \
  PUBLIC_SITE_URL="https://www.graceconnect.love" \
  MAIL_ALLOWED_REDIRECT_ORIGINS="https://www.graceconnect.love,https://graceconnect.love,http://localhost:3000" \
  MAIL_RATE_LIMIT_PEPPER="replace-with-a-long-random-secret"
```

Deploy the function after changing secrets or code:

```bash
supabase functions deploy grace-mailer \
  --project-ref nimgsgnkcvddomrgkawb \
  --no-verify-jwt \
  --use-api
```

## Public mail rate limits

The migration creates a service-role-only event table and a transactional RPC.
It stores keyed HMAC values instead of raw email addresses or IP addresses.
Concurrent requests are serialized with transaction advisory locks before an
event is consumed. Current limits are:

- Per email: one request per minute and three per hour for each action.
- Signup per IP: 10 per 10 minutes and 40 per day.
- Password reset per IP: 12 per 10 minutes and 60 per day.
- Signup globally: 120 per hour and 600 per day.
- Password reset globally: 180 per hour and 900 per day.

Rate-limited responses use HTTP `429` and include a bounded `Retry-After`
header. A missing RPC, malformed RPC response, or missing hashing key uses HTTP
`503`; requests do not continue to Supabase Auth or Resend.

`MAIL_RATE_LIMIT_PEPPER` must be at least 32 characters and is recommended so
rate keys are independent of other credentials. If it is absent, the function
uses the built-in `SUPABASE_SERVICE_ROLE_KEY` as the HMAC key. Rotating the
pepper invalidates the short-lived historical counters.

## Optional CAPTCHA

CAPTCHA is off by default so current clients keep working. The verifier uses
Cloudflare Turnstile's HTTPS `siteverify` endpoint by default, but the endpoint
can be overridden for a compatible provider.

The request JSON must contain `captchaToken` before CAPTCHA is enabled. Ship
and test token collection in every affected client first. The public website
uses `auth-signup`; the Flutter app uses `password-reset`.

Set the provider secret and validation constraints while CAPTCHA is still off:

```bash
supabase secrets set \
  MAIL_CAPTCHA_SECRET="provider-secret" \
  MAIL_CAPTCHA_ALLOWED_HOSTNAMES="www.graceconnect.love,graceconnect.love" \
  MAIL_CAPTCHA_SIGNUP_ACTION="grace-signup" \
  MAIL_CAPTCHA_RESET_ACTION="grace-password-reset"
```

After the corresponding client is live, enable one action at a time:

```bash
supabase secrets set MAIL_CAPTCHA_SIGNUP_REQUIRED="true"
supabase secrets set MAIL_CAPTCHA_RESET_REQUIRED="true"
```

`MAIL_CAPTCHA_REQUIRED=true` is a global fallback when neither per-action flag
is set. An explicit per-action true/false value overrides the global flag.
Accepted boolean values are `true`, `false`, `1`, `0`, `yes`, `no`, `on`, and
`off`; an invalid value fails closed. Optional
`MAIL_CAPTCHA_VERIFY_URL` must be HTTPS. Provider/network failures return
HTTP `503`, and missing, invalid, wrong-hostname, or wrong-action tokens return
HTTP `403`. CAPTCHA tokens and provider secrets are never logged.

## Supabase Auth templates

The repository also contains branded authentication and security-notification
templates in `supabase/templates`. With Supabase CLI 2.113, authentication
template paths (including reauthentication) are project-root-relative and use
`./supabase/templates/...`; security-notification paths are config-relative and
use `./templates/...`. Preserve that intentional difference.

`supabase db push` does not publish hosted Auth email templates. Apply and
enable them through the hosted project's Auth Email Templates settings or the
Supabase Management API, then send render tests for reauthentication, password,
email, phone, MFA, and identity changes before release.

Notes:

- `RESEND_FROM_EMAIL` must be on a domain verified in Resend.
- The public website uses `auth-signup` to create the Supabase confirmation
  link and send it through Resend.
- The Flutter app uses `password-reset` so reset messages are branded and open
  the app callback instead of showing a plain Supabase email.
- The developer portal uses `flush-queue` after approval/rejection/support
  actions to send queued `email_notification_queue` rows through Resend.
- Add these Supabase Auth redirect URLs before release testing:
  `app.graceconnect.church://login-callback/`,
  `app.graceconnect.church://reset-callback/`,
  `https://www.graceconnect.love/auth/callback`, and
  `http://localhost:3000/auth/callback`.
