# Grace Connect launch and Reel Grace implementation — September 17, 2026

## Audit before implementation

- `lib/screens/main/main_tabs_screen.dart` uses five PageView destinations; Feed is index 0. Re-tapping Feed currently requests scroll-to-top. `lib/widgets/app_bottom_menu.dart` owns the destination controls. Preserve Community Feed state while adding an internal FeedHub mode and accessible long press.
- `lib/screens/community/community_feed_screen.dart` provides creation, existing feed scopes, access checks, public profiles and live-church cards. Preserve these behaviors. `lib/services/community_service.dart` uses streams and Supabase Storage for normal posts; neither is appropriate for reel media or the reel feed.
- `lib/widgets/community_video_player.dart` already provides bounded initialization, poster-first rendering, visibility/lifecycle handling, playback coordination and cleanup. Add a dedicated bounded Reel coordinator; make playback ownership shared across community and reels.
- `lib/utils/community_video_inspection.dart` generates JPEG previews but does not normalize codecs, duration, bitrate or progressive MP4 layout. Add a native media preparation plugin using supported platform media APIs; validate the resulting file server-side before publication.
- Existing `social_saved_items` supports an entity type and can be extended to reels. Reuse `social_follows`, `user_blocks`, `content_reports`, public profiles and trusted access checks. Reporting/blocking Dart methods currently reject empty church IDs; global operations need explicit server authorization.
- `lib/main.dart` initializes Firebase, but analytics instrumentation is missing. The supplied google-services.json contains the existing production love.graceconnect app plus an obsolete example app. Verify and retain only the production client configuration.
- Attendance contains fixed UTC-5 calculations despite a church timezone column. Active-service lookup returns the first matching window, which can keep a completed first service selected. Treat each service/date independently, retain verified arrival time, and show schedule and arrival in the church timezone.
- Testimonies are church-scoped; app access currently blocks unconnected users. Add explicit public scope without exposing historical church testimonies. Global/church ranking views must return the viewer's rank even outside the first page.
- Haptic preference is persisted without a common feedback implementation. Add a preference-aware, throttled service.
- The user confirmed the one-time reset must retain only their developer account and delete other accounts and app data. Implement the control; do not activate it during development. Server state must survive the purge and prevent replay across devices/reinstalls.

## Planned new files

- `lib/models/primary_feed_mode.dart`, `lib/models/reel.dart`, `lib/models/reel_comment.dart`, `lib/models/reel_upload_session.dart`
- `lib/controllers/reel_feed_controller.dart`, `lib/controllers/reel_playback_coordinator.dart`
- `lib/services/reel_service.dart`, `lib/services/reel_upload_service.dart`, `lib/services/reel_analytics_service.dart`, `lib/services/haptic_service.dart`, `lib/services/feature_flag_service.dart`
- `lib/screens/community/feed_hub_screen.dart`, `lib/screens/reels/reel_grace_screen.dart`, `lib/screens/reels/reel_create_screen.dart`
- `lib/widgets/reels/reel_grace_player.dart`, `lib/widgets/reels/reel_action_bar.dart`, `lib/widgets/reels/reel_caption.dart`, `lib/widgets/reels/reel_comments_sheet.dart`
- `lib/utils/church_time.dart`, `lib/services/media_playback_coordinator.dart`
- `packages/grace_reel_media/pubspec.yaml`, its Dart interface, Android Kotlin media implementation/build/manifest, and iOS Swift implementation/podspec
- `supabase/functions/_shared/r2.ts`, `reel_validation.ts`, `reel_media_validation.ts`, `reel_http.ts`
- `supabase/functions/create-reel-upload/index.ts`, `finalize-reel-upload/index.ts`, `sign-reel-playback/index.ts` (batch authorization + presigned GET), `delete-reel/index.ts`, `cleanup-reel-uploads/index.ts`
- (deferred, not V1) `cloudflare/reel-media-worker/` — only if scale later justifies a gateway in front of private R2; V1 uses presigned GET directly
- `supabase/functions/reset-platform-once/index.ts` and server reset worker/state helpers
- CLI-generated migrations for attendance timezone/service handling, launch/global features, one-time reset, and Reel Grace foundation
- Dart tests for mode switching, playback bounds/lifecycle, optimistic state, cursor pagination, uploads, timezones, service overlap, global scopes and launch controls; SQL security/behavior tests and server-function tests

## Planned existing files to modify

- Navigation/access: `lib/screens/main/main_tabs_screen.dart`, `lib/widgets/app_bottom_menu.dart`, `lib/main.dart`, `lib/access/app_access_context.dart`, `lib/access/app_feature.dart`
- Community/social: `lib/screens/community/community_feed_screen.dart`, `lib/widgets/community_video_player.dart`, `lib/services/moderation_service.dart`, `lib/services/saved_items_service.dart`, `lib/screens/community/saved_items_screen.dart`
- Attendance: `lib/services/attendance_service.dart`, `lib/services/attendance_reminder_plan.dart`, `lib/models/attendance_record.dart`, `lib/screens/attendance/attendance_screen.dart`, church schedule/location configuration and backend finalizer
- Global features: `lib/models/testimony.dart`, `lib/services/testimony_service.dart`, `lib/screens/testimonies/testimonies_screen.dart`, `lib/services/daily_bible_quiz_service.dart`, `lib/widgets/quiz/monthly_quiz_leaderboard_panel.dart`, `lib/services/bible_streak_service.dart`, Bible leaderboard UI and relevant access routes
- Quotes: `lib/widgets/share/shareable_quote_card.dart`, daily-word generation/share code
- Launch polish: `lib/theme/app_theme.dart`, `lib/theme/app_colors.dart`, `lib/screens/grace_rooms/grace_room_chat_screen.dart`, shared input/button widgets and screens with hardcoded conflicting styles
- Settings/developer: `lib/screens/settings/app_settings_screen.dart`, `lib/screens/settings/settings_home_screen.dart`, `lib/screens/developer/developer_console_screen.dart`, `lib/services/developer_service.dart`, beta-only routes and UI
- Church branding: `lib/models/church_model.dart`, `lib/services/church_service.dart`, `lib/screens/settings/church_admin_settings_screen.dart`, `lib/screens/church/church_public_profile_screen.dart`, live-church cards
- Build/config: `pubspec.yaml`, `pubspec.lock`, `android/app/build.gradle`, `android/app/google-services.json`, iOS plugin/Pods configuration, `supabase/config.toml`, `.github/workflows/flutter-ci.yml`

## Reel Grace media architecture — DECIDED (2026-09-18)

This section is the single source of truth for Reel Grace media. It
supersedes any earlier note, the original brief's public playback domain,
and anything in the sections below that contradicts it.

**The R2 bucket `reel-grace-videos` is private and stays private.** No
permanent public object URLs. `reels.graceconnect.love` is NOT attached as
a public R2 custom domain. A secured Cloudflare Worker/gateway in front of
R2 remains a later option if scale demands it, and is explicitly not part
of V1.

Why: a public bucket URL is a capability. Anyone holding the link can fetch
the object forever, with no reference to who is asking. Postgres RLS can be
perfect and a `followers`-only or `church`-only reel would still be
retrievable by URL. Visibility has to be enforced at the point the bytes
are handed out, not only at the point the metadata is read.

### Authority split

- **Supabase** is the authority for authentication, reel visibility,
  followers, church membership, blocks, moderation, likes, comments and
  saves. It stores metadata and social rows only.
- **R2** stores the bytes. It never authorizes anyone.
- **Supabase never carries video bytes.** Devices talk to R2 directly for
  both upload and playback; no proxying through an Edge Function.
- **Firebase Analytics** carries high-volume playback behaviour
  (impressions, watch time, quartiles, completion, skip, replay). These do
  not become Supabase writes.

### Visibility, supported from the first migration

`public`, `followers`, `church`. Not a later addition — the visibility
column, its predicate and its tests land with the initial reel schema, so
there is never a window where everything is effectively public.

### Upload flow

1. Authenticated Flutter calls `create-reel-upload` (Supabase Edge
   Function, user JWT).
2. Server authenticates, checks posting permission/account state, validates
   declared MIME/size/duration, enforces rate limits, generates the reel id
   and object keys itself, and records an upload session.
3. Server returns a **short-lived presigned PUT** (5-10 min).
4. Device uploads bytes **directly to R2**.
5. `finalize-reel-upload` HEADs the objects and validates what R2 can
   actually prove — existence, byte size, content type — then publishes the
   reel row. It does **not** verify duration/codec/faststart; see "Final
   decisions" below for what is client-declared instead.

### Playback flow

1. `get_reel_grace_feed` (Postgres RPC) returns metadata and **object keys
   only** — never a URL. Visibility, blocks, moderation and not-interested
   are filtered here.
2. Flutter calls `sign-reel-playback` (Edge Function) with a small batch of
   reel ids.
3. The function **re-verifies in Supabase that this viewer may see each
   reel** — it does not trust the ids — and returns a **short-lived
   presigned GET** per authorized reel. Unauthorized ids are omitted, not
   errored.
4. The player fetches bytes straight from R2 with that URL.

Signing happens only inside Edge Functions, from environment secrets
(`R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
`R2_BUCKET_NAME`, `R2_S3_ENDPOINT`). No R2 credential is ever shipped in
the Flutter app, committed, logged, or returned to a client.

### Seeking and fast swiping under signed URLs

Signed URLs create two real problems. Both are handled explicitly:

- **Range requests / seeking.** `Range` is not a signed header, so an S3
  presigned GET serves partial content normally. Seeking works, and
  progressive MP4 (`moov` at the front) still matters so playback starts
  before the file is complete.
- **Swipe speed and caching.** A signed URL changes every time it is
  signed, so URL-keyed HTTP caching breaks and per-reel round trips would
  stall swiping. Therefore: sign **in batches** alongside feed pagination
  (one call per page, not per reel), cache each signed URL in memory
  **keyed by reel id** until shortly before expiry, and give signed URLs a
  session-length TTL (target ~30 min) so a normal viewing session never
  re-signs mid-scroll. The on-device media cache is keyed by **reel id**,
  never by URL, so a re-signed URL does not re-download bytes already held.
  A reel whose URL expired mid-session is re-signed lazily on its next
  impression.

### Final decisions (approved 2026-09-19)

**Posters are private too.** A followers-only or church-only reel must not
leak its still image through a public poster bucket. Both objects live in
the private bucket.

**One signing call covers a whole page.** `sign-reel-playback` takes the
page's reel ids and returns **video and poster URLs together**, so a
12-reel page costs one request, not 24. Both are cached by reel id.

**Signed URL lifetime: 30 minutes.** Signed URLs are held **in memory
only**. They are never written into the `reels` table, never persisted to
disk, and never treated as reel data. A URL with roughly **5 minutes or
less remaining is refreshed proactively**, so a long session or a seek
never fails on an expiry that was predictable.

**What `finalize-reel-upload` can and cannot prove.** An R2 HEAD returns
object existence, actual byte size, and the content type the uploader set.
It **cannot** parse the MP4 container, so it cannot verify duration,
codec, dimensions, or whether the `moov` atom is at the front. Treating a
successful HEAD as proof of those would be false confidence.

So, for V1:

- Flutter runs a **controlled upload pipeline** that produces a
  standardized MP4 within Reel Grace's limits before anything is uploaded.
- `finalize-reel-upload` verifies **only what R2 can actually prove**:
  both objects exist, byte size is within limits and consistent with what
  was declared, and content type is acceptable. It rejects on those.
- Duration, dimensions, codec and faststart are stored as
  **client-declared** values and are documented as such in the schema.
  They are used for layout and display, not as a security boundary.
- If trusted server-side media inspection or transcoding is added later,
  that validation can be tightened and these fields promoted to verified.

**Restated constraints that govern implementation:**

- Both video and poster objects stay private.
- Supabase stores **object keys**, never permanent playback URLs.
- All media for a page is batch-signed.
- Supabase is never in the video-byte path.
- Community Feed state is preserved when switching to Reel Grace.
- Feed re-tap and long-press toggle Feed <-> Reel Grace.
- Data Saver initializes and plays **only the current reel**.
- No R2 credential appears anywhere in Flutter.

### What this rules out

- No `PUBLIC_BASE_URL` playback constant in the app.
- No storing playback URLs in the `reels` table — only object keys.
- No "sign once at publish time" long-lived link.
- No public custom domain in V1.

## Proposed database and API

Dedicated `reels`, `reel_likes`, `reel_comments`, `reel_user_feedback`, `reel_upload_sessions`, and retryable media cleanup jobs. Reuse `social_saved_items` for reel saves and existing reporting/blocking/follows. Add explicit indexed visibility and ready/moderation predicates, RLS on exposed tables, safe function search paths and minimal grants. Add `reel_grace` to the existing platform flag system after identifying its live representation.

Feed: `get_reel_grace_feed`, default 12/max 20 rows, stable cursor, accepted-follow filtering, bilateral blocks, not-interested exclusion, no comments and no permanent Realtime subscription. Freeze ranking for a pagination session or use a stable ordering to avoid mutable-counter cursor skips; diversify creators without losing cursor progress. Social RPCs transact counters and return confirmed state for optimistic rollback.

Uploads and playback: see "Reel Grace media architecture — DECIDED" above, which governs. In short — authenticate with Supabase Auth, enforce trusted posting/account access and rate/size/duration/MIME limits, create server-owned paths, sign short-lived exact-header PUT requests, and upload bytes directly to R2. Finalization HEADs both objects and validates what R2 can prove (existence, byte size, content type); MP4 structure is not server-verifiable by HEAD and is client-declared in V1. Promote staging objects to immutable published keys so reusable PUT authorization cannot overwrite published media. Playback is authorization-checked in Supabase and then served by short-lived presigned GET; the feed returns object keys, never URLs. Store secrets only in protected server configuration; delete the supplied credential file after import is verified.

## Architecture conflicts and resolutions

1. RESOLVED — see "Reel Grace media architecture — DECIDED" above. The bucket stays private; authorization is checked in Supabase and then a short-lived presigned GET is issued per viewer. No public bucket URL, no public custom domain in V1.
2. Current+next+previous simultaneously initialized conflicts with the maximum of two players. Keep the previous controller only briefly, then release it before preloading the next. Data Saver initializes only the current reel.
3. Existing Feed re-tap scroll behavior conflicts with the requested toggle. When Reel Grace is enabled, repeat tap/long press toggles within Feed; with the flag off, retain the previous scroll behavior. Returning from another main tab opens Community Feed.
4. Existing church-only testimony access and older church-only social policies conflict with global users. Change explicit scopes and permissions without making old church content public.
5. HEAD size/MIME alone cannot validate duration, codec or fast-start — confirmed, and V1 does not pretend otherwise. A controlled Flutter pipeline produces a standardized MP4; finalize enforces only provable properties; duration/codec/dimensions/faststart are stored as client-declared. Server-side inspection/transcoding can strengthen this later.

## Work sequence and completion gates

1. Attendance timing and multi-service repair.
2. Global testimonies, global/church quiz and Bible-streak ranks.
3. Quote labeling/global wording, haptics, analytics, launch UI/beta removal and church branding.
4. One-time developer reset implementation, never executed on live data during tests.
5. Reel schema/RLS/RPCs (visibility public/followers/church included from the first migration) → R2 private-bucket + secret configuration → presigned upload/finalization → normalization/upload UI → authorization-checked batch presigned playback → navigation → social/moderation → analytics → deletion/cleanup. Design review with the user before any production change.
6. Meaningful Dart/native/server/database tests, Flutter analysis, security/performance advisors, bounded-controller stress checks and HTTP Range/media tests.
7. Signed launch AAB, release notes, exact deployment/test results and remaining physical-device limitations. Do not claim physical device, GA dashboard ingestion or protected Cloudflare deployment without evidence.

The code list may expand when implementation reveals dependent call sites; record additions and results in the final report. Preserve unrelated local files and existing Feed functionality.
