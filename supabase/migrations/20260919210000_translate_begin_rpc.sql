-- translate_begin: everything /translate needs before calling the model, in
-- ONE round trip. It replaces 4 (trial) to 8 (signed-in) sequential PostgREST
-- calls: identity upsert + sync, session lookup + sliding renewal,
-- subscription lookup, and the usage-window counts for rate limiting.
-- The verdict itself stays in the Edge Function (limits come from secrets);
-- this function only reads, upserts and counts.
create or replace function public.translate_begin(
  p_identity_hash text,
  p_token_hash text default null,
  p_session_lifetime_days integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_now timestamptz := timezone('utc', now());
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
begin
  -- Session -> subscription. Same rules as the former lookupActiveSubscription.
  if p_token_hash is not null then
    select s.account_id, s.expires_at
      into v_account_id, v_expires_at
      from public.app_sessions s
     where s.token_hash = p_token_hash
       and s.expires_at > v_now;

    if v_account_id is not null then
      -- Sliding renewal: only write when it moves expires_at by >= 24h
      -- (mirrors _shared/session.ts renewalThresholdMs).
      v_new_expiry := v_now + make_interval(days => p_session_lifetime_days);
      if v_new_expiry - v_expires_at >= interval '24 hours' then
        update public.app_sessions
           set expires_at = v_new_expiry
         where token_hash = p_token_hash;
      end if;

      select a.status, a.plan_name
        into v_status, v_plan_name
        from public.account_subscriptions a
       where a.account_id = v_account_id
       order by a.updated_at desc
       limit 1;

      if v_status = 'active' then
        v_plan := 'active';
        -- Must equal the Edge Function's sha256Hex(accountID) so existing
        -- license_hash rows keep counting (verified against production).
        v_account_hash := encode(extensions.digest(v_account_id::text, 'sha256'), 'hex');
      else
        v_plan_name := null;
      end if;
    end if;
  end if;

  -- Identity upsert + sync in one statement (was two).
  insert into public.translation_identities (identity_hash, last_seen_at, last_plan, last_license_hash)
  values (p_identity_hash, v_now, v_plan, v_account_hash)
  on conflict (identity_hash) do update
     set last_seen_at = excluded.last_seen_at,
         last_plan = excluded.last_plan,
         last_license_hash = excluded.last_license_hash
  returning first_seen_at into v_first_seen;

  -- Usage windows for the plan in force.
  if v_plan = 'trial' then
    select count(*)
      into v_identity_24h
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

revoke all on function public.translate_begin(text, text, integer) from public;
revoke all on function public.translate_begin(text, text, integer) from anon, authenticated;
grant execute on function public.translate_begin(text, text, integer) to service_role;
