-- Credentials are encrypted in Vault, never returned to the browser.
create table private.fygaro_configuration (
 singleton boolean primary key default true check(singleton),
 secret_id uuid not null references vault.secrets(id),
 enabled boolean not null default false,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id) on delete set null
);
alter table private.fygaro_configuration enable row level security;
revoke all on private.fygaro_configuration from public,anon,authenticated;

create function public.fygaro_owner_settings(p_actor uuid,p_action text default 'status',p_config jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg private.fygaro_configuration; saved jsonb:='{}'; next jsonb; button text; kid text; secret text; hook_kid text; hook_secret text; enable boolean;
begin
 if not exists(select 1 from auth.users u join public.developer_accounts d
   on (d.user_id=u.id or (d.user_id is null and lower(d.email)=lower(u.email)))
   where u.id=p_actor and d.status='active' and d.developer_role='super_developer')
 then raise exception 'Only the platform owner can configure payments.' using errcode='42501'; end if;
 -- Serializes first-time setup and rotation without logging credential values.
 perform pg_advisory_xact_lock(hashtext('grace.fygaro.configuration'));
 select * into cfg from private.fygaro_configuration where singleton for update;
 if found then
   select decrypted_secret::jsonb into saved from vault.decrypted_secrets where id=cfg.secret_id;
   if saved is null then raise exception 'Stored payment configuration is unavailable.';end if;
 end if;
 if p_action='save' then
   if p_config is null or jsonb_typeof(p_config)<>'object' then raise exception 'Payment configuration is required.';end if;
   button:=trim(p_config->>'button_url');kid:=trim(p_config->>'key_id');
   secret:=coalesce(nullif(trim(p_config->>'secret_key'),''),saved->>'secret_key');
   hook_kid:=case when coalesce((p_config->>'same_webhook_key')::boolean,true) then kid else trim(p_config->>'webhook_key_id') end;
   hook_secret:=case when coalesce((p_config->>'same_webhook_key')::boolean,true) then secret
     else coalesce(nullif(trim(p_config->>'webhook_secret_key'),''),saved->>'webhook_secret_key') end;
   enable:=coalesce((p_config->>'enabled')::boolean,false);
   if button is null or length(button)>2048 or button !~ '^https://(www\.)?fygaro\.com/[a-zA-Z]{2}/pb/[a-zA-Z0-9_-]+/?$'
     then raise exception 'Enter the HTTPS payment-button URL copied from Fygaro.';end if;
   if kid is null or kid !~ '^[a-zA-Z0-9_-]{8,200}$' or hook_kid is null or hook_kid !~ '^[a-zA-Z0-9_-]{8,200}$'
     then raise exception 'Enter the Fygaro API key ID.';end if;
   if coalesce(length(secret),0) not between 16 and 4096 or coalesce(length(hook_secret),0) not between 16 and 4096
     then raise exception 'Enter both required API secrets (or use the same key for checkout and webhook).';end if;
   if saved->>'key_id' is distinct from kid and nullif(trim(p_config->>'secret_key'),'') is null
     then raise exception 'A new API key ID requires its matching secret.';end if;
   if not coalesce((p_config->>'same_webhook_key')::boolean,true) and saved->>'webhook_key_id' is distinct from hook_kid
     and nullif(trim(p_config->>'webhook_secret_key'),'') is null then raise exception 'A new webhook key ID requires its matching secret.';end if;
   next:=jsonb_build_object('button_url',button,'key_id',kid,'secret_key',secret,'webhook_key_id',hook_kid,
     'webhook_secret_key',hook_secret,'same_webhook_key',coalesce((p_config->>'same_webhook_key')::boolean,true));
   if saved->>'webhook_key_id' is not null and saved->>'webhook_key_id'<>hook_kid then
     next:=next||jsonb_build_object('previous_webhook_key_id',saved->>'webhook_key_id',
       'previous_webhook_secret_key',saved->>'webhook_secret_key','previous_webhook_expires_at',now()+interval '7 days');
   elsif (saved->>'previous_webhook_expires_at')::timestamptz>now() then
     next:=next||jsonb_build_object('previous_webhook_key_id',saved->>'previous_webhook_key_id',
       'previous_webhook_secret_key',saved->>'previous_webhook_secret_key','previous_webhook_expires_at',saved->>'previous_webhook_expires_at');
   end if;
   if cfg.secret_id is null then
     cfg.secret_id:=vault.create_secret(next::text,'grace_fygaro_credentials','Payment signing credentials managed by the platform owner');
     insert into private.fygaro_configuration(secret_id,enabled,updated_by) values(cfg.secret_id,enable,p_actor);
   else
     perform vault.update_secret(cfg.secret_id,next::text);
     update private.fygaro_configuration set enabled=enable,updated_at=now(),updated_by=p_actor where singleton;
   end if;
   saved:=next;
   perform public.log_developer_action('fygaro_configuration_saved','payment_gateway','fygaro',jsonb_build_object('enabled',enable));
   select * into cfg from private.fygaro_configuration where singleton;
 elsif p_action<>'status' then raise exception 'Unknown payment configuration action.';end if;
 return jsonb_build_object('configured',cfg.secret_id is not null,'enabled',coalesce(cfg.enabled,false),
   'button_url',coalesce(saved->>'button_url',''),'key_id',coalesce(saved->>'key_id',''),
   'webhook_key_id',coalesce(saved->>'webhook_key_id',''),'same_webhook_key',coalesce((saved->>'same_webhook_key')::boolean,true),
   'has_secret',coalesce(length(saved->>'secret_key'),0)>0,'has_webhook_secret',coalesce(length(saved->>'webhook_secret_key'),0)>0,
   'updated_at',cfg.updated_at);
end $$;
revoke all on function public.fygaro_owner_settings(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.fygaro_owner_settings(uuid,text,jsonb) to service_role;

-- Service-only: checkout and webhook functions need the signing material.
create function public.fygaro_runtime_configuration()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('enabled',c.enabled,'credentials',v.decrypted_secret::jsonb)
 from private.fygaro_configuration c join vault.decrypted_secrets v on v.id=c.secret_id where c.singleton;
$$;
revoke all on function public.fygaro_runtime_configuration() from public,anon,authenticated;
grant execute on function public.fygaro_runtime_configuration() to service_role;
