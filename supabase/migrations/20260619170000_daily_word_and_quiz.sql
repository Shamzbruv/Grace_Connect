-- Daily Word, Daily Bible Quiz, and notification preference foundations.

alter table public.users
  add column if not exists "notifyDailyMotivation" boolean not null default true,
  add column if not exists "notifyDailyQuiz" boolean not null default true;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create table if not exists public.daily_motivations (
  id uuid primary key default gen_random_uuid(),
  publish_date date not null unique,
  title text not null,
  message text not null,
  scripture_reference text not null,
  topic text,
  source text not null default 'ai',
  status text not null default 'draft'
    check (status in ('draft', 'published', 'failed', 'unpublished')),
  is_published boolean not null default false,
  generated_at timestamptz,
  published_at timestamptz,
  notification_sent_at timestamptz,
  failure_reason text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_daily_motivations_updated_at
  on public.daily_motivations;
create trigger trg_daily_motivations_updated_at
  before update on public.daily_motivations
  for each row execute function public.set_updated_at();

alter table public.daily_motivations enable row level security;

drop policy if exists "Members view published daily motivations"
  on public.daily_motivations;
create policy "Members view published daily motivations"
  on public.daily_motivations
  for select
  to authenticated
  using (is_published = true and status = 'published');

drop policy if exists "Admins manage daily motivations"
  on public.daily_motivations;
create policy "Admins manage daily motivations"
  on public.daily_motivations
  for all
  to authenticated
  using (
    public.has_any_role(array[
      'Pastor',
      'Senior Pastor',
      'Assistant Pastor',
      'Acting Pastor',
      'Church Admin',
      'Admin',
      'Administrator',
      'Secretary',
      'Church Secretary'
    ])
    or public.has_app_privilege('manageDailyMotivations')
  )
  with check (
    public.has_any_role(array[
      'Pastor',
      'Senior Pastor',
      'Assistant Pastor',
      'Acting Pastor',
      'Church Admin',
      'Admin',
      'Administrator',
      'Secretary',
      'Church Secretary'
    ])
    or public.has_app_privilege('manageDailyMotivations')
  );

grant select on public.daily_motivations to authenticated;
grant insert, update, delete on public.daily_motivations to authenticated;

create table if not exists public.system_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  topic text not null,
  title text not null,
  body text not null,
  route text,
  type text not null default 'general',
  entity_table text,
  entity_id text,
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'failed', 'skipped')),
  provider_message_id text,
  error_message text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index if not exists system_notification_outbox_status_idx
  on public.system_notification_outbox (status, created_at desc);

alter table public.system_notification_outbox enable row level security;

drop policy if exists "Admins view system notification outbox"
  on public.system_notification_outbox;
create policy "Admins view system notification outbox"
  on public.system_notification_outbox
  for select
  to authenticated
  using (
    public.has_any_role(array['Pastor', 'Senior Pastor', 'Church Admin', 'Admin', 'Administrator'])
    or public.has_app_privilege('sendPushNotification')
  );

grant select on public.system_notification_outbox to authenticated;

create table if not exists public.daily_bible_quizzes (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  quiz_date date not null,
  available_at timestamptz not null,
  expires_at timestamptz not null,
  status text not null default 'draft'
    check (status in ('draft', 'published', 'failed', 'unpublished', 'archived')),
  generation_source text not null default 'ai',
  generation_status text not null default 'pending'
    check (generation_status in ('pending', 'generated', 'fallback', 'failed')),
  notification_sent_at timestamptz,
  validation_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (church_id, quiz_date)
);

create index if not exists daily_bible_quizzes_church_date_idx
  on public.daily_bible_quizzes (church_id, quiz_date desc);

drop trigger if exists trg_daily_bible_quizzes_updated_at
  on public.daily_bible_quizzes;
create trigger trg_daily_bible_quizzes_updated_at
  before update on public.daily_bible_quizzes
  for each row execute function public.set_updated_at();

alter table public.daily_bible_quizzes enable row level security;

drop policy if exists "Members view own church published quizzes"
  on public.daily_bible_quizzes;
create policy "Members view own church published quizzes"
  on public.daily_bible_quizzes
  for select
  to authenticated
  using (church_id = public.get_church_id() and status = 'published');

drop policy if exists "Admins view own church quizzes"
  on public.daily_bible_quizzes;
create policy "Admins view own church quizzes"
  on public.daily_bible_quizzes
  for select
  to authenticated
  using (
    church_id = public.get_church_id()
    and (
      public.has_any_role(array['Pastor', 'Senior Pastor', 'Church Admin', 'Admin', 'Administrator'])
      or public.has_app_privilege('manageDailyBibleQuiz')
    )
  );

grant select on public.daily_bible_quizzes to authenticated;
grant insert, update, delete on public.daily_bible_quizzes to authenticated;

drop policy if exists "Admins manage own church quizzes"
  on public.daily_bible_quizzes;
create policy "Admins manage own church quizzes"
  on public.daily_bible_quizzes
  for all
  to authenticated
  using (
    church_id = public.get_church_id()
    and (
      public.has_any_role(array['Pastor', 'Senior Pastor', 'Church Admin', 'Admin', 'Administrator'])
      or public.has_app_privilege('manageDailyBibleQuiz')
    )
  )
  with check (
    church_id = public.get_church_id()
    and (
      public.has_any_role(array['Pastor', 'Senior Pastor', 'Church Admin', 'Admin', 'Administrator'])
      or public.has_app_privilege('manageDailyBibleQuiz')
    )
  );

create table if not exists public.daily_bible_quiz_questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.daily_bible_quizzes(id) on delete cascade,
  question_order integer not null check (question_order between 1 and 5),
  question_text text not null,
  option_a text not null,
  option_b text not null,
  option_c text not null,
  option_d text not null,
  correct_option_index integer not null check (correct_option_index between 0 and 3),
  correct_answer text not null,
  explanation text not null,
  scripture_references jsonb not null default '[]'::jsonb,
  category text,
  difficulty text,
  question_hash text not null,
  created_at timestamptz not null default now(),
  unique (quiz_id, question_order),
  unique (quiz_id, question_hash)
);

create index if not exists daily_bible_quiz_questions_quiz_idx
  on public.daily_bible_quiz_questions (quiz_id, question_order);

alter table public.daily_bible_quiz_questions enable row level security;

drop policy if exists "Admins view quiz answers for own church"
  on public.daily_bible_quiz_questions;
create policy "Admins view quiz answers for own church"
  on public.daily_bible_quiz_questions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.daily_bible_quizzes q
      where q.id = quiz_id
        and q.church_id = public.get_church_id()
        and (
          public.has_any_role(array['Pastor', 'Senior Pastor', 'Church Admin', 'Admin', 'Administrator'])
          or public.has_app_privilege('manageDailyBibleQuiz')
        )
    )
  );

grant select on public.daily_bible_quiz_questions to authenticated;
grant insert, update, delete on public.daily_bible_quiz_questions to authenticated;

drop policy if exists "Admins manage quiz questions for own church"
  on public.daily_bible_quiz_questions;
create policy "Admins manage quiz questions for own church"
  on public.daily_bible_quiz_questions
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.daily_bible_quizzes q
      where q.id = quiz_id
        and q.church_id = public.get_church_id()
        and (
          public.has_any_role(array['Pastor', 'Senior Pastor', 'Church Admin', 'Admin', 'Administrator'])
          or public.has_app_privilege('manageDailyBibleQuiz')
        )
    )
  )
  with check (
    exists (
      select 1
      from public.daily_bible_quizzes q
      where q.id = quiz_id
        and q.church_id = public.get_church_id()
        and (
          public.has_any_role(array['Pastor', 'Senior Pastor', 'Church Admin', 'Admin', 'Administrator'])
          or public.has_app_privilege('manageDailyBibleQuiz')
        )
    )
  );

create table if not exists public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.daily_bible_quizzes(id) on delete cascade,
  member_id uuid not null references auth.users(id) on delete cascade,
  church_id text not null,
  church_id_at_attempt text not null,
  status text not null default 'active'
    check (status in ('active', 'completed', 'failed', 'abandoned', 'expired', 'timed_out')),
  started_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  failure_reason text,
  current_question_order integer not null default 1,
  question_started_at timestamptz,
  last_heartbeat_at timestamptz,
  total_score integer not null default 0,
  correct_answers integer not null default 0,
  total_response_time_ms bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (quiz_id, member_id)
);

create index if not exists quiz_attempts_member_idx
  on public.quiz_attempts (member_id, created_at desc);
create index if not exists quiz_attempts_church_status_idx
  on public.quiz_attempts (church_id, status, created_at desc);
create index if not exists quiz_attempts_leaderboard_idx
  on public.quiz_attempts (church_id_at_attempt, completed_at desc, total_score desc)
  where status = 'completed';

drop trigger if exists trg_quiz_attempts_updated_at on public.quiz_attempts;
create trigger trg_quiz_attempts_updated_at
  before update on public.quiz_attempts
  for each row execute function public.set_updated_at();

alter table public.quiz_attempts enable row level security;

drop policy if exists "Members view own quiz attempts"
  on public.quiz_attempts;
create policy "Members view own quiz attempts"
  on public.quiz_attempts
  for select
  to authenticated
  using (member_id = auth.uid());

drop policy if exists "Admins view own church quiz attempts"
  on public.quiz_attempts;
create policy "Admins view own church quiz attempts"
  on public.quiz_attempts
  for select
  to authenticated
  using (
    church_id = public.get_church_id()
    and (
      public.has_any_role(array['Pastor', 'Senior Pastor', 'Church Admin', 'Admin', 'Administrator'])
      or public.has_app_privilege('manageDailyBibleQuiz')
    )
  );

grant select on public.quiz_attempts to authenticated;

create table if not exists public.quiz_attempt_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.quiz_attempts(id) on delete cascade,
  question_id uuid not null references public.daily_bible_quiz_questions(id) on delete cascade,
  selected_option_index integer,
  is_correct boolean not null default false,
  points_awarded integer not null default 0,
  answered_at timestamptz,
  response_time_ms integer,
  timed_out boolean not null default false,
  created_at timestamptz not null default now(),
  unique (attempt_id, question_id)
);

create index if not exists quiz_attempt_answers_attempt_idx
  on public.quiz_attempt_answers (attempt_id, created_at);

alter table public.quiz_attempt_answers enable row level security;

drop policy if exists "Members view own quiz answer feedback"
  on public.quiz_attempt_answers;
create policy "Members view own quiz answer feedback"
  on public.quiz_attempt_answers
  for select
  to authenticated
  using (
    exists (
      select 1 from public.quiz_attempts a
      where a.id = attempt_id and a.member_id = auth.uid()
    )
  );

grant select on public.quiz_attempt_answers to authenticated;

create table if not exists public.monthly_quiz_winners (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  quiz_month date not null,
  member_id uuid not null references auth.users(id) on delete cascade,
  rank integer not null check (rank between 1 and 3),
  total_points integer not null,
  correct_answers integer not null,
  perfect_quizzes integer not null,
  total_response_time_ms bigint not null,
  created_at timestamptz not null default now(),
  unique (church_id, quiz_month, rank),
  unique (church_id, quiz_month, member_id)
);

create index if not exists monthly_quiz_winners_church_month_idx
  on public.monthly_quiz_winners (church_id, quiz_month desc, rank);

alter table public.monthly_quiz_winners enable row level security;

drop policy if exists "Members view own church monthly quiz winners"
  on public.monthly_quiz_winners;
create policy "Members view own church monthly quiz winners"
  on public.monthly_quiz_winners
  for select
  to authenticated
  using (church_id = public.get_church_id());

grant select on public.monthly_quiz_winners to authenticated;

create table if not exists public.quiz_security_events (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid references public.quiz_attempts(id) on delete set null,
  member_id uuid references auth.users(id) on delete set null,
  church_id text,
  event_type text not null,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index if not exists quiz_security_events_church_idx
  on public.quiz_security_events (church_id, created_at desc);

alter table public.quiz_security_events enable row level security;

drop policy if exists "Admins view own church quiz security events"
  on public.quiz_security_events;
create policy "Admins view own church quiz security events"
  on public.quiz_security_events
  for select
  to authenticated
  using (
    church_id = public.get_church_id()
    and (
      public.has_any_role(array['Pastor', 'Senior Pastor', 'Church Admin', 'Admin', 'Administrator'])
      or public.has_app_privilege('manageDailyBibleQuiz')
    )
  );

grant select on public.quiz_security_events to authenticated;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'daily_motivations'
    ) then
      execute 'alter publication supabase_realtime add table public.daily_motivations';
    end if;
  end if;
exception when undefined_object then
  null;
end;
$$;
