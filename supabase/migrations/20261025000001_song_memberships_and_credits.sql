-- SN-45
-- Carry each song's edition listings (Deluxe songs inherited from
-- Standard, extra tracks, per-edition order and numbering) and its full
-- artist credit list. Additive only: existing rows stay NULL, which the
-- app reads as "not provided" and never as an authoritative empty list,
-- and apps without these fields keep writing every other column as before.
-- Apps that know the columns send them only after confirming they exist.

alter table public.songs
  add column if not exists edition_memberships jsonb null;

alter table public.songs
  add column if not exists artist_credits jsonb null;

alter table public.songs
  add constraint songs_edition_memberships_is_array
  check (
    edition_memberships is null
    or jsonb_typeof(edition_memberships) = 'array'
  );

alter table public.songs
  add constraint songs_artist_credits_is_array
  check (
    artist_credits is null
    or jsonb_typeof(artist_credits) = 'array'
  );
