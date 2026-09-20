-- Data retention (security review 2026-09-19). Nothing was ever deleted:
-- usage events, magic codes, expired sessions and raw webhook payloads
-- (billing PII) grew forever. Rate-limit windows only ever look back 24h.
create extension if not exists pg_cron;

select cron.schedule('purge-usage-events', '17 * * * *',
  $$delete from public.translation_usage_events where created_at < timezone('utc', now()) - interval '7 days'$$);
select cron.schedule('purge-magic-codes', '23 * * * *',
  $$delete from public.magic_codes where created_at < timezone('utc', now()) - interval '24 hours'$$);
select cron.schedule('purge-expired-sessions', '29 * * * *',
  $$delete from public.app_sessions where expires_at < timezone('utc', now()) - interval '7 days'$$);
select cron.schedule('scrub-webhook-payloads', '35 3 * * *',
  $$update public.paddle_webhook_events set payload = '{}'::jsonb
     where received_at < timezone('utc', now()) - interval '30 days' and payload <> '{}'::jsonb$$);
select cron.schedule('forget-identity-networks', '41 4 * * *',
  $$update public.translation_identities set created_ip_hash = null
     where created_ip_hash is not null and first_seen_at < timezone('utc', now()) - interval '7 days'$$);
