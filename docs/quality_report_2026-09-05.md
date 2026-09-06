# Grace Connect 1.0.31-beta (35): release audit

This release addresses the reported password recovery, Grace Rooms, Daily Word, chapter quiz, attendance, notification, and light-mode defects. Verification combines regression tests, production configuration checks, isolated synthetic-account checks, and mobile/desktop website checks. It is not a guarantee that every device or workflow is bug-free.

## Changes and evidence

| Area | Finding and correction | Verification |
| --- | --- | --- |
| Password recovery | Synced the already-deployed mailer change that sends recovery tokens to the website's password form. Aligned the repository's recovery template with that flow and clarified the app's instructions. | Production Auth configuration and mailer use recovery wording and `type=recovery`. A synthetic account redeemed a recovery token, changed its password, rejected token replay and the old password, and signed in with the new password. No email was sent to a real member. |
| Grace Rooms | The message table was absent from the production realtime publication. Added it with an idempotent migration. Apply the current session to Realtime before subscribing. The chat now retains its subscription across rebuilds, refreshes after resume/send, reconciles missed updates every 15 seconds, preserves newer events against an older pending fetch, and follows new messages when the reader is at the bottom. | Publication membership verified with SQL. Live two-account INSERT delivery passed after explicitly applying the receiver's session and awaiting database-listener readiness. |
| Daily Word Bible links | Published references contain nonbreaking hyphens, which the parser rejected. Normalize Unicode dash and spacing variants before parsing. | Tests cover the live reference typography, verse ranges, aliases, chapter references, and invalid chapters. |
| Chapter quizzes | The status function omitted study metadata, so the app could not direct readers to the source chapter. Return the quiz mode and chapter, show a reading prompt, and open that chapter before starting a chapter-study quiz. Reading does not start the question timer. | Deployed `get-daily-bible-quiz-status` version 19 with the existing live shared dependency preserved. A signed-in live request returned `available: true`, `quiz_mode: chapter_study`, and `study_chapter_key: psalms 99`. |
| Auto-attendance | Production history showed no automatic attendance or presence claims in the inspected 30-day period. Refresh jobs previously stopped after their first run, and asynchronous registration errors were ignored. Jobs now repeat weekly, retain the nearest occurrence of each time slot, and await registration so failures can retry. | Dwell and readiness regression coverage; Android release compilation. Server finalization RPC and cron are present, and recent scheduled finalizations succeeded. |
| Attendance setup | The switch could imply readiness despite changed permissions or other blockers. Diagnostics now report precise/background location, location services, church configuration, enabled schedule, battery restriction, and the last native event. Expired background sessions are refreshed. | Readiness tests include approximate-only location. No real attendance rows, schedules, church coordinates, or church radii were altered. |
| Small attendance geofences | The configured church radius is 50 m. Additional 150 m geofences wake a fresh GPS check; attendance still uses the configured church boundary and dwell requirement. Time in the wider area does not count as on-site dwell. | Code review of the separate wake path and existing dwell protections. On-site device validation remains necessary. |
| Notification destinations | Inbox and OS notifications used different routing, some message IDs were interpreted as room IDs, and generic fallbacks could open unrelated screens. Use one resolver, load the authorized parent of a message, show individual event/announcement content, and display unavailable content explicitly. Attendance initialization now preserves the common tap handler. | Route regressions cover messages, rooms, roles, events, announcements, and supported/rejected deep links. Invitation routing preserves its explicit room destination. Old quiz/quote links no longer silently substitute today's content. |
| Light mode | Pale accent text and global app-bar overrides reduced contrast; some cards and message indicators assumed one theme. Use readable theme colors, preserve explicit Bible app-bar foreground colors, and repair Bible tab actions. | Both-theme contrast checks and a widget regression for the Bible app bar. Reviewed Grace Rooms, Inbox/message bubbles, Bible reader, study cards, and quiz controls. |

Supabase documents the publication requirement and the readiness gap between a channel joining and its database listener becoming active in its [Realtime troubleshooting guide](https://supabase.com/docs/guides/troubleshooting/realtime-postgres-changes-troubleshooting). Android recommends larger geofences for reliable transition delivery in its [geofencing guide](https://developer.android.com/develop/sensors-and-location/location/geofencing).

## Website and deployment synchronization

- Both repositories were fetched and fast-forwarded before editing.
- Landing repository: `Shamzbruv/Grace_Connect_Landing`, branch `main`, commit `571e128636dac1a788fc2fbbcf2d08adc275a0a7`.
- Railway's latest production deployment reported `SUCCESS` for that same commit. The live domain is `https://graceconnect.love`.
- Website tests: 23 passed under Node 22.
- Live browser checks: 16 passed, covering eight routes at mobile and desktop widths. Checked home, member signup, church registration, subscription request, password reset, Auth callback, developer access, and account deletion. No page JavaScript errors or horizontal overflow were observed. Unauthenticated developer access correctly redirected to sign-in.
- Recovery testing also verified that an ordinary account could not use the developer-only temporary-password endpoint.
- Synthetic users, sessions, rooms, and messages used for verification were removed. Access tokens are not included in source or release artifacts.

## Final validation

The full Flutter suite completed with 149 passing checks and two assertion failures. After correcting the stale wording expectations, the affected suites and route/theme regressions were rerun: all 48 passed. The full suite contains 151 checks; no unresolved test failure remains. Final `flutter analyze --no-pub` passed with no issues. The signed release build completed successfully.

- Artifact: `grace-connect-1.0.31-beta+35.aab` (63613724 bytes).
- Package `love.graceconnect`; version name `1.0.31-beta`; version code `35`; minimum SDK 26; target SDK 36; debugging disabled.
- Google bundletool 1.18.3 validation and ZIP integrity passed. All three bundled arm64 libraries have 16 KB-compatible ELF segment alignment.
- `jarsigner` verified the bundle signature. The existing self-signed Android upload certificate matches SHA-256 `57:0B:F1:0C:B5:BE:B4:35:CD:1F:AF:75:CC:17:73:78:75:FD:9E:30:F1:D4:31:69:D9:24:77:A0:40:62:F3:B2`.
- Bundle SHA-256: `ce2618ec0ad9b31f107da12100abb65760ae0609f4f033a58ca25173d78167f0`.
- The packaged manifest includes background location, excludes a location foreground service, and contains the configured Maps key. No key value is included in this report.
- Live Bible provider check returned Psalm 99 with all nine verses and the requested starting verse.
- Release notes and verification evidence accompany the AAB in `../releases/1.0.31-beta+35/`.

## Remaining verification limits

- No Android device was connected. Physical arrival, reboot/Doze behavior, battery restrictions, and notification taps from a terminated app need validation on a Play-installed build. Android does not guarantee immediate geofence delivery, and a force-stopped app must be reopened.
- For the on-site check, enable Auto-Attendance, grant precise and background location, clear any displayed battery restriction, and enter the saved church boundary during a scheduled service. Remain for the configured dwell period, then inspect the attendance record and the last native event in settings. Repeat with the app closed and after a reboot. Confirm the church pin and boundary cover the actual grounds.
- Browser checks did not create real registrations, subscriptions, payments, or send member emails. Financial/provider flows and every privileged administration action were not exercised end to end.
- The Supabase security advisor reported no ERROR-level findings but did return existing warnings: 16 mutable function search paths, 159 GraphQL table-exposure warnings, 338 security-definer execution warnings, and disabled leaked-password protection; there were also 15 informational RLS-without-policy findings. These need a separate authorization-by-authorization review before changing existing RPC grants. This release does not claim a clean security certification.
