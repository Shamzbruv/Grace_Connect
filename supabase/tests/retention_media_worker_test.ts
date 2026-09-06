import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cleanupMedia } from '../functions/cleanup-retained-media/worker.ts';
import type { Candidate, CleanupDependencies } from '../functions/cleanup-retained-media/worker.ts';

const file: Candidate = { bucket_id: 'community_media', object_path: 'user/photo.jpg', bytes: 120 };
function fixture(overrides: Partial<CleanupDependencies> = {}) {
  const events: string[] = [];
  const deps: CleanupDependencies = {
    list: async () => [file],
    referenced: async () => { events.push('reference'); return false; },
    remove: async () => { events.push('remove'); },
    acknowledge: async () => { events.push('acknowledge'); },
    failed: async () => { events.push('retry'); },
    ...overrides,
  };
  return { events, deps };
}

test('deletes through Storage before acknowledging the queue', async () => {
  const { deps, events } = fixture();
  const result = await cleanupMedia(deps);
  assert.deepEqual(events, ['reference', 'remove', 'acknowledge']);
  assert.equal(result.removed, 1);
  assert.equal(result.removed_bytes, 120);
});

test('retains a candidate that acquired a live reference after selection', async () => {
  const { deps, events } = fixture({ referenced: async () => true });
  const result = await cleanupMedia(deps);
  assert.deepEqual(events, []);
  assert.equal(result.protected, 1);
});

test('dry run checks references but never deletes or mutates the queue', async () => {
  const { deps, events } = fixture();
  const result = await cleanupMedia(deps, true);
  assert.deepEqual(events, ['reference']);
  assert.equal(result.removed, 0);
  assert.equal(result.dry_run, true);
});

test('an unavailable reference check retains the file for retry', async () => {
  const { deps, events } = fixture({ referenced: async () => { throw new Error('database unavailable'); } });
  const result = await cleanupMedia(deps);
  assert.deepEqual(events, ['retry']);
  assert.equal(result.failed, 1);
  assert.equal(result.ok, false);
});

test('Storage failure is never acknowledged and does not block other files', async () => {
  const { deps, events } = fixture({
    list: async () => [file, { ...file, object_path: 'user/second.jpg' }],
    remove: async (_, path) => { if (path === file.object_path) throw new Error('Storage unavailable'); },
  });
  const result = await cleanupMedia(deps);
  assert.deepEqual(events, ['reference', 'retry', 'reference', 'acknowledge']);
  assert.equal(result.failed, 1);
  assert.equal(result.removed, 1);
});

test('retry-log failure still allows later files to be processed', async () => {
  const { deps } = fixture({
    list: async () => [file, { ...file, object_path: 'user/second.jpg' }],
    remove: async (_, path) => { if (path === file.object_path) throw new Error('Storage unavailable'); },
    failed: async () => { throw new Error('queue unavailable'); },
  });
  const result = await cleanupMedia(deps);
  assert.equal(result.failed, 1);
  assert.equal(result.removed, 1);
});

test('profile, quote and support buckets cannot be deleted', async () => {
  const { deps, events } = fixture({ list: async () => ['avatars', 'quote-backgrounds', 'support_attachments'].map(bucket_id => ({ ...file, bucket_id })) });
  const result = await cleanupMedia(deps);
  assert.deepEqual(events, []);
  assert.equal(result.protected, 3);
});

test('empty queue is an idempotent success', async () => {
  const { deps, events } = fixture({ list: async () => [] });
  const result = await cleanupMedia(deps);
  assert.deepEqual(events, []);
  assert.equal(result.ok, true);
  assert.equal(result.candidates, 0);
});
