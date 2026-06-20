# Google Maps and Cloud API Setup

Firebase/Google Cloud project: `graceconnect-9a97c`

## Current Cloud state

Updated on 2026-06-19:

- Enabled API Keys API, Maps SDK for Android, Maps SDK for iOS, Maps JavaScript API, and Places API.
- Created `GraceConnect Android Maps SDK`, restricted to package `com.example.grace_connect`, the local debug SHA-1, and Maps SDK for Android only.
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
- Package name: `com.example.grace_connect`
- SHA-1 certificate: add the debug SHA-1 for local builds and the release/Play App Signing SHA-1 for production
- API restriction: Maps SDK for Android
- Local config: add `GOOGLE_MAPS_API_KEY_ANDROID=...` to `android/local.properties`, or export it as an environment variable

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

Places REST key:

- Current config: pass `--dart-define=GOOGLE_PLACES_API_KEY=...` when building/running, or it falls back to `GOOGLE_MAPS_API_KEY`
- API restriction: Places API
- Best production setup: proxy the Places search through Cloud Functions so the Places key can be server/IP restricted instead of shipped inside the mobile app
