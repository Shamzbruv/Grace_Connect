alter table public.direct_messages add column if not exists shared_content jsonb;
alter table public.direct_messages add constraint direct_messages_shared_content_check check (
  shared_content is null or (
    jsonb_typeof(shared_content) = 'object'
    and shared_content ?& array['kind','id']
    and shared_content - 'kind' - 'id' = '{}'::jsonb
    and shared_content->>'kind' in ('reel','post')
    and shared_content->>'id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  )
);
comment on column public.direct_messages.shared_content is
  'Only content kind and id. Recipients resolve metadata under their own RLS; no signed URLs or private content snapshots.';
