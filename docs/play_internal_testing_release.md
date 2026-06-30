# Play Internal Testing Release

Use this checklist for the Grace Connect internal testing upload.

## Release

- Release name: `Grace Connect 1.0.16-beta (17)`
- App bundle: `build/app/outputs/bundle/release/app-release.aab`
- Release notes: `release_notes/internal-testing-en-US.txt`
- Package ID: `love.graceconnect`
- Upload certificate SHA-1: `EC:9E:91:4F:CB:98:12:91:A9:E5:78:6C:CF:7D:72:B7:52:67:6D:AC`
- Upload certificate SHA-256: `57:0B:F1:0C:B5:BE:B4:35:CD:1F:AF:75:CC:17:73:78:75:FD:9E:30:F1:D4:31:69:D9:24:77:A0:40:62:F3:B2`

## Required Console Checks

- Firebase Android app package is `love.graceconnect`.
- Firebase has the upload certificate SHA-1 and SHA-256 used for the release AAB.
- After Play App Signing is enabled, add the Play App Signing SHA-1 to Firebase and Google Maps API key restrictions.
- Supabase auth redirect allowlist includes:
  - `app.graceconnect.church://login-callback/`
  - `app.graceconnect.church://reset-callback/`
  - `https://graceconnect-9a97c.web.app/auth/callback`
  - the production website callback URL if using hosted auth links.
- Google Maps Android key restriction uses package `love.graceconnect` plus the release and Play App Signing SHA-1 values.

## Local Verification

Run these before upload:

```bash
flutter analyze
flutter test test/beta_hardening_static_test.dart test/membership_service_test.dart test/notification_route_test.dart
flutter build appbundle --release
```
