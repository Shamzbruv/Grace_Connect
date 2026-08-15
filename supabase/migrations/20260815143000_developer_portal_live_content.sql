-- Show developers what is currently live today, not just what is scheduled
-- for the future. Same sanitization rules as the existing preview: quiz
-- answer index, answer value, and explanation are never included.

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
    'current_daily_word', (
      select jsonb_build_object(
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
      )
      from public.daily_motivations d
      where d.publish_date = v_today
        and d.status = 'published'
      limit 1
    ),
    'current_quizzes', coalesce((
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
        'quiz_mode', q.quiz_mode,
        'study_chapter_key', q.study_chapter_key,
        'question_count', (
          select count(*) from public.daily_bible_quiz_questions qq
          where qq.quiz_id = q.id
        ),
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
      ) order by q.church_id)
      from public.daily_bible_quizzes q
      where q.quiz_date = v_today
        and q.status = 'published'
    ), '[]'::jsonb),
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
