-- Rollback for the PROPOSED migration 20261113000001 (not deployed).
-- Removes the two album_editions columns, their checks and the validation
-- function; every other column and row is untouched.
--
-- Data lost: release-date precision and disc names written to the cloud
-- after deployment. Each device still holds both locally (SQLite
-- album_editions.release_date_precision and album_edition_disc_labels, in
-- its backups) and re-uploads them once the columns return. A device that
-- was restored from the cloud alone, with no local copy, loses them: its
-- dates show as exact days again and its discs as "Disc N".
-- Apps keep working either way: they detect the missing columns and stop
-- sending them, as with the SN-45 song columns.
--
-- Preview first (nothing is kept):
--   begin; \i rollback.sql
--   select count(*) from public.album_editions;
--   rollback;

alter table public.album_editions
  drop constraint if exists album_editions_release_date_partial_format;
alter table public.album_editions
  drop constraint if exists album_editions_disc_labels_valid;
alter table public.album_editions drop column if exists release_date_partial;
alter table public.album_editions drop column if exists disc_labels;
drop function if exists public.album_edition_disc_labels_valid(jsonb);

-- Once deployed, also remove the migration from Supabase's history so it
-- can be applied again later:
--   supabase migration repair 20261113000001 --status reverted
