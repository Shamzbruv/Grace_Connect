export type Candidate = { bucket_id: string; object_path: string; bytes: number };
export type CleanupDependencies = {
  list: () => Promise<Candidate[]>;
  referenced: (path: string) => Promise<boolean>;
  remove: (bucket: string, path: string) => Promise<void>;
  acknowledge: (candidate: Candidate) => Promise<void>;
  failed: (candidate: Candidate, reason: string) => Promise<void>;
};

export async function cleanupMedia(deps: CleanupDependencies, dryRun = false) {
  const candidates = await deps.list();
  let removed = 0, removedBytes = 0, protectedFiles = 0, failed = 0;
  for (const candidate of candidates) {
    if (!['community_media', 'chat_media'].includes(candidate.bucket_id)) {
      protectedFiles++;
      continue;
    }
    try {
      // Check again immediately before deletion: content may have changed since
      // the candidate query. Keep shared media and moderation/support evidence.
      if (await deps.referenced(candidate.object_path)) {
        protectedFiles++;
        continue;
      }
      if (dryRun) continue;
      await deps.remove(candidate.bucket_id, candidate.object_path);
      await deps.acknowledge(candidate);
      removed++;
      removedBytes += Number(candidate.bytes) || 0;
    } catch (error) {
      failed++;
      if (!dryRun) {
        try { await deps.failed(candidate, String(error).slice(0, 300)); }
        catch { /* The existing queue/orphan scan will retry; continue this batch. */ }
      }
    }
  }
  return { ok: failed === 0, dry_run: dryRun, candidates: candidates.length,
    removed, removed_bytes: removedBytes, protected: protectedFiles, failed };
}
