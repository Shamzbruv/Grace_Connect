import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';
import { cleanupMedia } from './worker.ts';

Deno.serve(async (request: Request) => {
  const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json' },
  });
  if (request.method !== 'POST') return reply({ error: 'POST required.' }, 405);
  const secret = Deno.env.get('DAILY_QUIZ_CRON_SECRET');
  if (!secret || request.headers.get('x-cron-secret') !== secret) {
    return reply({ error: 'Forbidden.' }, 403);
  }
  const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  try {
    const body = await request.json().catch(() => ({}));
    const result = await cleanupMedia({
      list: async () => {
        const { data, error } = await client.rpc('list_retention_media_candidates', { batch_size: 50 });
        if (error) throw error;
        return data ?? [];
      },
      referenced: async (path) => {
        const { data, error } = await client.rpc('retention_media_is_referenced', { target_path: path });
        if (error) throw error;
        return data !== false; // Fail closed if the authorization check is ambiguous.
      },
      remove: async (bucket, path) => {
        const { error } = await client.storage.from(bucket).remove([path]);
        if (error) throw error;
      },
      acknowledge: async ({ bucket_id, object_path }) => {
        const { error } = await client.from('media_cleanup_queue').delete()
          .eq('bucket_id', bucket_id).eq('object_path', object_path);
        if (error) throw error;
      },
      failed: async ({ bucket_id, object_path }, reason) => {
        const { error } = await client.from('media_cleanup_queue').upsert({
          bucket_id, object_path, last_error: reason,
        }, { onConflict: 'bucket_id,object_path' });
        if (error) throw error;
      },
    }, body.dry_run === true);
    return reply(result, result.ok ? 200 : 500);
  } catch (_) {
    return reply({ error: 'Retention cleanup could not complete; pending files will retry.' }, 500);
  }
});
