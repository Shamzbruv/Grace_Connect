-- Batch authorization for playback signing.
--
-- sign-reel-playback receives reel ids from a client, which is a request and
-- not proof of entitlement. This resolves that batch through exactly the same
-- predicate the feed uses, so the feed and the signer can never disagree
-- about who may see a reel -- a disagreement there would hand out private
-- media through a signed URL.
--
-- Unauthorized ids are simply absent from the result rather than raising, so
-- the endpoint cannot be used to probe which reels exist.
create or replace function public.authorize_reel_playback(
  p_viewer uuid,
  p_reel_ids uuid[]
) returns table (id uuid, video_object_key text, poster_object_key text)
language sql stable security definer set search_path = ''
as $$
  select r.id, r.video_object_key, r.poster_object_key
  from public.reels r
  where r.id = any(p_reel_ids)
    and r.video_object_key is not null
    and private.can_view_reel(p_viewer, r.id)
  -- Bounded independently of the caller, so a large array cannot turn this
  -- into a bulk signing oracle even if the function's caller changes.
  limit 20;
$$;

-- Only the service role (the Edge Function) may call this. It takes the
-- viewer as a parameter rather than reading auth.uid(), so exposing it to
-- clients would let one member resolve another member's permitted media.
revoke all on function public.authorize_reel_playback(uuid, uuid[])
  from public, anon, authenticated;
grant execute on function public.authorize_reel_playback(uuid, uuid[]) to service_role;
