-- How the user explained a bill total mismatch (also a beta metric: parser vs bill problems).
alter table public.captures
  add column adjust_reason text check (adjust_reason in ('discount','printError','duplicateLine','other')),
  add column adjust_note text;
