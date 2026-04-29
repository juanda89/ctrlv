-- Add Stripe columns alongside existing Paddle columns (non-breaking).
-- Lemon Squeezy data was never migrated to these tables — Paddle webhook is legacy.
-- We add Stripe columns for the new subscription flow.

alter table public.subscription_accounts
  add column if not exists stripe_customer_id text unique;

create index if not exists subscription_accounts_stripe_customer_idx
  on public.subscription_accounts (stripe_customer_id)
  where stripe_customer_id is not null;

alter table public.account_subscriptions
  add column if not exists stripe_subscription_id text unique,
  add column if not exists provider text;

create index if not exists account_subscriptions_stripe_subscription_idx
  on public.account_subscriptions (stripe_subscription_id)
  where stripe_subscription_id is not null;

-- The status check constraint already accepts: 'trial', 'active', 'past_due', 'canceled', 'expired'
-- Stripe statuses we care about ('active', 'past_due', 'canceled') are already covered.
-- 'incomplete', 'incomplete_expired', 'trialing', 'unpaid' will be normalized in code.
