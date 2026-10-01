# Grace Connect 1.1.1 (40)

Reel Grace now accepts likes, comments and saves under the authenticated user's
identity. Database permissions and atomic counters cover existing clients as well
as this release. Profile reels, detail views and message previews respect visibility
and blocking. A public post SELECT policy that bypassed church privacy was removed.

Videos loop with sound, support tap-to-pause and double-tap likes, and expose optional
auto-scroll on long-press. Like animation starts invisible. Following/Discover stay
centered independently of the create button. Playback stops behind dialogs, other
routes and in the background. Only the current and next video preload; the previously
viewed video is retained briefly, then released. Data Saver disables speculative video
loading. Mode changes ignore stale network responses and comment paging handles ties.

Reels and feed posts share to existing conversations as structured references with
recipient-authorized media previews. Photos open at full size with pinch-to-zoom.
Public content can be shared outside the app as an actual image, video or text. Video
export embeds a Grace Connect watermark at bottom-left using Android Media3 or iOS
AVFoundation. The private R2 bucket and signing credentials remain server-side.

The supplied circular GC artwork is used for the home-screen app icon and notification
branding. Android uses a monochrome GC/arrow mark in the status bar and the original
full-color artwork as the large notification image; iOS uses the app icon. The original
opening/splash artwork is preserved. App icon assets are generated for Android, iOS
and desktop/web.

The website developer portal provides sharing-background uploads and management,
maintenance status, queue counts, payment readiness and a one-time launch reset.
Background deletion is audited, queues storage cleanup, and retries only explicitly
removed images; catalogue images never expire merely because they are 30 days old.

The reset requires a super developer, password verification and typed confirmation.
It retains that account, deletes other accounts/churches/content/media, pauses writes,
and resumes interrupted cleanup through a leased cron worker. Its consumed state is
durable and cannot be reset through the public API. Essential app definitions remain.
Production reset remains unused; destructive verification runs only in isolated Postgres.

Payment-to-entitlement linkage already exists and was reviewed. The live gateway
still needs Fygaro configuration; checkout intentionally stays unavailable until both
checkout and webhook verification secrets are present. No live charge was performed.

## Verification

Flutter analysis and regression tests, authenticated rollback-only database tests,
Edge Function tests, media cleanup tests, isolated reset tests and mobile browser
checks accompany this release. The signed AAB verification checks package, version,
SDK levels, upload certificate, bundle structure and SHA-256.

Android exporter compilation and isolated iOS exporter type checking pass. There is
no attached physical device, so a real-device video export and Samsung/iPhone behavior
cannot be claimed as verified. iOS export code is prepared but this is an Android release.

The Supabase advisory review still reports existing mutable-search-path, schema
discoverability, callable SECURITY DEFINER and password-protection notices. This release
does not claim a clean audit of every legacy RPC. New privileged reset/cleanup RPCs deny
anonymous and authenticated direct execution; visibility RPCs enforce caller access.

Build files and verification evidence are saved outside Git in
`../releases/1.1.1+40/`. See `release_notes_1.1.1+40.txt` for Google Play text.
