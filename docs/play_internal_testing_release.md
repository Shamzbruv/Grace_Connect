# Play Internal Testing Release

Use this checklist for the Grace Connect internal testing upload.

## Release

- Release name: `Grace Connect 1.0.31-beta (35)`
- App bundle: `build/app/outputs/bundle/release/grace-connect-1.0.31-beta+35.aab`
- Previous bundle backup: `../.release_backups/20260905/grace-connect-1.0.30-beta+34.aab`
- Release notes: `release_notes/internal-testing-en-US.txt`
- Package ID: `love.graceconnect`
- Compile/target SDK: Android 16 / API 36
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

## Android 16 And Auto-Attendance Policy

- Google Play requires new apps and updates to target API 36 beginning August
  31, 2026. This release uses `compileSdkVersion 36`, `targetSdkVersion 36`,
  Android Gradle Plugin 8.9.2, and Android 36 build tools. See the official
  [target API requirement](https://developer.android.com/google/play/requirements/target-sdk)
  and [Android 16 SDK setup](https://developer.android.com/about/versions/16/setup-sdk).
- Auto-attendance now registers a native Android Geofence API dwell transition;
  it does not continuously stream location through a location foreground
  service. Google removes geofencing as an approved *foreground-service* use
  case on August 26, 2026 and directs apps to the Geofence API instead. See the
  [Play policy preview](https://support.google.com/googleplay/android-developer/answer/16965181?hl=en)
  and [Android geofence guide](https://developer.android.com/develop/sensors-and-location/location/geofencing).
- The Geofence API is part of Google Play services location. It does **not**
  require another Google Cloud API key or a separate billable “Geofencing API.”
  It does require `ACCESS_FINE_LOCATION` and, for target API 29+, approved
  `ACCESS_BACKGROUND_LOCATION` access.
- In Play Console, do not declare/select a location foreground-service use case
  for auto-attendance after this migration. The merged release manifest must not
  contain `FOREGROUND_SERVICE_LOCATION`.
- Complete Play Console's background-location declaration for auto-attendance,
  provide the requested review video, keep the privacy policy accurate, and
  show the in-app prominent disclosure before Android's permission flow. The
  member must explicitly enable Auto-Attendance; denial leaves it off.
- Device validation must cover: permission denied, “while using” only, “allow
  all the time,” force-stopped/reopened app, reboot, Doze, entering/exiting the
  saved church radius, and a full configured dwell during an active service.

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
