-- In-app feedback (ratings, comments, requests). Written only by the
-- submit-feedback Edge Function (service role); no public access.
create table if not exists public.app_feedback (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  rating smallint check (rating between 1 and 5),
  category text not null check (category in ('bug', 'idea', 'praise', 'other')),
  message text not null default '',
  contact_email text,
  account_id uuid references public.subscription_accounts(id) on delete set null,
  install_id_hash text not null,
  app_version text,
  platform text not null default 'macos',
  email_sent boolean not null default false
);

create index if not exists app_feedback_install_created_idx
  on public.app_feedback (install_id_hash, created_at desc);

alter table public.app_feedback enable row level security;

create policy "No public access" on public.app_feedback
  for all using (false);
