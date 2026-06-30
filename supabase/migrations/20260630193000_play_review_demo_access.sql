-- Google Play review access and developer access hardening.
--
-- This migration seeds a hidden, approved, subscribed demo church that can be
-- paired with reusable reviewer accounts from scripts/setup_google_play_review_accounts.py.
-- It intentionally does not grant developer access to any reviewer account.

do $$
declare
  demo_church_id text := 'grace_connect_review_demo_church';
  demo_quiz_id uuid;
begin
  insert into public.churches (
    id,
    "placeId",
    name,
    display_name,
    legal_name,
    location_name,
    denomination_label,
    address,
    parish,
    timezone,
    status,
    church_status,
    public_visibility,
    about,
    founded_year,
    contact_email,
    contact_phone,
    website_url,
    service_times_note,
    approved_at,
    "createdAt",
    updated_at,
    profile_updated_at
  )
  values (
    demo_church_id,
    demo_church_id,
    'Grace Connect Review Demo Church',
    'Grace Connect Review Demo Church',
    'Grace Connect Review Demo Church',
    'Review Demo',
    'Non-denominational',
    'Demo campus, Kingston, Jamaica',
    'Kingston',
    'America/Jamaica',
    'active',
    'approved',
    false,
    'A private demo congregation used only for Google Play app review. It contains sample content and no real member data.',
    2026,
    'review-demo@graceconnect.love',
    '+18760000000',
    'https://www.graceconnect.love',
    'Sunday worship 10:00 AM, Wednesday Bible study 7:00 PM',
    now(),
    now(),
    now(),
    now()
  )
  on conflict (id) do update
    set "placeId" = excluded."placeId",
        name = excluded.name,
        display_name = excluded.display_name,
        legal_name = excluded.legal_name,
        location_name = excluded.location_name,
        denomination_label = excluded.denomination_label,
        address = excluded.address,
        parish = excluded.parish,
        timezone = excluded.timezone,
        status = excluded.status,
        church_status = excluded.church_status,
        public_visibility = excluded.public_visibility,
        about = excluded.about,
        founded_year = excluded.founded_year,
        contact_email = excluded.contact_email,
        contact_phone = excluded.contact_phone,
        website_url = excluded.website_url,
        service_times_note = excluded.service_times_note,
        approved_at = coalesce(public.churches.approved_at, excluded.approved_at),
        updated_at = now(),
        profile_updated_at = now();

  insert into public.church_subscriptions (
    church_id,
    status,
    plan_code,
    source,
    current_period_start,
    current_period_end,
    free_until,
    notes,
    metadata
  )
  values (
    demo_church_id,
    'active',
    'play_review_demo',
    'system',
    now(),
    now() + interval '12 months',
    now() + interval '12 months',
    'Google Play review demo access. No payment data is stored.',
    jsonb_build_object('playReviewDemo', true)
  )
  on conflict (church_id) do update
    set status = 'active',
        plan_code = 'play_review_demo',
        source = 'system',
        current_period_start = coalesce(public.church_subscriptions.current_period_start, now()),
        current_period_end = now() + interval '12 months',
        free_until = now() + interval '12 months',
        notes = excluded.notes,
        metadata = public.church_subscriptions.metadata || excluded.metadata,
        updated_at = now();

  insert into public.daily_motivations (
    publish_date,
    title,
    message,
    scripture_reference,
    topic,
    source,
    status,
    is_published,
    generated_at,
    published_at
  )
  values (
    current_date,
    'Review Demo Daily Word',
    'Today is a demo devotional for app review. It shows how members receive a short scripture-based encouragement inside Grace Connect.',
    'Psalm 119:105',
    'demo',
    'play_review_demo',
    'published',
    true,
    now(),
    now()
  )
  on conflict (publish_date) do nothing;

  insert into public.daily_bible_quizzes (
    church_id,
    quiz_date,
    available_at,
    expires_at,
    status,
    generation_source,
    generation_status,
    validation_notes
  )
  values (
    demo_church_id,
    current_date,
    date_trunc('day', now()),
    date_trunc('day', now()) + interval '1 day' - interval '1 second',
    'published',
    'play_review_demo',
    'generated',
    'Seeded for Google Play review demo access.'
  )
  on conflict (church_id, quiz_date) do update
    set available_at = excluded.available_at,
        expires_at = excluded.expires_at,
        status = excluded.status,
        generation_source = excluded.generation_source,
        generation_status = excluded.generation_status,
        validation_notes = excluded.validation_notes,
        updated_at = now()
  returning id into demo_quiz_id;

  insert into public.daily_bible_quiz_questions (
    quiz_id,
    question_order,
    question_text,
    option_a,
    option_b,
    option_c,
    option_d,
    correct_option_index,
    correct_answer,
    explanation,
    scripture_references,
    category,
    difficulty,
    question_hash
  )
  values
    (demo_quiz_id, 1, 'Who built the ark?', 'Moses', 'Noah', 'David', 'Paul', 1, 'Noah', 'Genesis records that Noah built the ark.', '[{"book":"Genesis","chapter":6}]'::jsonb, 'Old Testament', 'easy', 'play-review-q1'),
    (demo_quiz_id, 2, 'Which book begins with "In the beginning"?', 'Matthew', 'Psalms', 'Genesis', 'Romans', 2, 'Genesis', 'Genesis opens with the creation account.', '[{"book":"Genesis","chapter":1}]'::jsonb, 'Old Testament', 'easy', 'play-review-q2'),
    (demo_quiz_id, 3, 'How many disciples did Jesus appoint as the Twelve?', '7', '10', '12', '40', 2, '12', 'The Gospels describe Jesus appointing twelve disciples.', '[{"book":"Mark","chapter":3}]'::jsonb, 'New Testament', 'easy', 'play-review-q3'),
    (demo_quiz_id, 4, 'What is described as a lamp to our feet?', 'Wisdom', 'The Word', 'A city', 'A trumpet', 1, 'The Word', 'Psalm 119 describes God''s word as a lamp and light.', '[{"book":"Psalm","chapter":119,"verse":105}]'::jsonb, 'Wisdom', 'easy', 'play-review-q4'),
    (demo_quiz_id, 5, 'Which apostle wrote many letters to early churches?', 'Paul', 'Samuel', 'Jonah', 'Esther', 0, 'Paul', 'Paul wrote several New Testament letters to churches and leaders.', '[{"book":"Romans","chapter":1}]'::jsonb, 'New Testament', 'easy', 'play-review-q5')
  on conflict (quiz_id, question_order) do update
    set question_text = excluded.question_text,
        option_a = excluded.option_a,
        option_b = excluded.option_b,
        option_c = excluded.option_c,
        option_d = excluded.option_d,
        correct_option_index = excluded.correct_option_index,
        correct_answer = excluded.correct_answer,
        explanation = excluded.explanation,
        scripture_references = excluded.scripture_references,
        category = excluded.category,
        difficulty = excluded.difficulty,
        question_hash = excluded.question_hash;
end $$;

update public.users u
set "isDeveloper" = exists (
  select 1
  from public.developer_accounts da
  where da.status = 'active'
    and (
      da.user_id = u.id
      or lower(da.email) = lower(coalesce(u.email, ''))
    )
)
where coalesce(u."isDeveloper", false) is distinct from exists (
  select 1
  from public.developer_accounts da
  where da.status = 'active'
    and (
      da.user_id = u.id
      or lower(da.email) = lower(coalesce(u.email, ''))
    )
);
