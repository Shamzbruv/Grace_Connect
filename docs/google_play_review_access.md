# Google Play Review Access

Grace Connect uses normal Supabase Auth accounts for Google Play review. Reviewers should never receive developer-portal access and should not need email verification, OTP, church approval, payment, invite links, location setup, or Google sign-in to test the app.

## Demo Environment

- Demo church: `Grace Connect Review Demo Church`
- Church id: `grace_connect_review_demo_church`
- Church status: approved and active
- Subscription: active, system-granted review subscription
- Public directory visibility: hidden from ordinary public search
- Reviewer data: seeded sample-only content, no real members or payments

## Setup Command

Run the Supabase migration first, then run the script with secrets supplied through environment variables:

```bash
export SUPABASE_URL="https://nimgsgnkcvddomrgkawb.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="paste-service-role-key-here"
export PLAY_REVIEW_MEMBER_EMAIL="play-review-member@example.com"
export PLAY_REVIEW_MEMBER_PASSWORD="choose-a-strong-review-password"
export PLAY_REVIEW_ADMIN_EMAIL="play-review-admin@example.com"
export PLAY_REVIEW_ADMIN_PASSWORD="choose-a-strong-review-password"

python3 scripts/setup_google_play_review_accounts.py
```

The script creates or updates two email-confirmed Supabase Auth users, attaches both to the demo church, and seeds the demo church with announcements, an event, a ministry, a study group, a group message, profile details, and optional prayer/attendance sample rows when those tables are available.

## Play Console App Access

Use this text in Play Console app access instructions:

```text
Some Grace Connect features require signing in and belonging to a church.

Use these reusable review accounts:

Demo member
Email: <PLAY_REVIEW_MEMBER_EMAIL>
Password: <PLAY_REVIEW_MEMBER_PASSWORD>

Demo church admin
Email: <PLAY_REVIEW_ADMIN_EMAIL>
Password: <PLAY_REVIEW_ADMIN_PASSWORD>

Both accounts are already email-confirmed and approved in Grace Connect Review Demo Church. No OTP, email verification, Google sign-in, payment, invite link, location setup, or church approval is required during review.

The member account can browse the subscribed demo church, Bible, Daily Word, quiz, groups, events, announcements, profile, support, and beta feedback flows.

The church admin account can additionally review church-management features such as member/admin tools, ministries, events, announcements, church profile, giving-link setup, and ownership transfer.

Developer Portal / Developer Console access is intentionally not provided to Play reviewers.
```

## Safety Checks

- Reviewer accounts are not inserted into `developer_accounts`.
- Reviewer `users."isDeveloper"` is set to `false`.
- The demo church subscription uses `source = 'system'` and stores no payment details.
- The demo church is hidden from public church search by `public_visibility = false`.
- The script is idempotent and can be rerun to reset passwords and demo membership.
