-- Match app and portal validation at the storage boundary as well.
update storage.buckets set file_size_limit=5242880,
  allowed_mime_types=array['image/jpeg','image/png','image/webp']
where id='quote-backgrounds';

-- Quote files are permanent while in the catalogue. They enter this queue only
-- after an explicit catalogue removal, never because they became 30 days old.
alter table public.media_cleanup_queue drop constraint media_cleanup_queue_bucket_id_check;
alter table public.media_cleanup_queue add constraint media_cleanup_queue_bucket_id_check
  check(bucket_id in ('community_media','chat_media','quote-backgrounds'));

create or replace function public.quote_background_removal_pending(target_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select target_path like 'quote_backgrounds/%'
    and exists(select 1 from public.media_cleanup_queue
      where bucket_id='quote-backgrounds' and object_path=target_path)
    and not exists(select 1 from public.quote_backgrounds where 'quote_backgrounds/'||file_name=target_path)
    and not public.retention_media_is_referenced(target_path)
$$;
revoke all on function public.quote_background_removal_pending(text) from public,anon,authenticated;
grant execute on function public.quote_background_removal_pending(text) to service_role;
