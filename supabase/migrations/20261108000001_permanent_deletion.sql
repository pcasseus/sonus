-- App Update 1.2: permanent deletion that stays permanent across devices.
--
-- NOT DEPLOYED. Reviewed source only; applying it to production needs the
-- user's separate authorisation (see deploy/20261108000001_staging_runbook.md).
--
-- Additive and idempotent. No existing row changes:
--
-- 1. A new archive kind, library_deletion: one record per permanent
--    deletion or duplicate merge (key: the operation id; payload: entity
--    types and ids only, never names or counts). Every device applies it,
--    including one that connects later.
-- 2. A tombstone is final. A library row whose deleted_at is set can never
--    be made live again, whichever client or fallback write tries. The same
--    holds for archive records of the history kinds (listening_session,
--    all_time_moment, library_deletion). Mutable archive kinds (playlists,
--    lyrics, ...) keep today's rules, so existing clients are unaffected.
-- 3. A deleted history record keeps no content: its payload must be '{}',
--    so the titles of deleted listening and stories leave the cloud.
--    Existing clients never delete history records, so they are unaffected.
-- 4. sonus_capabilities(): what this server supports, so a client enables
--    permanent deletion only against a server that carries 1-3.

-- 1. The library_deletion kind.
alter table public.sonus_archive_records
  drop constraint if exists sonus_archive_records_kind_check;
alter table public.sonus_archive_records
  add constraint sonus_archive_records_kind_check
  check (kind in (
    'playlist',
    'listening_session',
    'lyrics',
    'artwork_crop',
    'release_classification',
    'project_assignment',
    'all_time_moment',
    'library_deletion'
  ));

-- 2 and 3. Tombstones are final and empty.
create or replace function public.sonus_keep_tombstone_final()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if tg_table_name = 'sonus_archive_records' then
    if new.kind not in (
      'listening_session', 'all_time_moment', 'library_deletion'
    ) then
      return new;
    end if;
    if new.kind = 'library_deletion' and (
      new.is_deleted or new.payload is distinct from old.payload
    ) then
      raise exception 'A deletion record is permanent.'
        using errcode = '42501';
    end if;
    if old.is_deleted and not new.is_deleted then
      raise exception 'A deleted archive record cannot be restored.'
        using errcode = '42501';
    end if;
    if new.is_deleted and new.payload <> '{}'::jsonb then
      raise exception 'A deleted archive record keeps no content.'
        using errcode = '23514';
    end if;
  elsif old.deleted_at is not null and new.deleted_at is null then
    raise exception 'A deleted library record cannot be restored.'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

revoke all on function public.sonus_keep_tombstone_final() from public;

do $migration$
declare
  v_table text;
begin
  foreach v_table in array array[
    'artwork_assets',
    'artists',
    'albums',
    'album_editions',
    'songs',
    'sonus_archive_records'
  ]
  loop
    execute format(
      'drop trigger if exists %I on public.%I',
      v_table || '_keep_tombstone_final',
      v_table
    );
    execute format(
      'create trigger %I before update on public.%I '
      'for each row execute function public.sonus_keep_tombstone_final()',
      v_table || '_keep_tombstone_final',
      v_table
    );
  end loop;
end;
$migration$;

-- 4. Capabilities.
create or replace function public.sonus_capabilities()
returns text[]
language sql
stable
set search_path = ''
as $function$
  select array['permanent_deletion_v1']::text[];
$function$;

revoke all on function public.sonus_capabilities() from public, anon;
grant execute on function public.sonus_capabilities() to authenticated;
