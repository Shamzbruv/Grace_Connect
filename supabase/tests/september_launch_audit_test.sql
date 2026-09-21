begin;
create temporary table launch_audit_assertions(description text);
create function pg_temp.audit_assert(ok boolean, description text)
returns void language plpgsql as $$
begin
 if ok is distinct from true then raise exception 'Launch audit failed: %',description; end if;
 insert into launch_audit_assertions values(description);
end;
$$;
do $test$
declare
 c text := 'audit_'||gen_random_uuid();
 private_church text := 'private_audit_'||gen_random_uuid();
 s uuid := gen_random_uuid();
 second_session uuid := gen_random_uuid();
 actor uuid := gen_random_uuid();
 other_user uuid := gen_random_uuid();
 membership uuid;
 quiz uuid := gen_random_uuid();
 result jsonb;
 until_at timestamptz;
 denied boolean;
begin
 insert into public.churches(id,"placeId",name,church_status,timezone)
 values(c,c||'_place','Rollback audit','approved','America/Jamaica');
 insert into auth.users(id,email,aud,role) values
   (actor,actor||'@audit.invalid','authenticated','authenticated'),
   (other_user,other_user||'@audit.invalid','authenticated','authenticated');
 insert into public.users(id,uid,email,"fullName","displayName")
 values(actor,actor::text,actor||'@audit.invalid','Audit Viewer','Audit Viewer'),
 (other_user,other_user::text,other_user||'@audit.invalid','Audit Other','Audit Other')
 on conflict(id) do update set "fullName"=excluded."fullName";
 insert into public.church_memberships(user_id,church_id,membership_status)
 values(actor,c,'active') returning id into membership;
 insert into public.church_member_roles(membership_id,role_name) values(membership,'Pastor');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 insert into public.churches(id,name,church_status,timezone,"isLive","liveStreamUrl",live_is_public,public_visibility)
 values(private_church,'Private audit church','approved','UTC',true,'https://example.invalid/live',false,true);
 perform pg_temp.audit_assert(not exists(select 1 from public.list_visible_live_churches(private_church,100) where id=private_church),
   'caller-supplied church cannot expose a private live stream');
 update public.churches set "isLive"=true,"liveStreamUrl"='https://example.invalid/live',live_is_public=false,public_visibility=true where id=c;
 perform pg_temp.audit_assert(exists(select 1 from public.list_visible_live_churches(null,100) where id=c),
   'members can still discover their own private live stream');

 perform pg_temp.audit_assert((select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='update_church_profile'),'profile RPC has one unambiguous signature');
 perform public.update_church_profile(c,'Audit renamed','Address','Church','America/Jamaica',
   p_managing_pastor_name=>'Test Pastor');
 perform public.update_church_profile(c,'Audit old client','Address','Church','America/Jamaica');
 perform pg_temp.audit_assert((select managing_pastor_name='Test Pastor' from public.churches where id=c),
   'older profile saves preserve pastor details');
 denied:=false;
 begin update public.churches set timezone='not/a/timezone' where id=c;
 exception when sqlstate '22023' then denied:=true; end;
 perform pg_temp.audit_assert(denied,'invalid timezone cannot break attendance');
 denied:=false;
 begin perform public.list_quiz_ranking('global','2026-99',25);
 exception when sqlstate '22023' then denied:=true; end;
 perform pg_temp.audit_assert(denied,'invalid ranking month rejected');
 insert into public.daily_bible_quizzes(id,church_id,quiz_date,available_at,expires_at)
 values(quiz,c,'2026-09-15','2026-09-15T00:00Z','2026-09-16T00:00Z');
 insert into public.quiz_attempts(quiz_id,member_id,church_id,church_id_at_attempt,status,completed_at,total_score)
 values(quiz,actor,c,c,'completed','2026-09-15T12:00Z',0);
 result:=public.list_quiz_ranking('global','2026-09',1);
 perform pg_temp.audit_assert(result->'viewer'->>'rank' is not null,'zero-score completed quiz still has viewer rank');
 insert into public.bible_streaks(user_id,church_id,user_name,streak_count,last_read_date)
 values(actor,c,'Audit Viewer',30000,(now() at time zone 'America/Jamaica')::date-10),
 (other_user,c,'Audit Other',20000,(now() at time zone 'America/Jamaica')::date);
 insert into public.social_profiles(user_id,display_name,visibility)
 values(other_user::text,'Private Person','private')
 on conflict(user_id) do update set visibility='private';
 result:=public.list_bible_streak_ranking('global',1);
 perform pg_temp.audit_assert(result->'viewer'->>'is_current'='false','expired streak flagged in viewer summary');
 perform pg_temp.audit_assert(result->'entries'->0->>'is_current'='true','active streaks precede historical streaks');
 perform pg_temp.audit_assert(result->'viewer'->>'rank' is not null,'viewer summary exists outside returned page');
 perform pg_temp.audit_assert(result->'entries'->0->>'user_name'='Private member'
   and result->'entries'->0->>'user_id' is null,'global ranking conceals private profile identity');

 perform set_config('request.jwt.claims',jsonb_build_object('role','service_role')::text,true);
 update public.church_memberships set church_id=c||'_place' where id=membership;
 result:=public.start_web_checkout_session_internal(actor,'tier_0_50','USD','fygaro');
 perform pg_temp.audit_assert(result->>'churchId'=c,'checkout normalizes authorized church aliases');
 insert into public.church_checkout_sessions(id,church_id,provider,provider_session_id,tier_code,currency,amount_minor)
 values(s,c,'fygaro',s::text,'tier_0_50','USD',1700);
 result:=public.apply_web_subscription_event_internal('fygaro',gen_random_uuid()::text,'payment_succeeded',
   s::text,null,'shared@example.invalid','active','USD',1,now(),now()+interval '1 month');
 perform pg_temp.audit_assert(result->>'matched'='false','underpayment cannot activate a subscription');
 result:=public.apply_web_subscription_event_internal('fygaro',gen_random_uuid()::text,'payment_succeeded',
   s::text,null,'shared@example.invalid','active','JMD',1700,now(),now()+interval '1 month');
 perform pg_temp.audit_assert(result->>'matched'='false','wrong currency cannot activate a subscription');
 result:=public.apply_web_subscription_event_internal('fygaro',s::text,'payment_succeeded',
   s::text,null,'shared@example.invalid','active','USD',1700,now(),now()+interval '1 month',null,
   '{"jwt":"DO_NOT_STORE","card":{"last4":"9999"}}');
 perform pg_temp.audit_assert(result->>'matched'='true','exact verified checkout activates paid access');
 select current_period_end into until_at from public.church_subscriptions where church_id=c;
 result:=public.get_web_subscription_portal_context_internal(actor);
 perform pg_temp.audit_assert(result->'subscription'->>'status'='active'
   and result->>'memberCount'='1','portal resolves alias memberships and paid access');
 perform pg_temp.audit_assert((select not auto_renews and next_charge_at is null
   and not billing_portal_enabled from public.church_subscriptions where church_id=c),'payment does not invent recurring mandate or portal');
 perform pg_temp.audit_assert((select not(payload ? 'jwt') and not(payload ? 'card')
   from public.church_billing_events where provider_event_id=s::text),'billing records exclude credentials and card details');
 result:=public.apply_web_subscription_event_internal('fygaro',s::text,'payment_succeeded',s::text);
 perform pg_temp.audit_assert(result->>'duplicate'='true','webhook retries are idempotent');
 result:=public.apply_web_subscription_event_internal('fygaro',gen_random_uuid()::text,'payment_succeeded',
   null,null,'shared@example.invalid','active','USD',1700,now(),now()+interval '1 month');
 perform pg_temp.audit_assert(result->>'matched'='false','shared email cannot select a church');
 result:=public.apply_web_subscription_event_internal('fygaro',gen_random_uuid()::text,'payment_succeeded',
   s::text,null,null,'active','USD',1700,now(),now()+interval '1 month');
 perform pg_temp.audit_assert(result->>'matched'='false','completed checkout cannot purchase another month');
 result:=public.request_web_subscription_cancellation_internal(actor,'Audit');
 insert into public.church_checkout_sessions(id,church_id,provider,provider_session_id,tier_code,currency,amount_minor)
 values(second_session,c,'fygaro',second_session::text,'tier_0_50','USD',1700);
 result:=public.apply_web_subscription_event_internal('fygaro',second_session::text,'payment_succeeded',
   second_session::text,null,null,'active','USD',1700,now(),now()+interval '1 month');
 perform pg_temp.audit_assert((select current_period_end>until_at and cancellation_effective_at is not null
   and not auto_renews from public.church_subscriptions where church_id=c),'later payment preserves paid time and cancellation');
 perform pg_temp.audit_assert(not has_function_privilege('authenticated',
   'public.apply_web_subscription_event_internal(text,text,text,text,text,text,text,text,bigint,timestamptz,timestamptz,timestamptz,jsonb)',
   'EXECUTE'),'members cannot impersonate payment webhooks');
end;
$test$;
select count(*) as passed from launch_audit_assertions;
rollback;
