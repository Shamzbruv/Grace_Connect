# Grace Connect 2.0.0 (42)

## App changes

- Daily Grace is an Android home-screen widget with 31 verified World English Bible passages, selected by the phone's local calendar day. It reads bundled assets, works without a session or network, supports resizing, and opens the exact displayed passage or Community. Add it under Settings → Devices & App, or through the launcher's Widgets picker. Android controls refresh timing while the device sleeps; the provider also refreshes after clock/timezone changes, reboot, app update and opening the app. No exact alarm, location or overlay permission is needed for the widget.
- The full passage and a prayer reflection remain readable offline in the app. Reading the full chapter uses the existing Bible reader and access checks. The original splash and app icon remain unchanged.
- Saved resolves existing reel bookmarks into current, authorized reel details. Unavailable or blocked reels do not expose stale captions; playback uses the existing single-reel viewer. Poster failures do not hide Saved. Reels still use expiring, memory-only media URLs.
- Settings caches access/version lookups, and tutorial layout changes no longer unmount a visible guide. Tooltip scrolling does not trigger an underlying-page reposition loop.

## Owner portal and backend

Operations → Configure Fygaro securely accepts the payment-button URL, API key ID and write-only secret. Credentials are encrypted in Supabase Vault; only service-role functions can read them. Owner authorization is checked using the verified Auth user. Empty secret fields retain existing credentials. Pausing checkout still allows verified in-flight payment callbacks. Rotating to a new webhook key retains the previous key for seven days.

Fygaro setup still requires the owner to configure the displayed Hook URL and Return URL in the Fygaro payment button and select the matching default webhook credential. Signed JWT payments require a compatible Fygaro plan. A successful settings save does not verify a live payment. Confirm a real checkout and matching webhook before accepting subscriptions. The existing server pricing, payment amount/currency validation, idempotency and church entitlement application remain in use.

- [Fygaro signed payment integration](https://help.fygaro.com/en-us/article/fygaro-links-integration-api-h78p9y/)
- [Fygaro webhook configuration and signatures](https://help.fygaro.com/en-us/article/payment-button-hook-1wkui1k/)

The one-time launch reset now requires verified review-account email addresses and church IDs. Saving this configuration does not reset anything. The selected churches, their members, dependent accounts/records, subscriptions, and referenced/owned media remain; unrelated data is removed. The developer account and essential definitions/integration configuration remain. Existing Auth credentials are never rewritten. The server recomputes dependencies inside the reset-start transaction, freezes app writes, retains foreign-key checks, filters Storage/R2/account cleanup and verifies protected records before completion. R2 cleanup skips retained files using a signed cursor and waits for issued uploads to expire. The action still requires owner reauthentication and an exact confirmation phrase, and cannot be started again after consumption.

No production reset was executed. A production protection-preview transaction was rolled back; phase remained idle. The owner must identify the actual Google Play review logins/church in Operations before the reset becomes available. A seeded demo church alone is not sufficient to identify the review accounts.

## Validation and practical limits

See the release artifact's verification directory for test results, native build, bundle manifest, signature and SHA-256 records. Isolated Postgres tests exercise destructive cleanup using synthetic data only. Browser tests cover both new owner forms at 320, 390 and 1280px. Live checks verify Saved under authenticated RLS, service-only payment configuration, and a rollback-only dependency preview.

Flutter analysis is clean. The full 255-test Flutter suite and three additional saved-item regressions pass, including offline removal and server-error handling. The 33 tutorial regressions, four widget tests, two native date/timezone tests, 20 isolated database tests, 63 distinct Edge Function tests and 42 website tests pass. Some focused suites are included in the full-suite totals.

Supabase's advisor reports expected deny-all RLS notices for the new private service tables. Existing project warnings include mutable search paths, GraphQL schema discovery grants, broad function grants and disabled leaked-password protection; they are not a clean global security audit. New payment/reset APIs are explicitly restricted and do not add anonymous credential access. See [the database linter guidance](https://supabase.com/docs/guides/database/database-linter) and [Auth password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

The repository's existing Supabase Preview job has a legacy migration-baseline failure (`public.users` missing); this release does not suppress that check. Physical Samsung/iPhone certification and a live Fygaro charge are outside the automated checks. This release adds the native widget to Android; an iOS WidgetKit extension is not included.
