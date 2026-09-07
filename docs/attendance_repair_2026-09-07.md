# Grace Connect attendance repair — 1.0.32-beta (36)

## Reported behavior and evidence

On September 6, the reported Samsung Galaxy S21 Ultra started showing a countdown only after the Attendance screen opened. The inspected Sunday School presence claim began at 08:31 Jamaica time, consistent with the screenshot. No completed attendance write reached the server before closeout at 10:45. This establishes missing confirmation; the single stored observation does not prove whether the phone's local countdown ran. Existing history has not been guessed or rewritten.

The calendar also retained only one record per day, so an absence for another service could hide a successful attendance record. It now groups all records by scheduled service date, displays mixed status indicators, and opens the individual service records.

## Implemented changes

- Android background scheduling is a Flutter plugin registered in UI and headless engines. Previously the scheduling channel existed only in MainActivity. Service opening/start checks and dwell completion now run without the Attendance screen.
- Absolute one-time weekly requests preserve the next service deadline. Routine checks leave native geofences registered and preserve their dwell timers. Boot/app-update recovery restores registration, including migration from build 35's opted-in schedule.
- Scheduled observations run independently of the geofence dependency's callback chain. Recovery repairs a failed/cancelled APPEND prerequisite that could otherwise block subsequent events. Workers have a 90-second execution limit, bounded retries, and engine cleanup.
- A pending server presence claim is no longer treated as a completed, permanently cached observation. Later verified inside observations can complete the dwell and atomically acknowledge attendance using the original arrival time.
- Manual on-site sign-in is available throughout the configured check-in window without waiting for the automatic dwell. The server computes early/on-time/late grades. Early remains compatible with existing reports as on_time plus minutes_early.
- The app distinguishes server-confirmed attendance from a check-in queued on the phone. A notification or local cleanup failure after server confirmation does not report the saved attendance as failed.
- Opt-in service reminders prompt before the service (up to 15 minutes, within the church's opening window), at the start, and ten minutes after the start while the service is ongoing. Taps open Attendance for location-verified manual sign-in. High-importance Android notifications request heads-up delivery over other apps.
- Reminders have stable member/service/date/phase IDs and concrete dates. This avoids the notification dependency's weekly matching behavior, which can ignore a future date and revive an already-confirmed day's reminder. At most 24 upcoming notifications are queued over a 15-day horizon. Android independently refreshes this plan daily, even with automatic check-in disabled or location permission revoked. Opening the app also refreshes it. Confirmed occurrences are excluded.
- Setup distinguishes Always access from while-in-use, checks precise location, and shows registration separately from the last actual background event/check result.

## iPhone preparation and limits

The native region callback now has its required Flutter plugin registrant. The permission-handler location build flag is enabled and deployment targets match iOS 15. Region callbacks use a bounded fresh location check and offer manual sign-in. A single region event does not stand in for ten minutes of dwell. Foreground-started on-site observation uses Apple's background location settings and stops when the service/dwell ends.

A headless iOS region engine is destroyed when its callback returns; keeping a Dart timer alive there does not establish reliable background dwell. Fully autonomous terminated-app iPhone dwell is not certified by this repair. Reminders are queued locally over the stated horizon and refreshed by app use; iPhone testing and a production iOS build are still required before shipping. No iPhone artifact is included in this Android release.

## Backend deployment and security

Applied migration: 20260907180124_attendance_arrival_acknowledgement_and_early_checkin. The existing attendance and legacy presence RPC signatures remain compatible. Only the new opt-in observer confirms dwell automatically; the legacy presence RPC stays pending-only because old clients call it from manual screens.

All 27 database behavioral/security assertions passed after deployment in a transaction that rolled back its synthetic fixtures. Coverage includes early/fractional arrival, grace and late boundaries, duplicates, correcting an auto-absence with a legitimate delivered check-in, cross-church denial, repeated versus distinct observations, exiting/re-entering, completing a valid claim after close, and before-midnight check-in for the next service day.

The three public attendance RPCs deny anonymous execution, check authenticated active church membership, and use an empty search_path. The claims table intentionally remains inaccessible directly to members; validated RPCs manage it. Supabase's advisor reports no ERROR findings. Its authenticated-security-definer warnings for these RPCs reflect intentional guarded API access ([advisor guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)); its claims-table no-policy notice reflects intentional direct-access denial ([guidance](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)). Existing unrelated advisor warnings remain outside this attendance change.

## Device acceptance checks

No Android phone was attached during this repair. Validate the Play-installed build on the reported Samsung Galaxy S21 Ultra and another supported Android device: arrive before opening, lock the phone through dwell, arrive after opening, leave during dwell, reboot/update, recover from offline use, tap reminders from another app and from a terminated app, and disable automatic detection while retaining reminders. Verify the persisted service, date, original arrival and grade, not just a local notification.

Android WorkManager and geofencing are subject to OS scheduling and battery restrictions. Inexact reminder alarms may be delayed. A force-stopped app needs reopening. Users control notification permission, channel pop-ups, battery restrictions and Do Not Disturb; the app cannot guarantee an overlay on every device or override those choices. The release uses normal OS notifications, without intrusive overlays, full-screen intents or continuous Android location services.

References: [Android geofencing](https://developer.android.com/develop/sensors-and-location/location/geofencing), [WorkManager timing](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work), [Apple region monitoring](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions).

## Release verification

Final analyzer, Flutter/native test, bundle validation, signature and checksum results are recorded with the AAB in the release directory after the build completes. This report does not claim universal physical-device verification or a bug-free certification.
