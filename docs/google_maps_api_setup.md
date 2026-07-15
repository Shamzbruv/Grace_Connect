# Google Maps and Cloud API Setup

Firebase/Google Cloud project: `graceconnect-9a97c`

## Current Cloud state

Updated on 2026-07-14:

- Enabled API Keys API, Maps SDK for Android, Maps SDK for iOS, Maps JavaScript API, Places API, and Geocoding API.
- `GraceConnect Android Maps SDK` is restricted to Android apps and allows Maps SDK for Android, Places API, Places API (New), and Geocoding API.
- The Android Maps key currently allows package `love.graceconnect` with the debug SHA-1, upload/release SHA-1, and Firebase-recorded Play App Signing SHA-1.
- Created `GraceConnect iOS Maps SDK`, restricted to bundle ID `com.example.graceconnect` and Maps SDK for iOS only.
- Added the new native key strings to ignored local config files: `android/local.properties` and `ios/Flutter/MapsKeys.xcconfig`.

## APIs this app uses

Enable these for the map and church geofence picker:

- Maps SDK for Android
- Maps SDK for iOS
- Maps JavaScript API
- Places API

The current Dart search service calls the legacy Places Text Search endpoint:
`https://maps.googleapis.com/maps/api/place/textsearch/json`.

The broader Firebase project also depends on these common APIs:

- Cloud Firestore API
- Firebase Authentication / Identity Toolkit API
- Firebase Cloud Messaging API
- Firebase Storage / Cloud Storage for Firebase
- Cloud Functions API
- Cloud Run Admin API
- Cloud Build API
- Artifact Registry API
- Eventarc API
- Pub/Sub API
- Cloud Scheduler API

## Keys and restrictions

Use separate Google Maps keys per platform. Do not use an HTTP-referrer-only web key for Android or iOS native maps.

Android Maps key:

- Application restriction: Android apps
- Debug/release package name: `love.graceconnect`
- SHA-1 certificate: add the debug SHA-1 for local builds, the upload/release SHA-1 for locally installed release builds, and the Play App Signing SHA-1 for Play-distributed builds
- API restriction: Maps SDK for Android, Places API, Places API (New), and Geocoding API
- Local/release config: add `GOOGLE_MAPS_API_KEY_ANDROID=...` to ignored `android/local.properties`, pass it as a Gradle property, or export it as an environment variable
- Gradle manifest placeholder: `googleMapsApiKey`
- Android manifest metadata populated by that placeholder: `com.google.android.geo.API_KEY`

`GOOGLE_MAPS_API_KEY_ANDROID` is required for Android release builds. The
Gradle release validation fails before packaging when it is missing or blank,
or when `GRACE_CONNECT_APPLICATION_ID` is not explicitly set to
`love.graceconnect`. Do not commit Maps keys to GitHub, Flutter source,
AndroidManifest.xml, or public docs.

iOS Maps key:

- Application restriction: iOS apps
- Bundle ID: `com.example.graceconnect`
- API restriction: Maps SDK for iOS
- Local config: copy `ios/Flutter/MapsKeys.xcconfig.example` to `ios/Flutter/MapsKeys.xcconfig` and set `GOOGLE_MAPS_API_KEY_IOS=...`

Web Maps key:

- Application restriction: HTTP referrers
- Allowed referrers: your Firebase Hosting domain, custom production domain, localhost/dev URLs you use
- API restriction: Maps JavaScript API, plus Places API only if web search uses it
- Current file: `web/index.html`

Places REST on Android:

- Current config: prefer `--dart-define=GOOGLE_PLACES_API_KEY=...` when building/running; Android release builds can also fall back to the manifest `GOOGLE_MAPS_API_KEY_ANDROID` value and send Android package/certificate restriction headers.
- API restriction: Places API, Places API (New), and Geocoding API when sharing the Android Maps key for the geofence picker
- Best production setup: proxy the Places search through Cloud Functions so the Places key can be server/IP restricted instead of shipped inside the mobile app
