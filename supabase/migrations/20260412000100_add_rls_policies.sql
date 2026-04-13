-- Block all anonymous/public access to all tables.
-- Edge Functions use service_role which bypasses RLS,
-- so this is a safety net if the anon key is ever leaked.

create policy "No public access" on public.subscription_accounts
  for all using (false);

create policy "No public access" on public.account_subscriptions
  for all using (false);

create policy "No public access" on public.paddle_webhook_events
  for all using (false);

create policy "No public access" on public.magic_codes
  for all using (false);

create policy "No public access" on public.app_sessions
  for all using (false);

create policy "No public access" on public.translation_identities
  for all using (false);

create policy "No public access" on public.translation_usage_events
  for all using (false);
