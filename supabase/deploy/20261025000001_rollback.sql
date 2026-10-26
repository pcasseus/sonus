-- Rollback for migration 20261025000001. Use only if the deployment must be
-- reverted. It removes the two song columns and their checks; every other
-- column and row is untouched. Data lost: only memberships and credits
-- written after deployment, which every device still holds locally and
-- re-uploads once the columns return. Apps keep working either way: they
-- detect the missing columns and stop sending them.
--
-- Preview first (nothing is kept):
--   begin; \i 20261025000001_rollback.sql
--   select count(*) from public.songs;
--   rollback;

alter table public.songs drop constraint if exists songs_edition_memberships_is_array;
alter table public.songs drop constraint if exists songs_artist_credits_is_array;
alter table public.songs drop column if exists edition_memberships;
alter table public.songs drop column if exists artist_credits;

-- Afterwards, also remove the migration from Supabase's history so it can
-- be applied again later:
--   supabase migration repair 20261025000001 --status reverted
