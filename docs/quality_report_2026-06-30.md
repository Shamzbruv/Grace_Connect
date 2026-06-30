# Grace Connect Quality Report - 2026-06-30

## Scope

This pass covered the mobile app settings/support flows, subscription gating, notification icon configuration, Play internal-testing release readiness, and Supabase reviewer/demo access setup.

## Fixed

- Transfer Ownership now has a usable email field, search button, active-membership lookup through `church_memberships`, and a scrollable layout for small devices.
- Beta Feedback now submits into the developer issue queue with screenshot attachments, app version, device details, auth email, and church/user context.
- Developer Console visibility in Settings now depends on Supabase-confirmed developer access, and the console route itself still blocks unauthorized users.
- Terms of Service and Privacy Policy rows now open the public website legal pages.
- Android notifications now use the Grace Connect notification resource for the OS notification panel. Android small notification icons are monochrome by platform design.
- Churches without active subscriptions are now limited to Bible and Daily Word access; church management/feed tools are paused.
- Daily Word and Daily Bible Quiz alert dots now clear after acknowledgement using local per-day/per-content keys.
- Giving Settings now centers on the SpurrOpen giving link and tells churches SpurrOpen is free to sign up for.
- Settings no longer labels the giving setup as Finance, and the visible app version was updated to `1.0.15-beta`.
- Release version bumped to `1.0.15-beta+16`, with Android `versionCode 16`.

## Supabase

- Applied remote migration: `20260630193000_play_review_demo_access.sql`.
- Seeded a hidden approved demo church record with an active system-granted subscription and daily quiz/demo daily word content.
- Added developer-flag cleanup so `users."isDeveloper"` matches active `developer_accounts`.
- Added `scripts/setup_google_play_review_accounts.py` to create the Play reviewer member/admin accounts from environment variables only.

The reviewer account script was not executed from this terminal because `SUPABASE_SERVICE_ROLE_KEY`, `PLAY_REVIEW_MEMBER_EMAIL`, `PLAY_REVIEW_MEMBER_PASSWORD`, `PLAY_REVIEW_ADMIN_EMAIL`, and `PLAY_REVIEW_ADMIN_PASSWORD` were not present in the environment.

## Verification

- `dart format` completed for touched Dart files.
- `python3 -m py_compile scripts/setup_google_play_review_accounts.py` passed.
- `flutter analyze` passed with no issues.
- Focused test suite passed:
  - `test/beta_hardening_static_test.dart`
  - `test/membership_service_test.dart`
  - `test/notification_route_test.dart`
- Full `flutter test` passed.
- `git diff --check` passed.
- Release AAB built successfully at `build/app/outputs/bundle/release/app-release.aab`.

## Release

- Release name: `Grace Connect 1.0.15-beta (16)`
- Package id: `love.graceconnect`
- AAB: `build/app/outputs/bundle/release/app-release.aab`
- Release notes: `release_notes/internal-testing-en-US.txt`
- Play reviewer access instructions: `docs/google_play_review_access.md`

## Residual Risk

- The Play reviewer accounts still need to be created by running `scripts/setup_google_play_review_accounts.py` with the required environment variables.
- The Android notification status-bar icon will appear monochrome because Android masks small notification icons; the app launcher/large icon remains branded.
