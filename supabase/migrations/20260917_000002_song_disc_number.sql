alter table public.songs
  add column if not exists disc_number integer not null default 1;

alter table public.songs
  drop constraint if exists songs_disc_number_nonnegative;

alter table public.songs
  add constraint songs_disc_number_nonnegative
    check (disc_number >= 0);
