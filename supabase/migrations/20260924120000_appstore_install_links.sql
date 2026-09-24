-- App Store subscriptions bought without signing in (App Review guideline
-- 5.1.1 forbids requiring an account to purchase). Apple's signed transaction
-- proves the purchase; each install that forwards it is linked here and gets
-- the paid plan in translate_begin, signed in or not. Subscription rows for
-- such purchases have no account until the user signs in on a device.

alter table public.account_subscriptions alter column account_id drop not null;

create table if not exists public.appstore_install_links (
  original_transaction_id text not null,
  identity_hash text not null,
  linked_at timestamptz not null default timezone('utc', now()),
  primary key (original_transaction_id, identity_hash)
);

create index if not exists appstore_install_links_identity_idx
  on public.appstore_install_links (identity_hash);

alter table public.appstore_install_links enable row level security;
revoke all on table public.appstore_install_links from anon, authenticated;

create or replace function public.translate_begin(
  p_identity_hash text,
  p_token_hash text default null,
  p_session_lifetime_days integer default 30,
  p_ip_hash text default null,
  p_new_identity_limit integer default 50
)
returns jsonb
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_now timestamptz := timezone('utc', now());
  v_days integer := least(greatest(coalesce(p_session_lifetime_days, 30), 1), 90);
  v_first_seen timestamptz;
  v_account_id uuid;
  v_expires_at timestamptz;
  v_status text;
  v_plan_name text;
  v_plan text := 'trial';
  v_account_hash text;
  v_identity_24h integer := 0;
  v_account_10m integer := 0;
  v_account_24h integer := 0;
  v_account_chars_24h bigint := 0;
  v_new_expiry timestamptz;
  v_is_new boolean := false;
  v_new_from_ip integer := 0;
  v_link_status text;
  v_link_plan_name text;
  v_link_account_id uuid;
  v_link_transaction_id text;
begin
  -- Session -> subscription. Same rules as the former lookupActiveSubscription.
  if p_token_hash is not null then
    select s.account_id, s.expires_at
      into v_account_id, v_expires_at
      from public.app_sessions s
     where s.token_hash = p_token_hash
       and s.expires_at > v_now;

    if v_account_id is not null then
      v_new_expiry := v_now + make_interval(days => v_days);
      if v_new_expiry - v_expires_at >= interval '24 hours' then
        update public.app_sessions set expires_at = v_new_expiry where token_hash = p_token_hash;
      end if;

      select a.status, a.plan_name
        into v_status, v_plan_name
        from public.account_subscriptions a
       where a.account_id = v_account_id
       order by a.updated_at desc
       limit 1;

      if v_status = 'active' then
        v_plan := 'active';
        v_account_hash := encode(extensions.digest(v_account_id::text, 'sha256'), 'hex');
      else
        v_plan_name := null;
      end if;
    end if;
  end if;

  -- No paid plan through a session: an App Store subscription this install
  -- forwarded (bought without signing in, or kept after signing out) still
  -- counts. Fair-use counters are shared by every install of that purchase.
  if v_plan = 'trial' then
    select a.status, a.plan_name, a.account_id, a.appstore_original_transaction_id
      into v_link_status, v_link_plan_name, v_link_account_id, v_link_transaction_id
      from public.appstore_install_links l
      join public.account_subscriptions a on a.appstore_original_transaction_id = l.original_transaction_id
     where l.identity_hash = p_identity_hash
     order by (a.status = 'active') desc, a.updated_at desc
     limit 1;

    if v_link_status = 'active' then
      v_plan := 'active';
      v_plan_name := v_link_plan_name;
      v_account_hash := encode(extensions.digest(
        coalesce(v_link_account_id::text, 'appstore:' || v_link_transaction_id), 'sha256'), 'hex');
    end if;
  end if;

  -- New identity? Cap how many a single network can create per day.
  if not exists (select 1 from public.translation_identities t where t.identity_hash = p_identity_hash) then
    v_is_new := true;
    if p_ip_hash is not null and p_new_identity_limit > 0 then
      select count(*) into v_new_from_ip
        from public.translation_identities t
       where t.created_ip_hash = p_ip_hash
         and t.first_seen_at >= v_now - interval '24 hours';
      if v_new_from_ip >= p_new_identity_limit then
        return jsonb_build_object('blocked', 'new_identity_limit');
      end if;
    end if;
  end if;

  insert into public.translation_identities (identity_hash, last_seen_at, last_plan, last_license_hash, created_ip_hash)
  values (p_identity_hash, v_now, v_plan, v_account_hash, case when v_is_new then p_ip_hash else null end)
  on conflict (identity_hash) do update
     set last_seen_at = excluded.last_seen_at,
         last_plan = excluded.last_plan,
         last_license_hash = excluded.last_license_hash
  returning first_seen_at into v_first_seen;

  if v_plan = 'trial' then
    select count(*) into v_identity_24h
      from public.translation_usage_events e
     where e.identity_hash = p_identity_hash
       and e.created_at >= v_now - interval '24 hours';
  else
    select count(*) filter (where e.created_at >= v_now - interval '10 minutes'),
           count(*),
           coalesce(sum(e.char_count), 0)
      into v_account_10m, v_account_24h, v_account_chars_24h
      from public.translation_usage_events e
     where e.license_hash = v_account_hash
       and e.created_at >= v_now - interval '24 hours';
  end if;

  return jsonb_build_object(
    'first_seen_ms', (extract(epoch from v_first_seen) * 1000)::bigint,
    'plan', v_plan,
    'account_hash', v_account_hash,
    'plan_name', v_plan_name,
    'identity_24h', v_identity_24h,
    'account_10m', v_account_10m,
    'account_24h', v_account_24h,
    'account_chars_24h', v_account_chars_24h
  );
end;
$$;
revoke all on function public.translate_begin(text, text, integer, text, integer) from public;
revoke all on function public.translate_begin(text, text, integer, text, integer) from anon, authenticated;
grant execute on function public.translate_begin(text, text, integer, text, integer) to service_role;
