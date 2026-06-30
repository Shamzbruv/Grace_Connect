# Resend Email Setup

Grace Connect sends public signup verification links and queued platform emails
through the `grace-mailer` Supabase Edge Function.

Required Supabase Edge Function secrets:

```bash
supabase secrets set \
  RESEND_API_KEY="re_xxxxxxxxxxxxxxxxx" \
  RESEND_FROM_EMAIL="notifications@graceconnect.love" \
  RESEND_FROM_NAME="Grace Connect" \
  RESEND_REPLY_TO="support@graceconnect.love" \
  PUBLIC_SITE_URL="https://www.graceconnect.love" \
  MAIL_ALLOWED_REDIRECT_ORIGINS="https://www.graceconnect.love,https://graceconnect.love"
```

Deploy the function after changing secrets or code:

```bash
supabase functions deploy grace-mailer
```

Notes:

- `RESEND_FROM_EMAIL` must be on a domain verified in Resend.
- The public website uses `auth-signup` to create the Supabase confirmation
  link and send it through Resend.
- The developer portal uses `flush-queue` after approval/rejection/support
  actions to send queued `email_notification_queue` rows through Resend.
