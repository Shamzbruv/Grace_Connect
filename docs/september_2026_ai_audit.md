# September 20–21 AI change audit

Scope: app commits `d3d0ca0` through `aeacf65` (59 files), landing-page commits `0bae185` and `7dba7c8` (31 files), and corresponding deployed Supabase migrations/functions. Earlier attendance and Reel changes are included in regression testing where these commits depend on them.

## Confirmed defects corrected

- Church-logo object paths contained escaped interpolation, so storage received literal placeholders. Unique valid paths, image-type/size checks, upload failure recovery, live-church logos, and editor refresh behavior are corrected.
- Live church discovery trusted a caller-supplied church ID for private-stream access. The argument remains compatible, but authorization now uses the signed-in viewer's church.
- The profile migration left two defaulted RPC overloads, making older clients ambiguous. One compatible signature remains; old clients preserve new pastor details. Invalid timezone edits are rejected before they can break attendance.
- Haptic calls did not await platform failures, the test action bypassed opt-out, and the shared scale button ignored the preference. Feedback now contains asynchronous failures and respects the preference.
- Analytics passed unsupported booleans and raw route parameters. Typed values and static screen names are used. Website tracking excludes recovery pages and removes URL queries/fragments from page-location and referrer fields.
- Bible search could mix numbered books, offer zero references, or accept a stale preview after the query changed. Search selection captures the navigator before closing the search route.
- The share catalogue resurrected disabled backgrounds from its old manifest and cached changes indefinitely. Empty catalogues are authoritative, cache lifetime is bounded, and unique uploads roll back if catalogue insertion fails.
- Quote-card character estimates could still overflow. The complete text/reference/reflection label scales down together to fit.
- Profile grids could download a complete video as if it were an image when no poster existed. They now use the text/video fallback.
- Reel activity did not explicitly follow the selected main tab. Tab changes now deactivate the reel screen, and feed-mode changes release playback ownership.
- Stale Bible streaks were presented as current; their display now identifies historical streaks. Recency uses the same calendar as the existing reading ledger.
- Global quiz ranks omitted completed zero-score attempts, accepted malformed months, and used inconsistent tie ordering. The church endpoint silently hit the API row limit when aggregating attempts. Aggregation is now done in Postgres, with deterministic ordering and the viewer's rank returned independently of the page.
- Rankings now honor bilateral blocks and redact the identity of private profiles on the global board.
- Payment application trusted a successful hook without matching checkout amount/currency, used email as a church lookup, and could replay a checkout under another transaction. It now requires the exact reference, amount, currency, and valid payment date; event and checkout processing are idempotent.
- Cancellation used a nonexistent `users.name` column. Subsequent payments used an upsert that collided with the church alias guard. Both paths now work with canonical/legacy church aliases and share a transaction lock. Payments preserve paid-through access and pending cancellation.
- A payment was treated as proof of automatic renewal and a hosted billing portal, neither of which this integration establishes. The code records verified paid access; copy no longer promises processor-side cancellation. Recurring provider configuration still needs owner confirmation.
- Billing events stored raw payloads, including a possible legacy JWT and payment/contact fields. Only reconciliation fields are retained.
- Enterprise checkout was disabled during rendering and then re-enabled in `finally`; HTML rendering also interpolated unescaped server values. Both are corrected.
- Live verification found that the Fygaro webhook secret is not configured. Checkout now requires both payment and webhook configuration before creating a session; the website disables payment and offers billing support until setup is complete.
- Mobile subscription links offered global external checkout without storefront eligibility integration. Web checkout remains on the website; the mobile build provides existing-account support/cancellation requests.

## Verification and limits

Before this audit, Flutter analysis passed despite these runtime/behavior defects. New rollback-only database tests cover payment authorization, amount/currency mismatch, idempotency, aliases, cancellation, timezone validation, legacy profile calls, ranking privacy and viewer rank. No live accounts, churches, attendance history, or payments were deleted or created by these tests.

The one-time platform reset was not executed. No payment was charged, no processor-side recurring schedule was cancelled, and physical Samsung/iPhone behavior or Analytics dashboard ingestion is not claimed by these checks.

Final test results, deployment versions, AAB checksum/signature and release notes are recorded with the release artifacts in `../releases/1.1.1+39/` after verification completes.

### Backend deployment verified September 21

- Migrations `20260921113250` and `20260921113252` are live; filenames match the server migration history.
- Edge versions: quiz leaderboard 22, subscription management 6, Fygaro webhook 7. User endpoints still require JWT verification; the webhook remains public and requires its own HMAC verification.
- 79 rollback-only database assertions pass: audit 23, attendance timezone/services 15, attendance arrival acknowledgement 27, global testimony/ranking regression 14. The 23 audit assertions also pass against the deployed schema.
- All 53 Edge unit tests and type checks pass. All 29 website unit/static tests pass.
- Landing PR 7 was merged as `2305e01`; Railway deployment `6577355172` succeeded, and the live checkout script matches the guard. Four mobile-width pages passed browser checks without JavaScript page errors or horizontal overflow.
- App CI [run 35650756783](https://github.com/Shamzbruv/Grace_Connect/actions/runs/35650756783) passed on source commit `a82886a`: Flutter analysis, the complete Flutter suite, Android attendance unit tests, 53 Edge tests and 8 retention worker tests. Earlier failed runs caught analyzer warnings, an incorrect multipart test assertion, and a mismatch between the Flutter and Android version declarations; these were corrected before the final release build.
- Security advisors were compared with the pre-audit state. Anonymous privileged function exposure decreased from 155 to 152, and authenticated exposure from 192 to 191. Existing advisory categories remain (16 mutable search paths, GraphQL schema visibility, intentionally closed internal tables, and disabled leaked-password protection); this is not a claim that every historic database advisory has been eliminated. See [Supabase advisor guidance](https://supabase.com/docs/guides/database/database-linter) and [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

### Payment setup still required

The live webhook currently rejects requests because no usable `FYGARO_WEBHOOK_SECRET` (or key-ID rotation map `FYGARO_WEBHOOK_SECRETS`) is configured. Configure the matching signing secret in Fygaro and Supabase Edge secrets; never put it in Flutter or this repository. The checkout additionally needs `FYGARO_BUTTON_URL`, `FYGARO_KEY_ID`, and `FYGARO_SECRET_KEY`, then a provider sandbox payment should verify the full delivery path. No real payment was attempted. This integration grants one paid month per verified checkout; a separately configured recurring provider schedule has not been confirmed.

### Preview database limitation

The Supabase Preview check for PR 6 fails while replaying the old migration history into an empty database: `relation public.users does not exist`, at the first migration's `drop policy ... on public.users`. The repository starts with changes to an existing schema rather than its initial creation. The audit migrations were tested against the real deployed schema in rollback-only transactions and applied successfully. Restoring a complete historical schema baseline for fresh preview databases remains separate work; the failed preview check was not disabled or marked successful.

Reference checks: [Fygaro webhook contract](https://help.fygaro.com/en-us/article/payment-button-hook-1wkui1k/), [Fygaro signed checkout](https://help.fygaro.com/en-us/article/fygaro-links-integration-api-h78p9y/), [Google Play payments guidance](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en), [Firebase page-location configuration](https://firebase.google.com/docs/reference/js/analytics.gtagconfigparams).
