-- App Store (StoreKit 2) subscriptions live in the same table as Stripe ones,
-- distinguished by provider='appstore' and keyed by Apple's original
-- transaction id (stable across renewals).
alter table public.account_subscriptions
  add column if not exists appstore_original_transaction_id text unique;

create index if not exists account_subscriptions_appstore_original_tx_idx
  on public.account_subscriptions (appstore_original_transaction_id)
  where appstore_original_transaction_id is not null;
