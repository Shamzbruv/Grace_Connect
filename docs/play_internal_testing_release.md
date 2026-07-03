# Play Internal Testing Release

Use this checklist for the Grace Connect internal testing upload.

## Release

- Release name: `Grace Connect 1.0.18-beta (20)`
- App bundle: `build/app/outputs/bundle/release/app-release.aab`
- Release notes: `release_notes/internal-testing-en-US.txt`
- Package ID: `love.graceconnect`
- Required Android release package property: `GRACE_CONNECT_APPLICATION_ID=love.graceconnect`
- Required Android Maps Gradle property: `GOOGLE_MAPS_API_KEY_ANDROID`
- Android Maps manifest placeholder: `googleMapsApiKey`
- Generated manifest metadata: `com.google.android.geo.API_KEY`
- Debug certificate SHA-1: `CE:35:7B:C3:9B:E3:88:86:8C:78:0D:F3:62:1C:6E:D4:75:DE:11:6B`
- Upload certificate SHA-1: `EC:9E:91:4F:CB:98:12:91:A9:E5:78:6C:CF:7D:72:B7:52:67:6D:AC`
- Upload certificate SHA-256: `57:0B:F1:0C:B5:BE:B4:35:CD:1F:AF:75:CC:17:73:78:75:FD:9E:30:F1:D4:31:69:D9:24:77:A0:40:62:F3:B2`
- Firebase Android certificate SHA-1, likely Play App Signing: `E9:67:2C:0A:6E:4E:B6:31:18:69:FC:88:E5:08:1D:9B:9A:B0:1B:19`

## Required Console Checks

- Firebase Android app package is `love.graceconnect`.
- Firebase has the upload certificate SHA-1/SHA-256 and the Play App Signing SHA-1 used for Play-distributed installs.
- Google Cloud billing is active on the project that owns the Android Maps key.
- Maps SDK for Android is enabled.
- Places API (New) is enabled if church search uses Places.
- Geocoding API is enabled if reverse geocoding or address lookup is enabled.
- Supabase auth redirect allowlist includes:
  - `app.graceconnect.church://login-callback/`
  - `app.graceconnect.church://reset-callback/`
  - `http://localhost:3000/auth/callback`
  - `https://graceconnect-9a97c.web.app/auth/callback`
  - the production website callback URL if using hosted auth links.
- Google Maps Android key restriction uses package `love.graceconnect` plus the debug, upload/release, and Play App Signing SHA-1 values.
- If locally-installed release builds are tested, also add the local/upload release keystore SHA-1 to the Android-restricted Maps key.

## Local Verification

Run these before upload:

```bash
flutter analyze
flutter test test/beta_hardening_static_test.dart test/membership_service_test.dart test/notification_route_test.dart
(cd android && ./gradlew :app:validateGraceReleaseConfig)
flutter build appbundle --release
```

Release builds intentionally fail before packaging when
`GRACE_CONNECT_APPLICATION_ID` is missing/not `love.graceconnect`, when
`GOOGLE_MAPS_API_KEY_ANDROID` is missing/blank, when the
`googleMapsApiKey` manifest placeholder is blank, or when release signing is
not configured. Do not hardcode the Maps key in GitHub, Flutter source,
AndroidManifest.xml, or public documentation.
