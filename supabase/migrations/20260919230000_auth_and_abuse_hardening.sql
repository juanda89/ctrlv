-- Security review 2026-09-19: magic-code brute force, per-network trial abuse,
-- defense in depth on PostgREST grants.

-- 1. Magic codes: bounded attempts per code, issuer IP hash for per-network caps.
alter table public.magic_codes add column if not exists attempts smallint not null default 0;
alter table public.magic_codes add column if not exists ip_hash text;
create index if not exists magic_codes_email_created_idx on public.magic_codes (email, created_at desc);
create index if not exists magic_codes_ip_created_idx on public.magic_codes (ip_hash, created_at desc) where ip_hash is not null;

-- Atomic verify: locks the newest live code for the email, consumes it on a
-- match, counts a failed attempt otherwise and burns the code after
-- p_max_attempts. Returns 'ok' | 'invalid' | 'none'. With 3 codes per email
-- per 10 minutes that bounds online guessing to 15 tries per window.
create or replace function public.consume_magic_code(
  p_email text,
  p_code_hash text,
  p_max_attempts integer default 5
)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  r public.magic_codes%rowtype;
  v_now timestamptz := timezone('utc', now());
begin
  select * into r
    from public.magic_codes
   where email = p_email
     and consumed_at is null
     and expires_at > v_now
   order by created_at desc
   limit 1
   for update;

  if not found then
    return 'none';
  end if;

  if r.code_hash = p_code_hash then
    update public.magic_codes set consumed_at = v_now where id = r.id;
    return 'ok';
  end if;

  update public.magic_codes
     set attempts = attempts + 1,
         consumed_at = case when attempts + 1 >= p_max_attempts then v_now else null end
   where id = r.id;
  return 'invalid';
end;
$$;
revoke all on function public.consume_magic_code(text, text, integer) from public;
revoke all on function public.consume_magic_code(text, text, integer) from anon, authenticated;
grant execute on function public.consume_magic_code(text, text, integer) to service_role;

-- 2. Trial identities: remember the network that created each one so a
-- script rotating installIDs cannot mint unlimited trials. The hash is
-- peppered server-side and cleared by the retention job.
alter table public.translation_identities add column if not exists created_ip_hash text;
create index if not exists translation_identities_created_ip_idx
  on public.translation_identities (created_ip_hash, first_seen_at desc) where created_ip_hash is not null;

drop function if exists public.translate_begin(text, text, integer);
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

-- 3. Defense in depth: no first-party client talks to PostgREST with the anon
-- key (every Edge Function uses the service role), so the public roles need
-- no table privileges at all. RLS stays as the second barrier.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated;

alter function public.set_updated_at() set search_path = pg_catalog, public;
