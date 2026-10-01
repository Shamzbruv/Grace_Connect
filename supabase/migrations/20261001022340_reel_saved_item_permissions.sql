-- Saving a hidden reel must not allow engagement changes through another table.
alter policy "Users manage own saved items" on public.social_saved_items
with check (user_id=(select auth.uid())::text and
  case when entity_type='reel' then public.can_read_reel(entity_id::uuid) else true end);

-- Existing post saves upsert metadata. Preserve that behavior while preventing
-- identity changes from bypassing the INSERT/DELETE engagement triggers.
create or replace function private.saved_item_identity_immutable()
returns trigger language plpgsql set search_path='' as $$
begin
  if (new.user_id,new.entity_type,new.entity_id) is distinct from
     (old.user_id,old.entity_type,old.entity_id) then
    raise exception 'Remove the saved item before saving a different item.' using errcode='23514';
  end if;
  return new;
end $$;
revoke all on function private.saved_item_identity_immutable() from public,anon,authenticated;
create trigger saved_item_identity_immutable before update on public.social_saved_items
for each row execute function private.saved_item_identity_immutable();
