alter table public.songs
  add column if not exists version_label text,
  add column if not exists version_characteristics text[] not null default '{}',
  add column if not exists release_status text not null default 'released',
  add column if not exists is_leak boolean not null default false;

alter table public.songs
  drop constraint if exists songs_release_status_valid;

alter table public.songs
  add constraint songs_release_status_valid
    check (release_status in ('released', 'unreleased'));
