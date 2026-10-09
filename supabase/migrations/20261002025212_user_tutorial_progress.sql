-- Existing members opt in; accounts created after this migration get guidance.
-- Serialize the rollout boundary with signups rather than guessing account age.
lock table auth.users in share row exclusive mode;
create table public.user_tutorial_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  generation integer not null default 1 check (generation between 1 and 2147483646),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.user_tutorial_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  generation integer not null check (generation between 1 and 2147483646),
  screen_id text not null check (screen_id ~ '^[a-z][a-z0-9_.]{0,79}$'),
  tutorial_version integer not null default 1 check (tutorial_version between 1 and 100000),
  status text not null check (status in ('completed','dismissed')),
  step_reached integer not null default 0 check (step_reached between 0 and 20),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id,generation,screen_id,tutorial_version)
);
-- The primary key already indexes (user_id, generation); no duplicate index.
alter table public.user_tutorial_settings enable row level security;
alter table public.user_tutorial_progress enable row level security;
revoke all on public.user_tutorial_settings,public.user_tutorial_progress from public,anon,authenticated;
grant select,insert,update on public.user_tutorial_settings,public.user_tutorial_progress to authenticated;
grant all on public.user_tutorial_settings,public.user_tutorial_progress to service_role;
create policy "Read own tutorial settings" on public.user_tutorial_settings for select to authenticated using (user_id=(select auth.uid()));
create policy "Insert own tutorial settings" on public.user_tutorial_settings for insert to authenticated with check (user_id=(select auth.uid()));
create policy "Update own tutorial settings" on public.user_tutorial_settings for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy "Read own tutorial progress" on public.user_tutorial_progress for select to authenticated using (user_id=(select auth.uid()));
create policy "Insert own tutorial progress" on public.user_tutorial_progress for insert to authenticated with check (user_id=(select auth.uid()));
create policy "Update own tutorial progress" on public.user_tutorial_progress for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));

insert into public.user_tutorial_settings(user_id,enabled) select id,false from auth.users;
create function private.initialize_user_tutorials() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  insert into public.user_tutorial_settings(user_id) values(new.id) on conflict do nothing;
  return new;
exception when others then
  -- Optional guidance must never be the reason authentication cannot complete.
  raise warning 'Tutorial initialization deferred (%)',sqlstate;
  return new;
end;
$$;
revoke all on function private.initialize_user_tutorials() from public,anon,authenticated;
create trigger initialize_user_tutorials after insert on auth.users for each row execute function private.initialize_user_tutorials();

create function public.sync_user_tutorials(
  p_generation integer default 1, p_enabled boolean default false,
  p_settings_dirty boolean default false, p_progress jsonb default '[]'::jsonb
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  actor uuid := auth.uid();
  settings public.user_tutorial_settings%rowtype;
  item jsonb;
  result jsonb;
begin
  if actor is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_generation is null or p_generation not between 1 and 2147483646
    or p_enabled is null or p_settings_dirty is null or jsonb_typeof(p_progress) <> 'array'
    or p_progress is null or jsonb_array_length(p_progress)>256
  then raise exception 'Invalid tutorial state' using errcode='22023'; end if;
  -- Missing rows fail closed for legacy accounts. The signup trigger sets true.
  insert into public.user_tutorial_settings(user_id,enabled) values(actor,false) on conflict do nothing;
  select * into strict settings from public.user_tutorial_settings where user_id=actor for update;
  if p_settings_dirty and p_generation >= settings.generation then
    update public.user_tutorial_settings set
      enabled=case when p_generation>generation then p_enabled else enabled and p_enabled end,
      generation=greatest(generation,p_generation),updated_at=now()
      where user_id=actor returning * into settings;
  end if;
  for item in select value from jsonb_array_elements(p_progress) loop
    if (item->>'generation')::integer > settings.generation then
      raise exception 'Progress cannot precede its tutorial generation' using errcode='22023';
    end if;
    insert into public.user_tutorial_progress(user_id,generation,screen_id,tutorial_version,status,step_reached,completed_at)
      values(actor,(item->>'generation')::integer,item->>'screen_id',(item->>'tutorial_version')::integer,
        item->>'status',(item->>'step_reached')::integer,case when item->>'status'='completed' then now() end)
      on conflict(user_id,generation,screen_id,tutorial_version) do update set
        status=case when user_tutorial_progress.status='completed' then 'completed' else excluded.status end,
        step_reached=greatest(user_tutorial_progress.step_reached,excluded.step_reached),
        completed_at=coalesce(user_tutorial_progress.completed_at,excluded.completed_at),updated_at=now();
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('screen_id',screen_id,'generation',generation,
    'tutorial_version',tutorial_version,'status',status,'step_reached',step_reached)),'[]'::jsonb)
    into result from public.user_tutorial_progress where user_id=actor and generation=settings.generation;
  return jsonb_build_object('enabled',settings.enabled,'generation',settings.generation,'progress',result);
end;
$$;
revoke all on function public.sync_user_tutorials(integer,boolean,boolean,jsonb) from public,anon;
grant execute on function public.sync_user_tutorials(integer,boolean,boolean,jsonb) to authenticated;

-- Keep the owner's existing one-time reset inventory/maintenance guards complete.
do $$
declare t text;
begin
  if to_regclass('private.platform_reset_tables') is not null then
    foreach t in array array['user_tutorial_settings','user_tutorial_progress'] loop
      insert into private.platform_reset_tables(table_name,preserve) values(t,false);
      execute format('create trigger platform_reset_write_guard before insert or update or delete on public.%I for each statement execute function private.guard_platform_reset_writes()',t);
    end loop;
  end if;
end;
$$;
