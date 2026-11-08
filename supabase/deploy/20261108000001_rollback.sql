-- Rollback for 20261108000001_permanent_deletion.sql. Removes the guards
-- and the probe; keeps every row. library_deletion rows stay but become
-- unreachable for the kind check only if none exist (verify first).
begin;
do $rollback$
declare
  v_table text;
begin
  foreach v_table in array array[
    'artwork_assets', 'artists', 'albums', 'album_editions', 'songs',
    'sonus_archive_records'
  ]
  loop
    execute format(
      'drop trigger if exists %I on public.%I',
      v_table || '_keep_tombstone_final', v_table
    );
  end loop;
end;
$rollback$;
drop function if exists public.sonus_keep_tombstone_final();
drop function if exists public.sonus_capabilities();
-- The kind check is restored only when no library_deletion row exists.
do $kinds$
begin
  if not exists (
    select 1 from public.sonus_archive_records where kind = 'library_deletion'
  ) then
    alter table public.sonus_archive_records
      drop constraint if exists sonus_archive_records_kind_check;
    alter table public.sonus_archive_records
      add constraint sonus_archive_records_kind_check
      check (kind in (
        'playlist', 'listening_session', 'lyrics', 'artwork_crop',
        'release_classification', 'project_assignment', 'all_time_moment'
      ));
  end if;
end;
$kinds$;
commit;
