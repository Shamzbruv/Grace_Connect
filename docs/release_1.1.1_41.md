# Grace Connect 1.1.1 (41)

New accounts receive short contextual guides when they first visit supported
screens. Existing accounts opt in through Settings → Devices & App. Guides respect
roles, loading states, navigation tabs, Feed/Reels modes, modals, keyboards and app
lifecycle. Each account's progress is cached locally and synchronized privately;
restarting advances its generation without deleting learning history. Reduced
motion, screen readers, small screens and larger text are supported.

The optional app-experience survey asks whether Grace Connect helps the member grow
closer to God and connect with others in faith. It becomes eligible after two hours
of accumulated foreground use. Either answer receives the same optional invitation
to leave an honest store review. Unanswered prompts require two additional hours
and 24 hours before repeating, with three automatic invitations maximum. A developer
can queue an additional unanswered reminder under the same time limits. Answered
surveys never repeat automatically. The portal records answers and successful store
link launches; neither Google nor Apple confirms individual review submissions.

Usage upload retries are idempotent per installation, and accounts remain isolated
through rapid sign-in changes. Usage sync occurs approximately every five minutes
and on lifecycle/interaction boundaries, rather than creating a database row for
every second. The iPhone prompt remains disabled until the owner configures a real
App Store listing in the portal. Historical usage from older app builds is unavailable.

Global members and church members now share one canonical quiz for each date.
Preparation checks retained question history across all audiences. Reading-linked
quizzes keep the Daily Word's chapter; existing published quizzes and scores are not
rewritten. Member requests never spend AI capacity. A monthly queue prepares daily
content ahead of time, and normal daily release publishes the prepared records.
Next month is queued on the 25th. One stage runs per worker invocation; failures
back off for six hours, stop after three content failures and can be retried from the
portal. Provider quota exhaustion pauses all pending dates for 24 hours and does not
consume a content retry. The worker resumes automatically after that cooldown.
Provider availability and credits can delay preparation; the system does not claim
to bypass external AI quotas. Daily Word wording now explicitly addresses a global
audience and distinguishes original reflection from a Bible quotation.

The website's App Feedback and Monthly Content panels use the signed-in developer's
permissions. Public clients cannot claim worker leases, generate quizzes, edit
survey counters directly or configure store destinations. The new private worker
tables intentionally have no client RLS policies. The survey's privileged RPCs check
the authenticated actor and developer role explicitly; their security-definer status
is intentional. Tutorial records use own-account RLS. Existing unrelated Supabase
advisories are outside this feature change.

The one-time destructive launch reset remains unused. Its table inventory includes
the new account data; store configuration is preserved. Scheduled preparation pauses
while a reset is running. No test performs the production reset.

Local debug preview: `http://localhost:3000/#/tutorial-preview`. This component preview
uses sample controls, local memory and no account records or analytics. Normal app
navigation remains at `http://localhost:3000/`. The preview route is excluded from
release builds. Physical-device, store-publication and real review submission checks
must not be inferred from automated or browser tests.

Build artifacts and verification evidence are saved in `../releases/1.1.1+41/`.
See `release_notes_1.1.1+41.txt` for the Google Play release text.
