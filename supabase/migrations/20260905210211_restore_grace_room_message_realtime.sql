-- Streams need table publication in addition to the existing SELECT RLS policy.
-- Participant identities remain excluded; only authorized message rows stream.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'grace_room_messages'
  ) then
    alter publication supabase_realtime add table public.grace_room_messages;
  end if;
end
$$;
