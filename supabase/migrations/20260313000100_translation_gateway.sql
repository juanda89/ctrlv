create table if not exists public.translation_identities (
  identity_hash text primary key,
  first_seen_at timestamptz not null default timezone('utc', now()),
  last_seen_at timestamptz not null default timezone('utc', now()),
  last_plan text not null default 'trial' check (last_plan in ('trial', 'active')),
  last_license_hash text
);

create table if not exists public.translation_usage_events (
  id uuid primary key default gen_random_uuid(),
  identity_hash text not null references public.translation_identities(identity_hash) on delete cascade,
  license_hash text,
  plan text not null check (plan in ('trial', 'active')),
  char_count integer not null check (char_count > 0),
  model text not null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists translation_usage_events_identity_created_idx
  on public.translation_usage_events (identity_hash, created_at desc);

create index if not exists translation_usage_events_license_created_idx
  on public.translation_usage_events (license_hash, created_at desc)
  where license_hash is not null;

alter table public.translation_identities enable row level security;
alter table public.translation_usage_events enable row level security;
