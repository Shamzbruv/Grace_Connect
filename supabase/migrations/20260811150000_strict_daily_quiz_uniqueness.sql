-- Strict Daily Bible Quiz uniqueness is on by default. A canonical fact is
-- anchored to Scripture chapter(s) plus normalized answer tokens, so changing
-- the wording or verse range cannot make a repeated fact appear new.

create table if not exists public.daily_content_generation_settings (
  id boolean primary key default true check (id),
  quiz_guarantee_unique boolean not null default true,
  relaxed_quiz_history_days integer not null default 60
    check (relaxed_quiz_history_days between 1 and 3650),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

insert into public.daily_content_generation_settings (
  id,
  quiz_guarantee_unique,
  relaxed_quiz_history_days
) values (true, true, 60)
on conflict (id) do nothing;

alter table public.daily_content_generation_settings enable row level security;
revoke all on table public.daily_content_generation_settings from public, anon, authenticated;

create or replace function public.canonical_quiz_answer_key(p_answer text)
returns text
language sql
immutable
strict
set search_path = public
as $$
  with normalized as (
    select trim(regexp_replace(lower(p_answer), '[^a-z0-9]+', ' ', 'g')) as value
  ), meaningful as (
    select distinct token
    from normalized,
      regexp_split_to_table(value, '[[:space:]]+') as token
    where token <> ''
      and token <> all(array[
        'a', 'an', 'and', 'at', 'by', 'for', 'from', 'in', 'of', 'on',
        'the', 'to', 'with'
      ]::text[])
  ), all_tokens as (
    select distinct token
    from normalized,
      regexp_split_to_table(value, '[[:space:]]+') as token
    where token <> ''
  )
  select coalesce(
    (select string_agg(token, ' ' order by token) from meaningful),
    (select string_agg(token, ' ' order by token) from all_tokens),
    ''
  );
$$;

create or replace function public.canonical_quiz_fact_keys(
  p_scripture_references jsonb,
  p_correct_answer text
)
returns text[]
language plpgsql
immutable
set search_path = public
as $$
declare
  v_item jsonb;
  v_reference text;
  v_match text[];
  v_book text;
  v_chapter text;
  v_answer text := public.canonical_quiz_answer_key(coalesce(p_correct_answer, ''));
  v_answer_tokens text[];
  v_reference_key text;
  v_token text;
  v_keys text[] := array[]::text[];
begin
  if v_answer = '' or jsonb_typeof(p_scripture_references) <> 'array' then
    return v_keys;
  end if;
  v_answer_tokens := regexp_split_to_array(v_answer, '[[:space:]]+');

  for v_item in
    select value from jsonb_array_elements(p_scripture_references)
  loop
    v_book := null;
    v_chapter := null;
    if jsonb_typeof(v_item) = 'string' then
      v_reference := lower(trim(v_item #>> '{}'));
      v_reference := regexp_replace(v_reference, '[[:space:]]+', ' ', 'g');
      v_match := regexp_match(
        v_reference,
        '^([123]?[[:space:]]*[a-z]+([[:space:]]+[a-z]+)*)[[:space:]]+([0-9]{1,3}):[0-9]{1,3}'
      );
      if v_match is not null then
        v_book := v_match[1];
        v_chapter := v_match[3];
      end if;
    elsif jsonb_typeof(v_item) = 'object' then
      -- Early beta/demo rows stored {book, chapter, verse} objects. Preserve
      -- that retained history by canonicalizing its chapter anchor as well.
      v_book := lower(trim(coalesce(v_item->>'book', '')));
      v_chapter := trim(coalesce(v_item->>'chapter', ''));
    end if;
    if nullif(v_book, '') is null
        or v_chapter !~ '^[0-9]{1,3}$'
        or v_chapter::integer < 1 then
      continue;
    end if;
    v_book := trim(regexp_replace(v_book, '[[:space:]]+', ' ', 'g'));
    v_book := case v_book
      when 'psalm' then 'psalms'
      when 'psalms' then 'psalms'
      when 'song of songs' then 'song of solomon'
      when 'canticles' then 'song of solomon'
      when 'revelations' then 'revelation'
      else v_book
    end;
    v_reference_key := v_book || ' ' || (v_chapter::integer)::text || '::';
    v_keys := array_append(v_keys, v_reference_key || v_answer);
    if v_answer = any(array[
      'christ jesus', 'christ jesus lord', 'jesus', 'jesus lord'
    ]::text[]) then
      v_keys := array_append(v_keys, v_reference_key || 'person:jesus');
    end if;
    if cardinality(v_answer_tokens) > 1 then
      foreach v_token in array v_answer_tokens
      loop
        if v_token <> all(array[
          'apostle', 'brother', 'christ', 'city', 'daughter', 'disciple',
          'disciples', 'god', 'israel', 'jesus', 'king', 'lord', 'man',
          'people', 'priest', 'prophet', 'queen', 'sister', 'son', 'woman'
        ]::text[]) then
          v_keys := array_append(v_keys, v_reference_key || v_token);
        end if;
      end loop;
    end if;
  end loop;

  return coalesce(
    (select array_agg(distinct key order by key) from unnest(v_keys) as key),
    array[]::text[]
  );
end;
$$;

revoke all on function public.canonical_quiz_answer_key(text)
  from public, anon, authenticated;
revoke all on function public.canonical_quiz_fact_keys(jsonb, text)
  from public, anon, authenticated;
grant execute on function public.canonical_quiz_answer_key(text) to service_role;
grant execute on function public.canonical_quiz_fact_keys(jsonb, text) to service_role;

alter table public.daily_bible_quiz_questions
  add column if not exists fact_keys text[] not null default array[]::text[];

update public.daily_bible_quiz_questions
set fact_keys = public.canonical_quiz_fact_keys(
  scripture_references,
  correct_answer
)
where fact_keys = array[]::text[];

alter table public.daily_bible_quiz_questions
  drop constraint if exists daily_bible_quiz_questions_fact_keys_check;
alter table public.daily_bible_quiz_questions
  add constraint daily_bible_quiz_questions_fact_keys_check
  check (cardinality(fact_keys) > 0) not valid;
-- NOT VALID deliberately preserves any malformed legacy row so deployment is
-- safe. PostgreSQL still enforces the check for every new/replaced question;
-- strict generation below fails closed if relevant retained history could not
-- be canonicalized, instead of silently ignoring that legacy row.

create index if not exists daily_bible_quiz_questions_fact_keys_idx
  on public.daily_bible_quiz_questions using gin (fact_keys);

-- Status is mutable because an administrator may need to withdraw a released
-- quiz. Keep an independent release marker so that unpublishing or archiving
-- never erases facts that members may already have seen. Drafts and scheduled
-- quizzes that have never been published remain unmarked and do not
-- unnecessarily consume permanent history.
alter table public.daily_bible_quizzes
  add column if not exists first_published_at timestamptz;

update public.daily_bible_quizzes q
set first_published_at = coalesce(q.available_at, q.updated_at, q.created_at, now())
where q.first_published_at is null
  and (
    q.status in ('published', 'archived')
    or exists (
      select 1
      from public.quiz_attempts qa
      where qa.quiz_id = q.id
    )
  );

create index if not exists daily_bible_quizzes_retained_history_idx
  on public.daily_bible_quizzes (church_id, quiz_date desc)
  where status = 'scheduled' or first_published_at is not null;

create or replace function public.get_blocked_daily_bible_quiz_fact_keys(
  p_church_id text,
  p_quiz_date date
)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_strict boolean := true;
  v_relaxed_days integer := 60;
  v_keys text[];
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if nullif(trim(coalesce(p_church_id, '')), '') is null
      or p_quiz_date is null then
    raise exception 'Church and quiz date are required';
  end if;

  select
    coalesce(quiz_guarantee_unique, true),
    greatest(1, least(coalesce(relaxed_quiz_history_days, 60), 3650))
  into v_strict, v_relaxed_days
  from public.daily_content_generation_settings
  where id = true;

  if exists (
    select 1
    from public.daily_bible_quiz_questions qq
    join public.daily_bible_quizzes q on q.id = qq.quiz_id
    where (q.status = 'scheduled' or q.first_published_at is not null)
      and cardinality(qq.fact_keys) = 0
      and q.church_id in (p_church_id, 'grace_connect_global')
      and (
        v_strict
        or (
          q.quiz_date >= p_quiz_date - v_relaxed_days
          and q.quiz_date <= p_quiz_date
        )
      )
  ) then
    raise exception 'Quiz uniqueness cannot verify malformed retained quiz history';
  end if;

  select coalesce(array_agg(distinct fact_key order by fact_key), array[]::text[])
    into v_keys
  from public.daily_bible_quiz_questions qq
  join public.daily_bible_quizzes q on q.id = qq.quiz_id
  cross join lateral unnest(qq.fact_keys) as fact_key
  where (q.status = 'scheduled' or q.first_published_at is not null)
    and q.church_id in (p_church_id, 'grace_connect_global')
    and (
      v_strict
      or (
        q.quiz_date >= p_quiz_date - v_relaxed_days
        and q.quiz_date <= p_quiz_date
      )
    );
  return v_keys;
end;
$$;

revoke all on function public.get_blocked_daily_bible_quiz_fact_keys(text, date)
  from public, anon, authenticated;
grant execute on function public.get_blocked_daily_bible_quiz_fact_keys(text, date)
  to service_role;

create or replace function public.daily_bible_quiz_has_fact_conflict(
  p_quiz_id uuid,
  p_fact_keys text[]
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_quiz public.daily_bible_quizzes;
  v_strict boolean := true;
  v_relaxed_days integer := 60;
begin
  select * into v_quiz
  from public.daily_bible_quizzes
  where id = p_quiz_id;
  if not found then
    raise exception 'Quiz not found';
  end if;

  select
    coalesce(quiz_guarantee_unique, true),
    greatest(1, least(coalesce(relaxed_quiz_history_days, 60), 3650))
    into v_strict, v_relaxed_days
  from public.daily_content_generation_settings
  where id = true;

  if exists (
    select 1
    from public.daily_bible_quiz_questions qq
    join public.daily_bible_quizzes q on q.id = qq.quiz_id
    where q.id <> p_quiz_id
      and (q.status = 'scheduled' or q.first_published_at is not null)
      and cardinality(qq.fact_keys) = 0
      and q.church_id in (v_quiz.church_id, 'grace_connect_global')
      and (
        v_strict
        or (
          q.quiz_date >= v_quiz.quiz_date - v_relaxed_days
          and q.quiz_date <= v_quiz.quiz_date
        )
      )
  ) then
    raise exception 'Strict quiz uniqueness cannot verify malformed retained quiz history';
  end if;

  return exists (
    select 1
    from public.daily_bible_quiz_questions qq
    join public.daily_bible_quizzes q on q.id = qq.quiz_id
    where q.id <> p_quiz_id
      and (q.status = 'scheduled' or q.first_published_at is not null)
      and qq.fact_keys && p_fact_keys
      and q.church_id in (v_quiz.church_id, 'grace_connect_global')
      and (
        v_strict
        or (
          q.quiz_date >= v_quiz.quiz_date - v_relaxed_days
          and q.quiz_date <= v_quiz.quiz_date
        )
      )
  );
end;
$$;

revoke all on function public.daily_bible_quiz_has_fact_conflict(uuid, text[])
  from public, anon, authenticated;
grant execute on function public.daily_bible_quiz_has_fact_conflict(uuid, text[])
  to service_role;

create or replace function public.lock_daily_bible_quiz_audience(
  p_church_id text
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_church_id text := nullif(trim(coalesce(p_church_id, '')), '');
  v_global_gate bigint := hashtextextended(
    'daily-bible-quiz:global-audience-gate',
    0
  );
begin
  if v_church_id is null then
    raise exception 'Quiz audience is required';
  end if;

  if v_church_id = 'grace_connect_global' then
    -- Global history is visible to every audience, so a global mutation takes
    -- the exclusive gate while ordinary churches take the shared form below.
    perform pg_advisory_xact_lock(v_global_gate);
  else
    -- Shared global gate lets unrelated churches proceed concurrently. The
    -- church-specific lock serializes every date for this one audience, making
    -- the all-history check safe across prepare/refresh races.
    perform pg_advisory_xact_lock_shared(v_global_gate);
    perform pg_advisory_xact_lock(
      hashtextextended('daily-bible-quiz:audience:' || v_church_id, 0)
    );
  end if;
end;
$$;

revoke all on function public.lock_daily_bible_quiz_audience(text)
  from public, anon, authenticated;
grant execute on function public.lock_daily_bible_quiz_audience(text)
  to service_role;

-- Legacy admin RLS used to allow direct question edits and direct publication.
-- Make quiz content server-owned; admins retain read access and publish through
-- the guarded RPC below. Service-role generation remains the only writer.
revoke insert, update, delete on table public.daily_bible_quiz_questions
  from anon, authenticated;
revoke insert, update, delete on table public.daily_bible_quizzes
  from anon, authenticated;
grant insert, update, delete on table public.daily_bible_quiz_questions
  to service_role;
grant insert, update, delete on table public.daily_bible_quizzes
  to service_role;

drop policy if exists "Admins manage quiz questions for own church"
  on public.daily_bible_quiz_questions;
drop policy if exists "Admins manage own church quizzes"
  on public.daily_bible_quizzes;

-- Play 1.0.27 publishes by directly updating only the status column. Preserve
-- that narrow path during rollout so deploying the database first does not
-- strand existing admins. The BEFORE trigger below still validates every
-- publication and records the immutable release marker. No question or other
-- quiz-column mutation is restored.
grant update (status) on table public.daily_bible_quizzes to authenticated;

drop policy if exists "Admins update own church quiz publication status"
  on public.daily_bible_quizzes;
create policy "Admins update own church quiz publication status"
  on public.daily_bible_quizzes
  for update
  to authenticated
  using (
    church_id = public.get_church_id()
    and (
      public.has_any_role(array[
        'Pastor', 'Senior Pastor', 'Church Admin', 'Admin', 'Administrator'
      ])
      or public.has_app_privilege('manageDailyBibleQuiz')
    )
  )
  with check (
    church_id = public.get_church_id()
    and (
      public.has_any_role(array[
        'Pastor', 'Senior Pastor', 'Church Admin', 'Admin', 'Administrator'
      ])
      or public.has_app_privilege('manageDailyBibleQuiz')
    )
  );

create or replace function public.enforce_daily_bible_quiz_publish_uniqueness()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fact_keys text[];
begin
  if tg_op = 'UPDATE' then
    -- The marker is derived from the first publication transition and is
    -- immutable thereafter. A status withdrawal/archive (or an accidental
    -- direct marker update by a trusted backend) must not erase history.
    new.first_published_at := old.first_published_at;
  elsif new.status <> 'published' then
    new.first_published_at := null;
  end if;

  if new.status <> 'published'
      or (tg_op = 'UPDATE' and old.status = 'published') then
    return new;
  end if;

  new.first_published_at := coalesce(
    case when tg_op = 'UPDATE' then old.first_published_at end,
    now()
  );

  -- This is the final invariant, independent of which client or RPC initiates
  -- the status transition. It shares the audience lock with replacement.
  perform public.lock_daily_bible_quiz_audience(new.church_id);

  if (
    select count(*)
    from public.daily_bible_quiz_questions
    where quiz_id = new.id
  ) <> 5 then
    raise exception 'Exactly five quiz questions are required before publication';
  end if;

  if exists (
    select 1
    from public.daily_bible_quiz_questions
    where quiz_id = new.id
      and (
        cardinality(fact_keys) = 0
        or fact_keys is distinct from public.canonical_quiz_fact_keys(
          scripture_references,
          correct_answer
        )
      )
  ) then
    raise exception 'Quiz publication blocked because a canonical Scripture fact could not be verified';
  end if;

  select array_agg(key)
    into v_fact_keys
  from (
    select unnest(fact_keys) as key
    from public.daily_bible_quiz_questions
    where quiz_id = new.id
  ) keys;

  if cardinality(v_fact_keys) <> (
    select count(distinct key)::integer from unnest(v_fact_keys) as key
  ) then
    raise exception 'The quiz contains repeated canonical Scripture facts';
  end if;
  if public.daily_bible_quiz_has_fact_conflict(new.id, v_fact_keys) then
    raise exception 'Quiz publication rejected because a canonical fact was already used';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_daily_bible_quiz_publish_uniqueness()
  from public, anon, authenticated;

drop trigger if exists trg_enforce_daily_bible_quiz_publish_uniqueness
  on public.daily_bible_quizzes;
create trigger trg_enforce_daily_bible_quiz_publish_uniqueness
  before insert or update of status, first_published_at on public.daily_bible_quizzes
  for each row execute function public.enforce_daily_bible_quiz_publish_uniqueness();

create or replace function public.admin_set_daily_bible_quiz_published(
  p_quiz_id uuid,
  p_published boolean
)
returns public.daily_bible_quizzes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quiz public.daily_bible_quizzes;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not (
    public.has_any_role(array[
      'Pastor', 'Senior Pastor', 'Church Admin', 'Admin', 'Administrator'
    ])
    or public.has_app_privilege('manageDailyBibleQuiz')
  ) then
    raise exception 'Quiz management permission is required';
  end if;

  select * into v_quiz
  from public.daily_bible_quizzes
  where id = p_quiz_id
    and church_id = public.get_church_id()
  for update;
  if not found then
    raise exception 'Quiz not found for this church';
  end if;

  update public.daily_bible_quizzes
     set status = case when coalesce(p_published, false)
       then 'published'
       else 'unpublished'
     end
   where id = p_quiz_id
  returning * into v_quiz;
  return v_quiz;
end;
$$;

revoke all on function public.admin_set_daily_bible_quiz_published(uuid, boolean)
  from public, anon;
grant execute on function public.admin_set_daily_bible_quiz_published(uuid, boolean)
  to authenticated, service_role;

create or replace function public.replace_daily_bible_quiz_questions(
  p_quiz_id uuid,
  p_questions jsonb,
  p_generation_source text,
  p_generation_status text,
  p_validation_notes text default null,
  p_status text default null
)
returns public.daily_bible_quizzes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quiz public.daily_bible_quizzes;
  v_question jsonb;
  v_question_keys text[];
  v_incoming_keys text[] := array[]::text[];
  v_count integer := 0;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if jsonb_typeof(p_questions) <> 'array'
      or jsonb_array_length(p_questions) <> 5 then
    raise exception 'Exactly five quiz questions are required';
  end if;

  select * into v_quiz
  from public.daily_bible_quizzes
  where id = p_quiz_id
  for update;
  if not found then raise exception 'Quiz not found'; end if;

  if v_quiz.first_published_at is not null then
    raise exception 'A quiz that has already been published cannot have its questions replaced';
  end if;

  perform public.lock_daily_bible_quiz_audience(v_quiz.church_id);

  if exists (
    select 1 from public.quiz_attempts where quiz_id = p_quiz_id
  ) then
    raise exception 'A quiz with member attempts cannot be regenerated';
  end if;
  if p_status = 'scheduled'
     and (v_quiz.status = 'published' or v_quiz.available_at <= now()) then
    raise exception 'The quiz release window has started and can no longer be refreshed';
  end if;

  for v_question in select value from jsonb_array_elements(p_questions)
  loop
    v_question_keys := public.canonical_quiz_fact_keys(
      coalesce(v_question->'scripture_references', '[]'::jsonb),
      v_question->>'correct_answer'
    );
    if cardinality(v_question_keys) = 0 then
      raise exception 'Every question requires a canonical Scripture fact key';
    end if;
    v_incoming_keys := array_cat(v_incoming_keys, v_question_keys);
  end loop;

  if cardinality(v_incoming_keys) <> (
    select count(distinct key)::integer from unnest(v_incoming_keys) as key
  ) then
    raise exception 'The quiz contains repeated canonical Scripture facts';
  end if;
  if public.daily_bible_quiz_has_fact_conflict(p_quiz_id, v_incoming_keys) then
    raise exception 'Strict quiz uniqueness rejected a fact used by retained scheduled or published content';
  end if;

  delete from public.daily_bible_quiz_questions where quiz_id = p_quiz_id;
  for v_question in select value from jsonb_array_elements(p_questions)
  loop
    v_count := v_count + 1;
    v_question_keys := public.canonical_quiz_fact_keys(
      coalesce(v_question->'scripture_references', '[]'::jsonb),
      v_question->>'correct_answer'
    );
    insert into public.daily_bible_quiz_questions (
      quiz_id, question_order, question_text,
      option_a, option_b, option_c, option_d,
      correct_option_index, correct_answer, explanation,
      scripture_references, category, difficulty, question_hash, fact_keys
    ) values (
      p_quiz_id,
      v_count,
      trim(v_question->>'question'),
      trim(v_question->'options'->>0),
      trim(v_question->'options'->>1),
      trim(v_question->'options'->>2),
      trim(v_question->'options'->>3),
      (v_question->>'correct_option_index')::integer,
      trim(v_question->>'correct_answer'),
      trim(v_question->>'explanation'),
      coalesce(v_question->'scripture_references', '[]'::jsonb),
      nullif(trim(v_question->>'category'), ''),
      nullif(trim(v_question->>'difficulty'), ''),
      trim(v_question->>'question_hash'),
      v_question_keys
    );
  end loop;

  update public.daily_bible_quizzes
     set generation_source = p_generation_source,
         generation_status = p_generation_status,
         validation_notes = p_validation_notes,
         status = coalesce(p_status, status),
         notification_sent_at = case
           when coalesce(p_status, status) = 'scheduled' then null
           else notification_sent_at
         end,
         notification_claimed_at = case
           when coalesce(p_status, status) = 'scheduled' then null
           else notification_claimed_at
         end,
         updated_at = now()
   where id = p_quiz_id
  returning * into v_quiz;
  return v_quiz;
end;
$$;

revoke all on function public.replace_daily_bible_quiz_questions(
  uuid, jsonb, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.replace_daily_bible_quiz_questions(
  uuid, jsonb, text, text, text, text
) to service_role;

create or replace function public.validate_daily_bible_quiz_uniqueness(
  p_quiz_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quiz public.daily_bible_quizzes;
  v_fact_keys text[];
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;

  select * into v_quiz
  from public.daily_bible_quizzes
  where id = p_quiz_id
  for update;
  if not found then raise exception 'Quiz not found'; end if;

  perform public.lock_daily_bible_quiz_audience(v_quiz.church_id);

  if (select count(*) from public.daily_bible_quiz_questions where quiz_id = p_quiz_id) <> 5 then
    raise exception 'Exactly five quiz questions are required before release';
  end if;
  if exists (
    select 1
    from public.daily_bible_quiz_questions
    where quiz_id = p_quiz_id
      and cardinality(fact_keys) = 0
  ) then
    raise exception 'Quiz release blocked because a canonical Scripture fact could not be verified';
  end if;
  select array_agg(key)
    into v_fact_keys
  from (
    select unnest(fact_keys) as key
    from public.daily_bible_quiz_questions
    where quiz_id = p_quiz_id
  ) keys;
  if cardinality(v_fact_keys) <> (
    select count(distinct key)::integer from unnest(v_fact_keys) as key
  ) then
    raise exception 'The quiz contains repeated canonical Scripture facts';
  end if;
  if public.daily_bible_quiz_has_fact_conflict(p_quiz_id, v_fact_keys) then
    raise exception 'Strict quiz uniqueness rejected this release because a canonical fact was already used';
  end if;
  return true;
end;
$$;

revoke all on function public.validate_daily_bible_quiz_uniqueness(uuid)
  from public, anon, authenticated;
grant execute on function public.validate_daily_bible_quiz_uniqueness(uuid)
  to service_role;

create or replace function public.publish_daily_bible_quiz_if_unique(
  p_quiz_id uuid
)
returns public.daily_bible_quizzes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quiz public.daily_bible_quizzes;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;

  select * into v_quiz
  from public.daily_bible_quizzes
  where id = p_quiz_id
  for update;
  if not found then raise exception 'Quiz not found'; end if;
  if v_quiz.status = 'published' then return v_quiz; end if;

  perform public.validate_daily_bible_quiz_uniqueness(p_quiz_id);

  update public.daily_bible_quizzes
  set status = 'published', updated_at = now()
  where id = p_quiz_id
  returning * into v_quiz;
  return v_quiz;
end;
$$;

revoke all on function public.publish_daily_bible_quiz_if_unique(uuid)
  from public, anon, authenticated;
grant execute on function public.publish_daily_bible_quiz_if_unique(uuid)
  to service_role;

create or replace function public.developer_update_quiz_uniqueness_settings(
  p_guarantee_unique boolean,
  p_relaxed_history_days integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dev public.developer_accounts;
  v_settings public.daily_content_generation_settings;
begin
  select * into v_dev
  from public.require_developer(array[
    'super_developer',
    'support_developer',
    'content_moderator',
    'security_admin'
  ]);
  if p_guarantee_unique is null then
    raise exception 'A uniqueness selection is required';
  end if;
  if p_relaxed_history_days is null
      or p_relaxed_history_days not between 1 and 3650 then
    raise exception 'Relaxed history days must be between 1 and 3650';
  end if;

  update public.daily_content_generation_settings
     set quiz_guarantee_unique = p_guarantee_unique,
         relaxed_quiz_history_days = p_relaxed_history_days,
         updated_at = now(),
         updated_by = auth.uid()
   where id = true
  returning * into v_settings;

  perform public.log_developer_action(
    'quiz_uniqueness_settings_updated',
    'daily_content_generation_settings',
    'singleton',
    jsonb_build_object(
      'guarantee_unique', v_settings.quiz_guarantee_unique,
      'relaxed_history_days', v_settings.relaxed_quiz_history_days
    )
  );
  return jsonb_build_object(
    'guarantee_unique', v_settings.quiz_guarantee_unique,
    'relaxed_history_days', v_settings.relaxed_quiz_history_days,
    'strict_history_scope', 'all_retained_published_and_scheduled',
    'updated_at', v_settings.updated_at
  );
end;
$$;

revoke all on function public.developer_update_quiz_uniqueness_settings(boolean, integer)
  from public, anon;
grant execute on function public.developer_update_quiz_uniqueness_settings(boolean, integer)
  to authenticated;

-- Sanitized schedule preview plus the explicit strict-uniqueness control.
create or replace function public.developer_list_scheduled_content(
  p_days integer default 14
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dev public.developer_accounts;
  v_today date := timezone('America/Jamaica', now())::date;
  v_days integer := greatest(1, least(coalesce(p_days, 14), 60));
  v_settings public.daily_content_generation_settings;
begin
  select * into v_dev from public.require_developer(null);
  select * into v_settings
  from public.daily_content_generation_settings
  where id = true;

  return jsonb_build_object(
    'jamaica_date', v_today,
    'quiz_uniqueness_settings', jsonb_build_object(
      'guarantee_unique', coalesce(v_settings.quiz_guarantee_unique, true),
      'relaxed_history_days', coalesce(v_settings.relaxed_quiz_history_days, 60),
      'strict_history_scope', 'all_retained_published_and_scheduled',
      'updated_at', v_settings.updated_at
    ),
    'can_manage_quiz_uniqueness_settings', v_dev.developer_role = any(array[
      'super_developer',
      'support_developer',
      'content_moderator',
      'security_admin'
    ]),
    'daily_words', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'publish_date', d.publish_date,
        'release_at', (d.publish_date::timestamp + time '05:00') at time zone 'America/Jamaica',
        'title', d.title,
        'message', d.message,
        'scripture_reference', d.scripture_reference,
        'topic', d.topic,
        'source', d.source,
        'status', d.status
      ) order by d.publish_date)
      from public.daily_motivations d
      where d.publish_date between v_today and v_today + v_days
        and d.status = 'scheduled'
        and ((d.publish_date::timestamp + time '05:00') at time zone 'America/Jamaica') > now()
    ), '[]'::jsonb),
    'quizzes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id,
        'scope', case
          when q.church_id = 'grace_connect_global' then 'global'
          else 'church'
        end,
        'church_name', case
          when q.church_id = 'grace_connect_global' then 'Grace Connect Global'
          else coalesce((
            select coalesce(nullif(c.display_name, ''), nullif(c.name, ''))
            from public.churches c
            where c.id = q.church_id or c."placeId" = q.church_id
            limit 1
          ), 'Church')
        end,
        'quiz_date', q.quiz_date,
        'release_at', q.available_at,
        'status', q.status,
        'source', q.generation_source,
        'generation_status', q.generation_status,
        'questions', coalesce((
          select jsonb_agg(jsonb_build_object(
            'order', qq.question_order,
            'question', qq.question_text,
            'options', jsonb_build_array(qq.option_a, qq.option_b, qq.option_c, qq.option_d),
            'category', qq.category,
            'difficulty', qq.difficulty
          ) order by qq.question_order)
          from public.daily_bible_quiz_questions qq
          where qq.quiz_id = q.id
        ), '[]'::jsonb)
      ) order by q.quiz_date, q.church_id)
      from public.daily_bible_quizzes q
      where q.quiz_date between v_today and v_today + v_days
        and q.status = 'scheduled'
        and q.available_at > now()
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.developer_list_scheduled_content(integer)
  to authenticated;
