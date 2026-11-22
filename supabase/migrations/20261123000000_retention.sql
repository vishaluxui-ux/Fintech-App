-- Known-merchant auto-approval marker (shown in the app so users can undo).
alter table public.items add column auto_approved smallint not null default 0;

-- Alerts the built-in rules couldn't read and the AI read instead. Used to add
-- missed wordings to the rules. Server-only (no client policies); deleted with the account.
create table public.alert_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  app text,
  alert_text text not null,
  kind text,
  amount numeric(12,2),
  payee text,
  input_tokens int,
  output_tokens int,
  created_at timestamptz not null default now()
);
alter table public.alert_log enable row level security;
grant select, insert, update, delete on public.alert_log to service_role;
grant usage, select on all sequences in schema public to service_role;
