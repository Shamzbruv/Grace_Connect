-- The launch reset truncates public content. Its private preparation state
-- must also be cleared so a subsequent Prepare month can rebuild that content.
-- This trigger runs only when an authorized operator truncates the quiz table;
-- ordinary row deletion and normal retention never restart prepared content.
create function private.clear_daily_content_preparation_after_reset()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 truncate table private.daily_content_batch_jobs,private.quiz_generation_leases;
 return null;
end $$;
revoke all on function private.clear_daily_content_preparation_after_reset() from public,anon,authenticated;
create trigger clear_daily_content_preparation_after_reset
after truncate on public.daily_bible_quizzes
for each statement execute function private.clear_daily_content_preparation_after_reset();
