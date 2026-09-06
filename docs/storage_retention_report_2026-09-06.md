# Storage retention and Disk IO repair — 6 September 2026

Deployed to Grace_Connect (`nimgsgnkcvddomrgkawb`). These are backend changes; **no new AAB is required**. The existing 1.0.31-beta+35 release remains current.

## Findings and repair

The Supabase email concerns **Disk IO budget**, which measures database disk activity and compute throughput. It is distinct from the amount of uploaded media. Both unnecessary database activity and broken content retention were present.

The July Grace Network migration made social posts persistent and allowed null expiry dates. Cleanup deliberately skipped those dates, so five posts older than 30 days survived. A database trigger now caps every community post at 30 days from creation, including requests from existing apps that send `is_persistent=true` and `expires_at=null`. Updates cannot move the creation date or extend that window. Existing posts were backfilled. The app already filters expired posts, so this takes effect when its feed refreshes. Hourly cleanup removes expired database records even when nobody opens the app. Stories retain their existing 24-hour policy and direct messages retain their existing expiry policy.

The old automatic cleanup deleted database records without removing the associated Storage files. Deletion triggers now queue post, story and direct-message media, including video thumbnails. An authenticated Edge Function removes files through the **Storage API**, then acknowledges the queue. It also finds unreferenced uploads older than 30 days to clear historical orphans. Work is limited to 50 files per invocation and retries after failures.

Before selecting and again before deleting a file, the worker checks live content and support/moderation references. Profile, quote-background and support-attachment buckets are excluded. The cleanup queue has RLS enabled and no app-user privileges; new cleanup RPCs are restricted to the service role. The Edge Function checks the existing private cron secret. Unauthenticated invocation returned HTTP 403.

The database's largest tables were job history and HTTP response logs. Job history had no expiry, and these extension-managed tables were not receiving effective routine vacuum/analyze. Successfully completed job logs now retain seven days; failed-job logs retain 30 days. Running jobs are excluded. Historical cleanup used batches of at most 5,000 rows. Standard vacuum/analyze is scheduled daily. After ordinary vacuum, a one-time full compaction of **only the two log tables**, using `SKIP_LOCKED`, reclaimed their accumulated free space. No application table was exclusively locked for compaction.

Grace Room presence previously rewrote every room each minute even when the participant count stayed the same. It now updates only changed counts, preserving the existing two-minute presence window. The quiz stale-attempt job keeps its minute-level check and 26-hour expiry rule but only invokes its Edge Function when a stale attempt exists. A partial heartbeat index supports that check. The media worker likewise skips empty scheduled invocations.

## Measured results

Measurements were taken on the live project during this repair. Database figures are allocated relation/database bytes, not Supabase's complete filesystem usage or Disk IO budget percentage. MB below uses decimal units.

| Item | Before | After |
| --- | ---: | ---: |
| Database size | 294,816,915 bytes / 294.8 MB | 45,485,203 bytes / 45.5 MB |
| Job-history table and indexes | 166,838,272 bytes | 14,573,568 bytes |
| HTTP response table and indexes | 98,033,664 bytes | 876,544 bytes |
| Stored media, all buckets | 97 files / 230,904,307 bytes | 42 files / 29,071,482 bytes |
| Community posts older than 30 days | 5 | 0 |
| Recent community posts | 7 | 7 |
| Recent post media references missing their Storage object | 0 | 0 |

- Removed five expired posts and **55 unused media files**, reclaiming **201,832,825 bytes (201.8 MB)** of object storage.
- Pruned **171,376** old job-history rows. Approximately 29,652 recent rows remained at verification; this count naturally changes as jobs run.
- Preserved all 18 avatar files, 14 quote-background files and four support attachments with identical aggregate byte sizes.
- Retained six community media files, including all five distinct media paths referenced by remaining posts and one recent unreferenced upload still within its grace period.
- Final cleanup queue and eligible orphan list were empty. A repeated worker invocation returned HTTP 200 with zero candidates, deletions or failures.
- The quiz cron's subsequent natural run returned `0 rows`, confirming that an idle check no longer queued an HTTP request. Unchanged presence refresh returned zero writes.

## Deployed components and schedule

| Component | Schedule / behavior |
| --- | --- |
| `20260906125421_restore_retention_and_reduce_background_io.sql` | Retention triggers, safe media queue/RPCs, presence optimization, guarded quiz job and log pruning |
| `20260906125926_schedule_retention_maintenance.sql` | Guarded media invocation with 60-second timeout and routine log maintenance |
| `cleanup-retained-media`, version 1 | Custom cron authentication; 50-file batch; reference checks; Storage API deletion |
| `graceconnect-hourly-content-retention` | Minute 12 of every hour, in addition to existing daily cleanup |
| `graceconnect-media-retention` | Minute 22 of every hour, only when candidates exist |
| `graceconnect-job-history-retention` | Minute 33 of every hour, up to 5,000 old rows |
| `graceconnect-job-history-vacuum` | Daily at 03:43 Jamaica time |
| `graceconnect-http-response-vacuum` | Daily at 03:47 Jamaica time |

Local migration versions match the versions recorded in Supabase. No credentials are stored in the migration or function source; the cron header is read from the existing Vault entry at execution time. No compute upgrade, restart, notification suppression or media recompression was performed.

## Validation

- Eight worker tests passed: deletion/acknowledgement ordering, shared-reference protection, non-mutating dry run, reference-check failure, Storage failure and retry, retry-log failure isolation, protected buckets and empty-batch idempotency.
- Transactional SQL assertions passed against the deployed schema. They verify old-client expiry enforcement, immutable creation dates, future-date handling, old/recent post cleanup, queued media, shared references, path validation, restricted privileges and zero redundant presence writes. All fixtures and test mutations rolled back.
- Authenticated dry run returned 50 candidates and zero mutations. Actual batches deleted 50 and five files, both with HTTP 200 and zero failures. A final invocation made no changes.
- Remaining post media references were checked against Storage; none are missing. Public access to the cleanup endpoint was rejected.
- Both scheduled maintenance commands were executed successfully during this repair. Existing minute-level cron jobs continued to complete successfully.
- The eight worker tests are now part of GitHub CI alongside Flutter analysis and tests.

Run the worker regression tests with Node 22.22.2:

```sh
node --experimental-strip-types --test supabase/tests/retention_media_worker_test.ts
```

For a database regression check, run `supabase/tests/retention_policy_test.sql` as the project administrator. Its transaction always rolls back on success; an assertion failure should also be rolled back before continuing in a persistent SQL session.

## Monitoring and practical limit

These changes remove measured waste and substantially reduce the working database size. They do **not** prove that the Disk IO budget will never be exhausted under future traffic. The supplied management token returned HTTP 403 for infrastructure/metrics endpoints during this session; the connected Supabase integration continued to provide the database and deployment access used for this repair. Consequently, a live budget percentage and before/after throughput series could not be verified.

Keep Supabase's warning enabled. Check Database Health after a full daily usage cycle, particularly during normal church-service traffic. If budget consumption persists after these optimizations, the actual throughput and compute capacity need to be compared before considering a paid compute change.

Sources: [Supabase high Disk IO guidance](https://supabase.com/docs/guides/troubleshooting/exhaust-disk-io), [compute and disk limits](https://supabase.com/docs/guides/platform/compute-and-disk), and [PostgreSQL vacuum behavior](https://www.postgresql.org/docs/current/sql-vacuum.html).
