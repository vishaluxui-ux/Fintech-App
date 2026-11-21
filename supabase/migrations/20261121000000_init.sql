-- Spend Inbox closed beta schema. Rows mirror the device tables (ACC-02).
-- Every table is private to its owner through RLS.

create table public.captures (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null check (source in ('upiNotification','bill','manual','cash')),
  source_app text,
  captured_at timestamptz not null,
  bill_total numeric(12,2),
  image_path text,            -- always null on the server: photos stay on the device
  withdrawal_id uuid,
  created_at timestamptz not null default now()
);

create table public.items (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  capture_id uuid not null references public.captures(id) on delete cascade,
  name text not null,
  amount numeric(12,2) not null check (amount > 0),
  category_id text not null,
  status text not null check (status in ('pending','approved','rejected','deleted')),
  spent_at timestamptz not null,
  flag_reason text,
  payee text,
  updated_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.withdrawals (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  at timestamptz not null,
  source_app text,
  created_at timestamptz not null default now()
);

create index on public.captures(user_id);
create index on public.items(user_id, status);
create index on public.withdrawals(user_id);

alter table public.captures enable row level security;
alter table public.items enable row level security;
alter table public.withdrawals enable row level security;

create policy "own captures" on public.captures for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own items" on public.items for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own withdrawals" on public.withdrawals for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Beta metric: AI cost and accuracy per bill (risk: AI cost per bill).
create table public.parse_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  model text not null,
  input_tokens int,
  output_tokens int,
  line_count int,
  created_at timestamptz not null default now()
);
alter table public.parse_log enable row level security;  -- no client policies: server only
