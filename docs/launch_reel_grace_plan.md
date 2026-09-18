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
- `supabase/functions/create-reel-upload/index.ts`, `finalize-reel-upload/index.ts`, `delete-reel/index.ts`, `cleanup-reel-uploads/index.ts`, `reel-media-access/index.ts`
- `cloudflare/reel-media-worker/src/index.ts`, worker configuration and tests (if available Cloudflare permissions permit the protected media gateway)
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

## Proposed database and API

Dedicated `reels`, `reel_likes`, `reel_comments`, `reel_user_feedback`, `reel_upload_sessions`, and retryable media cleanup jobs. Reuse `social_saved_items` for reel saves and existing reporting/blocking/follows. Add explicit indexed visibility and ready/moderation predicates, RLS on exposed tables, safe function search paths and minimal grants. Add `reel_grace` to the existing platform flag system after identifying its live representation.

Feed: `get_reel_grace_feed`, default 12/max 20 rows, stable cursor, accepted-follow filtering, bilateral blocks, not-interested exclusion, no comments and no permanent Realtime subscription. Freeze ranking for a pagination session or use a stable ordering to avoid mutable-counter cursor skips; diversify creators without losing cursor progress. Social RPCs transact counters and return confirmed state for optimistic rollback.

Uploads: authenticate with Supabase Auth, enforce trusted posting/account access, rate/size/duration/MIME limits, create server-owned paths, sign short-lived exact-header PUT requests, upload bytes directly to R2. Finalization HEADs both objects and validates MP4/poster structure. Promote staging objects to immutable published keys so reusable PUT authorization cannot overwrite published media. Store secrets only in protected server configuration; delete the supplied credential file after import is verified.

## Architecture conflicts and resolutions

1. A public R2 bucket URL bypasses followers/church visibility even with perfect Postgres RLS. Protect the custom playback domain with an authenticated Cloudflare media gateway; require the needed Cloudflare permission before claiming protected playback is deployed. Do not silently publish private uploads publicly.
2. Current+next+previous simultaneously initialized conflicts with the maximum of two players. Keep the previous controller only briefly, then release it before preloading the next. Data Saver initializes only the current reel.
3. Existing Feed re-tap scroll behavior conflicts with the requested toggle. When Reel Grace is enabled, repeat tap/long press toggles within Feed; with the flag off, retain the previous scroll behavior. Returning from another main tab opens Community Feed.
4. Existing church-only testimony access and older church-only social policies conflict with global users. Change explicit scopes and permissions without making old church content public.
5. HEAD size/MIME alone cannot validate duration, codec or fast-start. Validate actual media metadata, and never trust the device's declared duration.

## Work sequence and completion gates

1. Attendance timing and multi-service repair.
2. Global testimonies, global/church quiz and Bible-streak ranks.
3. Quote labeling/global wording, haptics, analytics, launch UI/beta removal and church branding.
4. One-time developer reset implementation, never executed on live data during tests.
5. Reel schema/RLS/RPCs → R2 configuration → upload/finalization → normalization/upload UI → playback → navigation → social/moderation → analytics → deletion/cleanup.
6. Meaningful Dart/native/server/database tests, Flutter analysis, security/performance advisors, bounded-controller stress checks and HTTP Range/media tests.
7. Signed launch AAB, release notes, exact deployment/test results and remaining physical-device limitations. Do not claim physical device, GA dashboard ingestion or protected Cloudflare deployment without evidence.

The code list may expand when implementation reveals dependent call sites; record additions and results in the final report. Preserve unrelated local files and existing Feed functionality.
