-- Reel Grace foundation: tables, indexes, RLS and the feed RPC.
--
-- Media lives in a PRIVATE Cloudflare R2 bucket. This schema therefore
-- stores object KEYS and never playback URLs: a URL here would outlive any
-- authorization check and hand out followers-only or church-only video to
-- anyone holding the link. Playback URLs are signed per viewer, in memory,
-- by an Edge Function that re-checks visibility. See
-- docs/launch_reel_grace_plan.md.

create table if not exists public.reels (
  id uuid primary key default gen_random_uuid(),
  author_id text not null,
  author_church_id text,
  caption text,
  category text,
  visibility text not null default 'public',
  status text not null default 'uploading',
  moderation_status text not null default 'approved',

  -- Object keys in the private bucket. Never a URL.
  video_object_key text unique,
  poster_object_key text,

  -- Server-verified at finalize (R2 HEAD can prove these).
  mime_type text,
  file_size_bytes bigint,

  -- CLIENT-DECLARED. An R2 HEAD cannot parse the MP4 container, so these
  -- are not server-verified. They drive layout and display only and must
  -- never be used as a security or trust boundary. If server-side media
  -- inspection is added later they can be promoted to verified.
  duration_ms integer,
  width integer,
  height integer,
  aspect_ratio double precision,

  audio_label text default 'Original audio',
  comments_enabled boolean not null default true,
  like_count integer not null default 0,
  comment_count integer not null default 0,
  save_count integer not null default 0,
  share_count integer not null default 0,
  report_count integer not null default 0,
  ranking_score double precision not null default 0,
  created_at timestamptz not null default now(),
  published_at timestamptz,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint reels_visibility_check
    check (visibility in ('public','followers','church')),
  constraint reels_status_check
    check (status in ('uploading','ready','failed','hidden','deleted')),
  constraint reels_moderation_check
    check (moderation_status in ('pending','approved','restricted','removed')),
  constraint reels_duration_check
    check (duration_ms is null or (duration_ms > 0 and duration_ms <= 60000)),
  constraint reels_size_check
    check (file_size_bytes is null or file_size_bytes <= 26214400),
  -- A church-only reel without a church would be visible to nobody and is
  -- almost certainly a bug at the call site rather than an intent.
  constraint reels_church_visibility_check
    check (visibility <> 'church' or author_church_id is not null)
);

create table if not exists public.reel_likes (
  reel_id uuid not null references public.reels(id) on delete cascade,
  user_id text not null,
  created_at timestamptz not null default now(),
  primary key (reel_id, user_id)
);

create table if not exists public.reel_comments (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid not null references public.reels(id) on delete cascade,
  author_id text not null,
  body text not null,
  parent_comment_id uuid references public.reel_comments(id) on delete cascade,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reel_comments_body_check
    check (char_length(btrim(body)) between 1 and 1000),
  constraint reel_comments_status_check
    check (status in ('active','hidden','removed'))
);

create table if not exists public.reel_user_feedback (
  user_id text not null,
  reel_id uuid not null references public.reels(id) on delete cascade,
  feedback_type text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, reel_id, feedback_type),
  constraint reel_feedback_type_check check (feedback_type in ('not_interested'))
);

create table if not exists public.reel_upload_sessions (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid not null references public.reels(id) on delete cascade,
  user_id text not null,
  video_object_key text not null,
  poster_object_key text,
  declared_video_bytes bigint,
  declared_poster_bytes bigint,
  declared_duration_ms integer,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  completed_at timestamptz,
  constraint reel_upload_status_check
    check (status in ('pending','uploaded','completed','expired','failed'))
);

-- Feed ordering indexes. Discover orders by score then recency then id;
-- Following orders by recency then id. Both are covered here so keyset
-- pagination never degrades into a sort of the whole table.
create index if not exists reels_discover_idx
  on public.reels (ranking_score desc, published_at desc, id desc)
  where deleted_at is null and status = 'ready' and moderation_status = 'approved';
create index if not exists reels_following_idx
  on public.reels (published_at desc, id desc)
  where deleted_at is null and status = 'ready' and moderation_status = 'approved';
create index if not exists reels_author_idx on public.reels (author_id, published_at desc);
create index if not exists reels_church_idx on public.reels (author_church_id)
  where visibility = 'church';
create index if not exists reel_likes_user_idx on public.reel_likes (user_id, created_at desc);
create index if not exists reel_comments_reel_idx
  on public.reel_comments (reel_id, created_at desc) where status = 'active';
create index if not exists reel_feedback_user_idx on public.reel_user_feedback (user_id, reel_id);
create index if not exists reel_upload_sessions_user_idx
  on public.reel_upload_sessions (user_id, status, expires_at);

-- ---------------------------------------------------------------------------
-- The single visibility predicate. The feed RPC and the playback signing
-- function both call this, so they can never disagree about who may see a
-- reel -- which is the failure that would hand out private media.
-- ---------------------------------------------------------------------------
create or replace function private.can_view_reel(p_viewer uuid, p_reel_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.reels r
    where r.id = p_reel_id
      and r.deleted_at is null
      and (
        -- The author always sees their own reel, whatever its state.
        r.author_id = p_viewer::text
        or (
          r.status = 'ready'
          and r.moderation_status = 'approved'
          and (
            r.visibility = 'public'
            or (r.visibility = 'followers' and exists (
              select 1 from public.social_follows f
              where f.follower_id = p_viewer::text
                and f.following_id = r.author_id
                and f.status = 'accepted'
            ))
            -- Resolved from p_viewer, NOT from the session. This predicate is
            -- also called by the playback signing function, which runs as the
            -- service role with no end-user session; using the session
            -- identity here would silently deny every church-only reel there.
            or (r.visibility = 'church' and r.author_church_id is not null
                and exists (
                  select 1
                  from public.church_memberships cm
                  join public.churches ch
                    on ch.id = cm.church_id or ch."placeId" = cm.church_id
                  where cm.user_id = p_viewer
                    and cm.membership_status = 'active'
                    and ch.church_status = 'approved'
                    and r.author_church_id in (ch.id::text, ch."placeId"::text)
                ))
          )
          -- A block in either direction hides the reel.
          and not exists (
            select 1 from public.user_blocks b
            where (b.blocker_id = p_viewer::text and b.blocked_user_id = r.author_id)
               or (b.blocker_id = r.author_id and b.blocked_user_id = p_viewer::text)
          )
        )
      )
  );
$$;
revoke all on function private.can_view_reel(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.reels enable row level security;
alter table public.reel_likes enable row level security;
alter table public.reel_comments enable row level security;
alter table public.reel_user_feedback enable row level security;
alter table public.reel_upload_sessions enable row level security;

drop policy if exists "Viewers read permitted reels" on public.reels;
create policy "Viewers read permitted reels" on public.reels for select to authenticated
  using (private.can_view_reel((select auth.uid()), id));

drop policy if exists "Authors create their own reels" on public.reels;
create policy "Authors create their own reels" on public.reels for insert to authenticated
  with check (author_id = (select auth.uid())::text);

-- Both USING and WITH CHECK: without WITH CHECK an author could reassign a
-- reel to another user.
drop policy if exists "Authors update their own reels" on public.reels;
create policy "Authors update their own reels" on public.reels for update to authenticated
  using (author_id = (select auth.uid())::text)
  with check (author_id = (select auth.uid())::text);

drop policy if exists "Authors delete their own reels" on public.reels;
create policy "Authors delete their own reels" on public.reels for delete to authenticated
  using (author_id = (select auth.uid())::text);

drop policy if exists "Viewers read likes on permitted reels" on public.reel_likes;
create policy "Viewers read likes on permitted reels" on public.reel_likes for select to authenticated
  using (private.can_view_reel((select auth.uid()), reel_id));

drop policy if exists "Members manage their own reel likes" on public.reel_likes;
create policy "Members manage their own reel likes" on public.reel_likes for insert to authenticated
  with check (user_id = (select auth.uid())::text
              and private.can_view_reel((select auth.uid()), reel_id));

drop policy if exists "Members remove their own reel likes" on public.reel_likes;
create policy "Members remove their own reel likes" on public.reel_likes for delete to authenticated
  using (user_id = (select auth.uid())::text);

drop policy if exists "Viewers read comments on permitted reels" on public.reel_comments;
create policy "Viewers read comments on permitted reels" on public.reel_comments for select to authenticated
  using (status = 'active' and private.can_view_reel((select auth.uid()), reel_id));

drop policy if exists "Members comment on permitted reels" on public.reel_comments;
create policy "Members comment on permitted reels" on public.reel_comments for insert to authenticated
  with check (
    author_id = (select auth.uid())::text
    and private.can_view_reel((select auth.uid()), reel_id)
    and exists (select 1 from public.reels r where r.id = reel_id and r.comments_enabled)
  );

drop policy if exists "Authors edit their own reel comments" on public.reel_comments;
create policy "Authors edit their own reel comments" on public.reel_comments for update to authenticated
  using (author_id = (select auth.uid())::text)
  with check (author_id = (select auth.uid())::text);

-- A reel's author may also remove comments on their own reel.
drop policy if exists "Comment or reel author deletes comments" on public.reel_comments;
create policy "Comment or reel author deletes comments" on public.reel_comments for delete to authenticated
  using (
    author_id = (select auth.uid())::text
    or exists (select 1 from public.reels r
               where r.id = reel_id and r.author_id = (select auth.uid())::text)
  );

drop policy if exists "Members manage their own reel feedback" on public.reel_user_feedback;
create policy "Members manage their own reel feedback" on public.reel_user_feedback for all to authenticated
  using (user_id = (select auth.uid())::text)
  with check (user_id = (select auth.uid())::text);

-- Upload sessions are server-managed; a client may read only its own and
-- never write one, so a device cannot mint itself an upload authorization.
drop policy if exists "Members read their own upload sessions" on public.reel_upload_sessions;
create policy "Members read their own upload sessions" on public.reel_upload_sessions for select to authenticated
  using (user_id = (select auth.uid())::text);

-- ---------------------------------------------------------------------------
-- Feed RPC. Returns object keys, never URLs. Keyset pagination on a stable
-- ordering so a changing counter cannot make a page skip or repeat a reel.
-- ---------------------------------------------------------------------------
create or replace function public.get_reel_grace_feed(
  p_mode text default 'discover',
  p_cursor jsonb default null,
  p_limit integer default 12
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  mode text := lower(coalesce(nullif(trim(p_mode), ''), 'discover'));
  capped integer := greatest(1, least(coalesce(p_limit, 12), 20));
  cursor_score double precision := nullif(p_cursor->>'ranking_score','')::double precision;
  cursor_published timestamptz := nullif(p_cursor->>'published_at','')::timestamptz;
  cursor_id uuid := nullif(p_cursor->>'id','')::uuid;
  items jsonb;
begin
  if actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;
  if mode not in ('discover','following') then
    raise exception 'Unknown feed mode.' using errcode = '22023';
  end if;

  with visible as (
    select r.*
    from public.reels r
    where r.deleted_at is null
      and r.status = 'ready'
      and r.moderation_status = 'approved'
      and r.published_at is not null
      and private.can_view_reel(actor, r.id)
      -- Not interested removes a reel from future pages.
      and not exists (
        select 1 from public.reel_user_feedback fb
        where fb.user_id = actor::text and fb.reel_id = r.id
          and fb.feedback_type = 'not_interested'
      )
      and (
        mode = 'discover'
        or exists (
          select 1 from public.social_follows f
          where f.follower_id = actor::text
            and f.following_id = r.author_id
            and f.status = 'accepted'
        )
      )
  ), paged as (
    select * from visible v
    where case
      when mode = 'following' then
        cursor_published is null
        or (v.published_at, v.id) < (cursor_published, cursor_id)
      else
        cursor_score is null
        or (v.ranking_score, v.published_at, v.id)
             < (cursor_score, cursor_published, cursor_id)
    end
    order by case when mode = 'following' then null else v.ranking_score end desc nulls last,
             v.published_at desc, v.id desc
    limit capped
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'author_id', p.author_id,
    'author_name', coalesce(nullif(btrim(u."displayName"), ''),
                            nullif(btrim(u."fullName"), ''), 'Member'),
    'author_avatar_url', u."photoUrl",
    'author_church_id', p.author_church_id,
    'caption', p.caption,
    'category', p.category,
    'visibility', p.visibility,
    -- Keys only. The client exchanges these for short-lived signed URLs.
    'video_object_key', p.video_object_key,
    'poster_object_key', p.poster_object_key,
    'duration_ms', p.duration_ms,
    'aspect_ratio', p.aspect_ratio,
    'audio_label', p.audio_label,
    'comments_enabled', p.comments_enabled,
    'published_at', p.published_at,
    'ranking_score', p.ranking_score,
    'like_count', p.like_count,
    'comment_count', p.comment_count,
    'save_count', p.save_count,
    'viewer_liked', exists (select 1 from public.reel_likes l
                            where l.reel_id = p.id and l.user_id = actor::text),
    'viewer_saved', exists (select 1 from public.social_saved_items s
                            where s.entity_type = 'reel' and s.entity_id = p.id::text
                              and s.user_id = actor::text),
    'viewer_follows_author', exists (select 1 from public.social_follows f
                                     where f.follower_id = actor::text
                                       and f.following_id = p.author_id
                                       and f.status = 'accepted')
  ) order by case when mode = 'following' then null else p.ranking_score end desc nulls last,
              p.published_at desc, p.id desc), '[]'::jsonb)
  into items
  from paged p
  left join public.users u on u.uid = p.author_id;

  return jsonb_build_object(
    'mode', mode,
    'reels', items,
    'next_cursor', case when jsonb_array_length(items) < capped then null else
      jsonb_build_object(
        'ranking_score', items->-1->>'ranking_score',
        'published_at', items->-1->>'published_at',
        'id', items->-1->>'id')
    end
  );
end;
$$;
revoke all on function public.get_reel_grace_feed(text, jsonb, integer) from public, anon;
grant execute on function public.get_reel_grace_feed(text, jsonb, integer) to authenticated;

-- RLS already denies anon every row (all policies are TO authenticated), but
-- leaving anon with table-level SELECT still exposes the shape of these
-- tables through PostgREST/GraphQL introspection -- including upload
-- sessions, which carry object keys. Revoke it outright.
revoke all on public.reels from anon;
revoke all on public.reel_likes from anon;
revoke all on public.reel_comments from anon;
revoke all on public.reel_user_feedback from anon;
revoke all on public.reel_upload_sessions from anon;

-- Upload sessions are written only by Edge Functions using the service role.
revoke insert, update, delete on public.reel_upload_sessions from authenticated;

-- Foreign keys that the feed and cleanup paths actually traverse:
-- reel_user_feedback.reel_id backs the feed's not-interested exclusion (the
-- existing composite index leads with user_id, so it does not cover this),
-- reel_upload_sessions.reel_id backs orphan cleanup, and
-- reel_comments.parent_comment_id backs threaded replies.
create index if not exists reel_user_feedback_reel_idx on public.reel_user_feedback (reel_id);
create index if not exists reel_upload_sessions_reel_idx on public.reel_upload_sessions (reel_id);
create index if not exists reel_comments_parent_idx on public.reel_comments (parent_comment_id)
  where parent_comment_id is not null;
