-- Read through the existing reel visibility check; never persist signed media
-- URLs or expose a caption after its creator blocks a viewer.
create function public.get_my_saved_items(p_limit integer default 100)
returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(
   to_jsonb(s) || case when s.entity_type='reel' then jsonb_build_object(
     'is_available',detail.card is not null,
     'metadata',jsonb_build_object(
       'title',case when detail.card is null then 'Reel unavailable'
         else 'Reel by '||coalesce(nullif(detail.card->>'author_name',''),'Member') end,
       'subtitle',coalesce(detail.card->>'caption',''),'media_type','reel','media_url',''))
     else '{}'::jsonb end order by s.created_at desc,s.id desc),'[]'::jsonb)
 from (select * from public.social_saved_items where user_id=(select auth.uid())::text
   order by created_at desc,id desc limit greatest(1,least(coalesce(p_limit,100),100))) s
 left join lateral (select case when s.entity_type='reel' and
   s.entity_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   then public.get_reel_grace_detail(s.entity_id::uuid) end as card) detail on true;
$$;
revoke all on function public.get_my_saved_items(integer) from public,anon;
grant execute on function public.get_my_saved_items(integer) to authenticated;
