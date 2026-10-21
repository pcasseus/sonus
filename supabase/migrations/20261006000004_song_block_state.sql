alter table public.songs
  add column if not exists is_blocked boolean not null default false;
