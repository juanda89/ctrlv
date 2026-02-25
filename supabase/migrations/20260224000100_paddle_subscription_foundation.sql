create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table if not exists public.subscription_accounts (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  paddle_customer_id text unique,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists subscription_accounts_email_lower_idx
  on public.subscription_accounts (lower(email));

create table if not exists public.account_subscriptions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.subscription_accounts(id) on delete cascade,
  paddle_subscription_id text unique,
  status text not null check (status in ('trial', 'active', 'past_due', 'canceled', 'expired')),
  plan_name text,
  current_period_ends_at timestamptz,
  raw_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists account_subscriptions_account_id_idx
  on public.account_subscriptions (account_id, updated_at desc);

create table if not exists public.paddle_webhook_events (
  event_id text primary key,
  event_type text not null,
  payload jsonb not null,
  received_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.magic_codes (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  code_hash text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists magic_codes_lookup_idx
  on public.magic_codes (lower(email), created_at desc);

create table if not exists public.app_sessions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.subscription_accounts(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists app_sessions_token_hash_idx
  on public.app_sessions (token_hash);

drop trigger if exists set_subscription_accounts_updated_at on public.subscription_accounts;
create trigger set_subscription_accounts_updated_at
before update on public.subscription_accounts
for each row execute function public.set_updated_at();

drop trigger if exists set_account_subscriptions_updated_at on public.account_subscriptions;
create trigger set_account_subscriptions_updated_at
before update on public.account_subscriptions
for each row execute function public.set_updated_at();

alter table public.subscription_accounts enable row level security;
alter table public.account_subscriptions enable row level security;
alter table public.paddle_webhook_events enable row level security;
alter table public.magic_codes enable row level security;
alter table public.app_sessions enable row level security;
