-- Rollback for migration 20261026000001. Use only if the deployment must be
-- reverted. Nothing is deleted: the archive table is renamed and closed to
-- the app, so every archived record is kept and can be brought back. Apps
-- see the archive as missing and skip it; library sync is unaffected, and
-- every device keeps its playlists, history, lyrics, crops, organization
-- and Moments locally.
--
-- Preview first (nothing is kept):
--   begin; \i 20261026000001_rollback.sql
--   select to_regclass('public.sonus_archive_records');
--   rollback;

alter table if exists public.sonus_archive_records
  rename to sonus_archive_records_rolled_back;

revoke all on table public.sonus_archive_records_rolled_back
  from anon, authenticated;

notify pgrst, 'reload schema';

-- Afterwards, also mark the migration reverted so it can be applied again:
--   supabase migration repair 20261026000001 --status reverted
--
-- To bring the archive back later, instead of re-running the migration:
--   alter table public.sonus_archive_records_rolled_back
--     rename to sonus_archive_records;
--   grant select, insert, update on table public.sonus_archive_records
--     to authenticated;
--   notify pgrst, 'reload schema';
--   supabase migration repair 20261026000001 --status applied
