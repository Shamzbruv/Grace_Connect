create table if not exists public.quiz_generation_runs (
  id uuid primary key default gen_random_uuid(),
  run_date date not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  trigger_source text not null default 'manual',
  churches_checked integer not null default 0,
  quizzes_published integer not null default 0,
  ai_status text not null default 'not_called',
  source_summary text,
  error_message text,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists quiz_generation_runs_run_date_idx
  on public.quiz_generation_runs (run_date desc, started_at desc);

alter table public.quiz_generation_runs enable row level security;

drop policy if exists "Quiz managers can view generation runs"
  on public.quiz_generation_runs;

create policy "Quiz managers can view generation runs"
  on public.quiz_generation_runs
  for select
  using (
    public.has_any_role(array[
      'Pastor',
      'Senior Pastor',
      'Church Admin',
      'Admin',
      'Administrator'
    ])
    or public.has_app_privilege('manageDailyBibleQuiz')
    or public.has_app_privilege('viewAnalytics')
  );
