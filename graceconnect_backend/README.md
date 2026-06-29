# Legacy Backend Archive

This Express/Mongo service is not part of the active Grace Connect production
stack. The mobile app, developer portal, church onboarding, issue reporting,
media, attendance, and subscription controls use Supabase.

`server.js` exits by default so it cannot be started or deployed by accident.
Set `GRACECONNECT_ENABLE_LEGACY_BACKEND=true` only for local archival review.
