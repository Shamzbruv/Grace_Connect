# Grace Connect Audit Remediation Plan

## Current Status

This plan is based on the attached audit and the current Flutter/Supabase codebase. No commit has been made for this pass.

Completed during this pass:

- Added local auth cleanup after a failed password sign-in so a wrong password attempt does not leave the login flow stuck.
- Hardened notification route parsing so app routes and deep-link-style routes normalize before navigation.
- Added a shared Supabase realtime/session resilience helper.
- Applied guarded realtime handling to notifications and events.
- Added attendance write queueing so temporary network failures do not lose check-ins.
- Added quiz generation run logging migration and best-effort Edge Function writes.
- Added unit tests for notification route normalization and Supabase auth-session error detection.
- Replaced the login screen's raw snackbars with the shared app-styled snackbar.
- Fixed placeholder web manifest colors in `pubspec.yaml`.
- Applied the pending Supabase migrations, including quiz generation observability.
- Deployed the updated `generate-daily-bible-quiz` Edge Function.

Verified during this pass:

- `dart format`
- `git diff --check`
- `flutter analyze`
- `flutter test`

Already addressed before this audit pass:

- Daily quiz generation now has a larger fallback bank and avoids recent repeated question hashes.
- `generate-daily-bible-quiz` was deployed to Supabase.
- Custom notification channels/sounds exist for messages, devotionals, quiz, prayer, and live stream notifications.
- Several community and inbox realtime streams already have fallback behavior when realtime subscriptions time out.

## Phase 1: Critical Stability And Trust Fixes

1. Authentication retry reliability
   - Keep the new failed-login cleanup.
   - Add a regression test for wrong password followed by correct password.
   - Confirm the app does not clear remembered email on wrong password.
   - Confirm unverified-email sign-in still signs out locally and shows the resend prompt.

2. Realtime expired-token resilience
   - Create a shared guarded realtime helper for Supabase streams.
   - Apply it to notifications, attendance, members, prayers, counseling, events, and role streams.
   - On `InvalidJWTToken`, refresh the Supabase session once, then retry the initial fetch.
   - Never blank a screen because realtime fails; keep last-known data and show a small retry state.

3. Notification deep links
   - Keep route normalization from this pass.
   - Add tests for `/daily_word?id=...`, `/daily_bible_quiz?month=...`, `/live_streaming`, `/inbox`, and unknown routes.
   - Ensure cold-start, background, and foreground notification opens all use the same route handling.

4. Crash/error monitoring
   - Confirm Firebase Crashlytics is configured for Android and iOS.
   - Add custom keys for user role, church id, current route, theme mode, and network state.
   - Avoid logging secrets, tokens, prayer/counseling text, or private message bodies.

## Phase 2: Quiz Reliability

1. Server-side generation observability
   - Add a `quiz_generation_runs` table or audit rows with run time, source, church id, error, and question hashes.
   - Log when AI generation fails and when curated fallback is used.
   - Add an admin-visible quiz health panel showing last generation time and source.

2. Daily freshness guarantees
   - Add a force-regenerate admin action for today's quiz when the generated set is bad.
   - Prevent reuse of the same full five-question set for at least 60 days per church.
   - Keep the client status endpoint as the source of truth; avoid local caching beyond the current response.

3. Scheduler checks
   - Verify Supabase cron schedules call `generate-daily-bible-quiz` at 7:00 AM Jamaica time.
   - Add an alert or notification if no quiz is published by 7:10 AM.
   - Add a synthetic check that fetches the quiz daily and confirms the quiz date matches Jamaica today.

## Phase 3: UI And Theme Audit

1. Central theme tokens
   - Review `AppTheme`, cards, buttons, text fields, switches, sliders, and bottom sheets.
   - Replace hard-coded dark grays and muted text colors with theme tokens.
   - Fix low-contrast text in dark mode, especially settings, Bible reader controls, attendance, support, and beta feedback.

2. Pop-up consistency
   - Replace raw `SnackBar`, `AlertDialog`, and default modal sheets with app-styled equivalents.
   - Standardize success, warning, destructive confirmation, and error states.
   - Ensure pop-ups respect dark mode and have enough contrast.

3. Screenshot QA
   - Add golden/screenshot tests for login, home, feed, event create/edit, attendance, quiz, daily word, notifications, inbox, and settings.
   - Test both light and dark mode at mobile and tablet widths.

## Phase 4: Data Sync And Refresh

1. Pull-to-refresh
   - Audit all refresh buttons and pull-to-refresh handlers.
   - Disable duplicate refreshes while a request is in flight.
   - Keep stale content visible while refreshing, then update in place.

2. Offline attendance queue
   - Add a persistent local queue for attendance attempts.
   - Sync queued attempts when network returns.
   - Deduplicate by user, service id, day, and status.

3. Attendance correctness
   - Confirm service start/end windows and late thresholds are church-configurable.
   - Fix late marking when a user signs in before or during the allowed early window.
   - Auto-mark absent only after the service window closes and only for expected attendees.

## Phase 5: Notifications And Permissions

1. Topic subscriptions
   - Confirm every notification toggle maps to the right Firebase topic and Supabase preference column.
   - Re-sync topics when the user's church, role, or notification settings change.

2. Push payload contract
   - Standardize payload fields: `title`, `body`, `type`, `route`, `entity_table`, `entity_id`, `church_id`.
   - Use the same contract for Edge Functions, Cloud Functions, and local foreground notifications.

3. Permission states
   - Show app-styled prompts for denied notification permission, disabled OS notifications, and missing background location.

## Phase 6: Testing And Release Gate

1. Automated checks
   - Keep `flutter analyze` and `flutter test` required before release.
   - Add unit tests for auth retry, notification route normalization, quiz date logic, media display formats, and attendance status.

2. Manual release checklist
   - Wrong password then correct password.
   - Daily quiz changes after a generated day.
   - Push opens correct screen from killed/background/foreground app.
   - Dark mode pass on top 20 screens.
   - Attendance normal, late, remote, absent, offline, and retry scenarios.
   - Feed/story image format selection.
   - Profile photo crop and sync to previous posts.

3. Deployment order
   - Supabase migrations were applied first.
   - The changed quiz Edge Function was deployed.
   - Android/iOS distribution is still a release step after product sign-off.
   - Push GitHub commit after validation.
