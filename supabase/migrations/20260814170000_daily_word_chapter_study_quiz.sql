-- Give every Daily Word a permanently unique Bible chapter and make Monday,
-- Wednesday, and Saturday quizzes study that exact chapter. Scheduled content
-- may be rewritten, but its release slot and chapter contract stay unchanged.

create table if not exists public.bible_book_catalog (
  book_key text primary key,
  display_name text not null unique,
  chapter_count integer not null check (chapter_count > 0)
);

insert into public.bible_book_catalog (book_key, display_name, chapter_count) values
  ('genesis', 'Genesis', 50), ('exodus', 'Exodus', 40),
  ('leviticus', 'Leviticus', 27), ('numbers', 'Numbers', 36),
  ('deuteronomy', 'Deuteronomy', 34), ('joshua', 'Joshua', 24),
  ('judges', 'Judges', 21), ('ruth', 'Ruth', 4),
  ('1 samuel', '1 Samuel', 31), ('2 samuel', '2 Samuel', 24),
  ('1 kings', '1 Kings', 22), ('2 kings', '2 Kings', 25),
  ('1 chronicles', '1 Chronicles', 29), ('2 chronicles', '2 Chronicles', 36),
  ('ezra', 'Ezra', 10), ('nehemiah', 'Nehemiah', 13),
  ('esther', 'Esther', 10), ('job', 'Job', 42),
  ('psalms', 'Psalms', 150), ('proverbs', 'Proverbs', 31),
  ('ecclesiastes', 'Ecclesiastes', 12),
  ('song of solomon', 'Song of Solomon', 8),
  ('isaiah', 'Isaiah', 66), ('jeremiah', 'Jeremiah', 52),
  ('lamentations', 'Lamentations', 5), ('ezekiel', 'Ezekiel', 48),
  ('daniel', 'Daniel', 12), ('hosea', 'Hosea', 14), ('joel', 'Joel', 3),
  ('amos', 'Amos', 9), ('obadiah', 'Obadiah', 1), ('jonah', 'Jonah', 4),
  ('micah', 'Micah', 7), ('nahum', 'Nahum', 3),
  ('habakkuk', 'Habakkuk', 3), ('zephaniah', 'Zephaniah', 3),
  ('haggai', 'Haggai', 2), ('zechariah', 'Zechariah', 14),
  ('malachi', 'Malachi', 4), ('matthew', 'Matthew', 28),
  ('mark', 'Mark', 16), ('luke', 'Luke', 24), ('john', 'John', 21),
  ('acts', 'Acts', 28), ('romans', 'Romans', 16),
  ('1 corinthians', '1 Corinthians', 16),
  ('2 corinthians', '2 Corinthians', 13),
  ('galatians', 'Galatians', 6), ('ephesians', 'Ephesians', 6),
  ('philippians', 'Philippians', 4), ('colossians', 'Colossians', 4),
  ('1 thessalonians', '1 Thessalonians', 5),
  ('2 thessalonians', '2 Thessalonians', 3),
  ('1 timothy', '1 Timothy', 6), ('2 timothy', '2 Timothy', 4),
  ('titus', 'Titus', 3), ('philemon', 'Philemon', 1),
  ('hebrews', 'Hebrews', 13), ('james', 'James', 5),
  ('1 peter', '1 Peter', 5), ('2 peter', '2 Peter', 3),
  ('1 john', '1 John', 5), ('2 john', '2 John', 1),
  ('3 john', '3 John', 1), ('jude', 'Jude', 1),
  ('revelation', 'Revelation', 22)
on conflict (book_key) do update
set display_name = excluded.display_name,
    chapter_count = excluded.chapter_count;

alter table public.bible_book_catalog enable row level security;
revoke all on table public.bible_book_catalog from public, anon, authenticated;
grant select on table public.bible_book_catalog to service_role;

create or replace function public.canonical_bible_chapter_key(p_reference text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_match text[];
  v_book text;
  v_chapter integer;
  v_max integer;
begin
  v_match := regexp_match(
    trim(coalesce(p_reference, '')),
    '^([123]?[[:space:]]*[A-Za-z]+([[:space:]]+[A-Za-z]+)*)[[:space:]]+([0-9]{1,3})(:[0-9]{1,3})?',
    'i'
  );
  if v_match is null then return null; end if;
  v_book := lower(trim(regexp_replace(v_match[1], '[[:space:]]+', ' ', 'g')));
  v_book := case v_book
    when 'psalm' then 'psalms'
    when 'song of songs' then 'song of solomon'
    when 'canticles' then 'song of solomon'
    when 'revelations' then 'revelation'
    else v_book
  end;
  v_chapter := v_match[3]::integer;
  select chapter_count into v_max
  from public.bible_book_catalog
  where book_key = v_book;
  if v_max is null or v_chapter < 1 or v_chapter > v_max then return null; end if;
  return v_book || ' ' || v_chapter::text;
end;
$$;

create or replace function public.daily_word_content_fingerprint(
  p_title text,
  p_message text
)
returns text
language sql
immutable
set search_path = public
as $$
  select md5(
    trim(regexp_replace(lower(coalesce(p_title, '') || ' ' || coalesce(p_message, '')), '[^a-z0-9]+', ' ', 'g'))
  );
$$;

revoke all on function public.canonical_bible_chapter_key(text)
  from public, anon, authenticated;
revoke all on function public.daily_word_content_fingerprint(text, text)
  from public, anon, authenticated;
grant execute on function public.canonical_bible_chapter_key(text) to service_role;
grant execute on function public.canonical_bible_chapter_key(text) to authenticated;
grant execute on function public.daily_word_content_fingerprint(text, text) to service_role;

alter table public.daily_motivations
  add column if not exists scripture_chapter_key text,
  add column if not exists has_study_quiz boolean not null default false,
  add column if not exists content_fingerprint text,
  add column if not exists generation_version integer not null default 1;

update public.daily_motivations
set scripture_chapter_key = public.canonical_bible_chapter_key(scripture_reference),
    content_fingerprint = public.daily_word_content_fingerprint(title, message)
where scripture_chapter_key is null
   or content_fingerprint is null;

alter table public.daily_motivations
  drop constraint if exists daily_motivations_canonical_chapter_check;
alter table public.daily_motivations
  add constraint daily_motivations_canonical_chapter_check
  check (
    scripture_chapter_key is not null
    and scripture_chapter_key = public.canonical_bible_chapter_key(scripture_reference)
  ) not valid;

alter table public.daily_motivations
  drop constraint if exists daily_motivations_study_day_check;
alter table public.daily_motivations
  add constraint daily_motivations_study_day_check
  check (
    not has_study_quiz
    or extract(isodow from publish_date)::integer in (1, 3, 6)
  ) not valid;

-- Keep every generated wording, including versions replaced before release.
-- Without this immutable ledger, repeatedly pressing Replace could eventually
-- cycle back to a discarded scheduled Daily Word because that text no longer
-- existed in daily_motivations.
create table if not exists public.daily_word_content_history (
  content_fingerprint text primary key,
  daily_motivation_id uuid not null,
  title text not null,
  message text not null,
  first_seen_at timestamptz not null default now()
);

insert into public.daily_word_content_history (
  content_fingerprint,
  daily_motivation_id,
  title,
  message,
  first_seen_at
)
select distinct on (d.content_fingerprint)
  d.content_fingerprint,
  d.id,
  d.title,
  d.message,
  coalesce(d.generated_at, d.created_at, now())
from public.daily_motivations d
where d.content_fingerprint is not null
order by d.content_fingerprint, d.publish_date, d.created_at, d.id
on conflict (content_fingerprint) do nothing;

alter table public.daily_word_content_history enable row level security;
revoke all on table public.daily_word_content_history
  from public, anon, authenticated;
grant select, insert on table public.daily_word_content_history to service_role;

create table if not exists public.daily_word_chapter_history (
  chapter_key text primary key,
  book_name text not null,
  chapter_number integer not null check (chapter_number > 0),
  first_daily_motivation_id uuid not null,
  first_publish_date date not null,
  reserved_at timestamptz not null default now(),
  first_published_at timestamptz
);

insert into public.daily_word_chapter_history (
  chapter_key,
  book_name,
  chapter_number,
  first_daily_motivation_id,
  first_publish_date,
  reserved_at,
  first_published_at
)
select distinct on (d.scripture_chapter_key)
  d.scripture_chapter_key,
  b.display_name,
  substring(d.scripture_chapter_key from ' ([0-9]+)$')::integer,
  d.id,
  d.publish_date,
  coalesce(d.generated_at, d.created_at, now()),
  case when d.is_published or d.status = 'published'
    then coalesce(d.published_at, d.created_at, now())
    else null
  end
from public.daily_motivations d
join public.bible_book_catalog b
  on b.book_key = regexp_replace(d.scripture_chapter_key, ' [0-9]+$', '')
where d.scripture_chapter_key is not null
order by d.scripture_chapter_key, d.publish_date, d.created_at, d.id
on conflict (chapter_key) do nothing;

alter table public.daily_word_chapter_history enable row level security;
revoke all on table public.daily_word_chapter_history from public, anon, authenticated;
grant select, insert, update on table public.daily_word_chapter_history to service_role;

create or replace function public.enforce_daily_word_unique_content()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
  v_existing uuid;
begin
  v_key := public.canonical_bible_chapter_key(new.scripture_reference);
  if v_key is null then
    raise exception 'Daily Word requires a valid canonical Bible verse reference';
  end if;
  if new.scripture_chapter_key is not null and new.scripture_chapter_key <> v_key then
    raise exception 'Daily Word verse must belong to its reserved chapter';
  end if;
  new.scripture_chapter_key := v_key;
  new.content_fingerprint := public.daily_word_content_fingerprint(new.title, new.message);
  if new.publish_date >= date '2026-08-15' then
    new.has_study_quiz := extract(isodow from new.publish_date)::integer in (1, 3, 6);
  end if;

  if new.has_study_quiz
      and extract(isodow from new.publish_date)::integer not in (1, 3, 6) then
    raise exception 'Chapter-study quizzes are scheduled only for Monday, Wednesday, and Saturday';
  end if;
  if tg_op = 'UPDATE'
      and old.has_study_quiz
      and old.status in ('scheduled', 'published')
      and old.scripture_chapter_key is distinct from new.scripture_chapter_key then
    raise exception 'A linked Daily Word chapter cannot change after scheduling';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('daily-word:chapter-history', 0));
  select first_daily_motivation_id into v_existing
  from public.daily_word_chapter_history
  where chapter_key = v_key;
  if v_existing is not null
      and v_existing <> new.id
      and not (
        tg_op = 'UPDATE'
        and old.scripture_chapter_key = v_key
      ) then
    raise exception 'That Bible chapter has already been used for a Daily Word';
  end if;

  if exists (
    select 1
    from public.daily_motivations d
    where d.id <> new.id
      and d.content_fingerprint = new.content_fingerprint
  ) then
    raise exception 'That Daily Word wording has already been used';
  end if;
  if exists (
    select 1
    from public.daily_word_content_history h
    where h.content_fingerprint = new.content_fingerprint
      and not (
        tg_op = 'UPDATE'
        and old.content_fingerprint = new.content_fingerprint
      )
  ) then
    raise exception 'That Daily Word wording was used by an earlier generated version';
  end if;
  return new;
end;
$$;

create or replace function public.reserve_daily_word_chapter_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_book_key text := regexp_replace(new.scripture_chapter_key, ' [0-9]+$', '');
  v_book_name text;
  v_chapter integer := substring(new.scripture_chapter_key from ' ([0-9]+)$')::integer;
begin
  select display_name into v_book_name
  from public.bible_book_catalog
  where book_key = v_book_key;
  if v_book_name is null then raise exception 'Unknown Daily Word Bible chapter'; end if;

  insert into public.daily_word_content_history (
    content_fingerprint,
    daily_motivation_id,
    title,
    message,
    first_seen_at
  ) values (
    new.content_fingerprint,
    new.id,
    new.title,
    new.message,
    now()
  ) on conflict (content_fingerprint) do nothing;

  insert into public.daily_word_chapter_history (
    chapter_key,
    book_name,
    chapter_number,
    first_daily_motivation_id,
    first_publish_date,
    reserved_at,
    first_published_at
  ) values (
    new.scripture_chapter_key,
    v_book_name,
    v_chapter,
    new.id,
    new.publish_date,
    now(),
    case when new.is_published or new.status = 'published' then now() else null end
  )
  on conflict (chapter_key) do update
  set first_published_at = coalesce(
    public.daily_word_chapter_history.first_published_at,
    excluded.first_published_at
  )
  where public.daily_word_chapter_history.first_daily_motivation_id = excluded.first_daily_motivation_id;
  return new;
end;
$$;

revoke all on function public.enforce_daily_word_unique_content()
  from public, anon, authenticated;
revoke all on function public.reserve_daily_word_chapter_history()
  from public, anon, authenticated;

drop trigger if exists trg_enforce_daily_word_unique_content
  on public.daily_motivations;
create trigger trg_enforce_daily_word_unique_content
  before insert or update of publish_date, title, message, scripture_reference,
    scripture_chapter_key, has_study_quiz
  on public.daily_motivations
  for each row execute function public.enforce_daily_word_unique_content();

drop trigger if exists trg_reserve_daily_word_chapter_history
  on public.daily_motivations;
create trigger trg_reserve_daily_word_chapter_history
  after insert or update of title, message, content_fingerprint,
    scripture_chapter_key, status, is_published
  on public.daily_motivations
  for each row execute function public.reserve_daily_word_chapter_history();

create index if not exists daily_motivations_chapter_key_idx
  on public.daily_motivations (scripture_chapter_key);
create index if not exists daily_motivations_content_fingerprint_idx
  on public.daily_motivations (content_fingerprint);

alter table public.daily_bible_quizzes
  add column if not exists quiz_mode text not null default 'pop_quiz',
  add column if not exists study_chapter_key text,
  add column if not exists source_daily_motivation_id uuid
    references public.daily_motivations(id) on delete restrict;

alter table public.daily_bible_quizzes
  drop constraint if exists daily_bible_quizzes_quiz_mode_check;
alter table public.daily_bible_quizzes
  add constraint daily_bible_quizzes_quiz_mode_check
  check (quiz_mode in ('pop_quiz', 'chapter_study'));
alter table public.daily_bible_quizzes
  drop constraint if exists daily_bible_quizzes_study_contract_check;
alter table public.daily_bible_quizzes
  add constraint daily_bible_quizzes_study_contract_check
  check (
    (quiz_mode = 'pop_quiz' and study_chapter_key is null and source_daily_motivation_id is null)
    or
    (quiz_mode = 'chapter_study' and study_chapter_key is not null and source_daily_motivation_id is not null)
  ) not valid;

create index if not exists daily_bible_quizzes_study_source_idx
  on public.daily_bible_quizzes (source_daily_motivation_id, quiz_date)
  where quiz_mode = 'chapter_study';

create or replace function public.enforce_daily_bible_quiz_question_study_chapter()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode text;
  v_chapter_key text;
begin
  select quiz_mode, study_chapter_key into v_mode, v_chapter_key
  from public.daily_bible_quizzes
  where id = new.quiz_id;
  if v_mode = 'chapter_study' then
    if jsonb_typeof(new.scripture_references) <> 'array'
        or jsonb_array_length(new.scripture_references) < 1
        or exists (
          select 1
          from jsonb_array_elements_text(new.scripture_references) as r(reference_text)
          where public.canonical_bible_chapter_key(r.reference_text) is distinct from v_chapter_key
        ) then
      raise exception 'Every chapter-study quiz reference must belong to the Daily Word chapter';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_daily_bible_quiz_question_study_chapter()
  from public, anon, authenticated;
drop trigger if exists trg_enforce_daily_bible_quiz_question_study_chapter
  on public.daily_bible_quiz_questions;
create trigger trg_enforce_daily_bible_quiz_question_study_chapter
  before insert or update of quiz_id, scripture_references
  on public.daily_bible_quiz_questions
  for each row execute function public.enforce_daily_bible_quiz_question_study_chapter();

create or replace function public.enforce_daily_bible_quiz_study_publish()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_word public.daily_motivations;
  v_is_study_day boolean := extract(isodow from new.quiz_date)::integer in (1, 3, 6);
begin
  if new.status <> 'published'
      or (tg_op = 'UPDATE' and old.status = 'published')
      or new.quiz_date < date '2026-08-15' then
    return new;
  end if;
  if v_is_study_day and new.quiz_mode <> 'chapter_study' then
    raise exception 'Monday, Wednesday, and Saturday quizzes must use the Daily Word chapter';
  elsif not v_is_study_day and new.quiz_mode <> 'pop_quiz' then
    raise exception 'Non-study-day quizzes must use pop-quiz mode';
  end if;
  if new.quiz_mode = 'chapter_study' then
    select * into v_word
    from public.daily_motivations
    where id = new.source_daily_motivation_id;
    if not found
        or v_word.publish_date <> new.quiz_date
        or not v_word.has_study_quiz
        or v_word.scripture_chapter_key is distinct from new.study_chapter_key then
      raise exception 'Chapter-study quiz is not linked to the matching Daily Word';
    end if;
    if (
      select count(*)
      from public.daily_bible_quiz_questions qq
      where qq.quiz_id = new.id
        and jsonb_typeof(qq.scripture_references) = 'array'
        and jsonb_array_length(qq.scripture_references) > 0
        and not exists (
          select 1
          from jsonb_array_elements_text(qq.scripture_references) as r(reference_text)
          where public.canonical_bible_chapter_key(r.reference_text) is distinct from new.study_chapter_key
        )
    ) <> 5 then
      raise exception 'All five quiz questions must be grounded in the Daily Word chapter';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_daily_bible_quiz_study_publish()
  from public, anon, authenticated;
drop trigger if exists trg_enforce_daily_bible_quiz_study_publish
  on public.daily_bible_quizzes;
create trigger trg_enforce_daily_bible_quiz_study_publish
  before insert or update of status, quiz_mode, study_chapter_key,
    source_daily_motivation_id
  on public.daily_bible_quizzes
  for each row execute function public.enforce_daily_bible_quiz_study_publish();

-- Sanitized preview: developers can see wording/options and study linkage, but
-- never the answer index, answer value, or explanation.
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
  v_can_manage boolean;
begin
  select * into v_dev from public.require_developer(null);
  select * into v_settings
  from public.daily_content_generation_settings
  where id = true;
  v_can_manage := v_dev.developer_role = any(array[
    'super_developer', 'support_developer', 'content_moderator', 'security_admin'
  ]);

  return jsonb_build_object(
    'jamaica_date', v_today,
    'quiz_uniqueness_settings', jsonb_build_object(
      'guarantee_unique', coalesce(v_settings.quiz_guarantee_unique, true),
      'relaxed_history_days', coalesce(v_settings.relaxed_quiz_history_days, 60),
      'strict_history_scope', 'all_ever_published_and_scheduled_per_audience',
      'updated_at', v_settings.updated_at
    ),
    'can_manage_quiz_uniqueness_settings', v_can_manage,
    'can_manage_scheduled_content', v_can_manage,
    'daily_words', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'publish_date', d.publish_date,
        'release_at', (d.publish_date::timestamp + time '05:00') at time zone 'America/Jamaica',
        'title', d.title,
        'message', d.message,
        'scripture_reference', d.scripture_reference,
        'scripture_chapter_key', d.scripture_chapter_key,
        'has_study_quiz', d.has_study_quiz,
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
        'scope', case when q.church_id = 'grace_connect_global' then 'global' else 'church' end,
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
        'quiz_mode', q.quiz_mode,
        'study_chapter_key', q.study_chapter_key,
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

-- Daily Word must exist before the linked quiz is prepared. Two retry slots
-- make transient AI/provider errors recover without changing either release.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'daily-content-evening-preparation') then
    perform cron.unschedule('daily-content-evening-preparation');
  end if;
  if exists (select 1 from cron.job where jobname = 'daily-word-evening-preparation') then
    perform cron.unschedule('daily-word-evening-preparation');
  end if;
  if exists (select 1 from cron.job where jobname = 'daily-word-evening-preparation-retry') then
    perform cron.unschedule('daily-word-evening-preparation-retry');
  end if;
  if exists (select 1 from cron.job where jobname = 'daily-quiz-evening-preparation') then
    perform cron.unschedule('daily-quiz-evening-preparation');
  end if;
  if exists (select 1 from cron.job where jobname = 'daily-quiz-evening-preparation-retry') then
    perform cron.unschedule('daily-quiz-evening-preparation-retry');
  end if;
end $$;

select cron.schedule(
  'daily-word-evening-preparation',
  '15 1 * * *',
  $$select net.http_post(
    url := coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url' limit 1), 'https://nimgsgnkcvddomrgkawb.supabase.co') || '/functions/v1/generate-daily-motivation',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'daily_motivation_cron_secret' limit 1), '')),
    body := '{"action":"prepare"}'::jsonb
  );$$
);

select cron.schedule(
  'daily-word-evening-preparation-retry',
  '25 1 * * *',
  $$select net.http_post(
    url := coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url' limit 1), 'https://nimgsgnkcvddomrgkawb.supabase.co') || '/functions/v1/generate-daily-motivation',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'daily_motivation_cron_secret' limit 1), '')),
    body := '{"action":"prepare"}'::jsonb
  );$$
);

select cron.schedule(
  'daily-quiz-evening-preparation',
  '40 1 * * *',
  $$select net.http_post(
    url := coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url' limit 1), 'https://nimgsgnkcvddomrgkawb.supabase.co') || '/functions/v1/generate-daily-bible-quiz',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'daily_quiz_cron_secret' limit 1), '')),
    body := '{"action":"prepare"}'::jsonb
  );$$
);

select cron.schedule(
  'daily-quiz-evening-preparation-retry',
  '0 2 * * *',
  $$select net.http_post(
    url := coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url' limit 1), 'https://nimgsgnkcvddomrgkawb.supabase.co') || '/functions/v1/generate-daily-bible-quiz',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', coalesce((select decrypted_secret from vault.decrypted_secrets where name = 'daily_quiz_cron_secret' limit 1), '')),
    body := '{"action":"prepare"}'::jsonb
  );$$
);
