-- Newer Supabase projects do not grant table access to API roles by default.
-- Signed-in users get row access; RLS still limits them to their own rows.
grant select, insert, update, delete on public.captures, public.items, public.withdrawals to authenticated;
-- parse_log is written only by the parse-bill function with the service role.
grant select, insert, update, delete on public.parse_log to service_role;
grant usage, select on all sequences in schema public to service_role;
grant select, insert, update, delete on public.captures, public.items, public.withdrawals to service_role;
