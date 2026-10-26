-- Read-only checks for migration 20261026000001 (cloud archive records).
-- Safe on staging and production: SELECT only, no writes.

-- 1. The table and its columns.
select column_name, data_type, is_nullable, column_default, is_generated
from information_schema.columns
where table_schema = 'public' and table_name = 'sonus_archive_records'
order by ordinal_position;

-- 2. Primary key and checks, and the cursor index.
select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.sonus_archive_records'::regclass
order by conname;

select indexname
from pg_indexes
where schemaname = 'public' and tablename = 'sonus_archive_records'
order by indexname;

-- 3. Row-level security on; exactly three own-row policies (select,
-- insert, update) and no delete policy.
select relrowsecurity as rls_enabled
from pg_class where oid = 'public.sonus_archive_records'::regclass;

select policyname, cmd, roles::text, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'sonus_archive_records'
order by policyname;

-- 4. The app role may select, insert and update; anon has nothing; nobody
-- in the app may delete.
select grantee, string_agg(privilege_type, ', ' order by privilege_type)
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'sonus_archive_records'
  and grantee in ('anon', 'authenticated')
group by grantee
order by grantee;

-- 5. Both triggers, using the existing functions.
select tgname, pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid = 'public.sonus_archive_records'::regclass and not tgisinternal
order by tgname;

-- 6. Every other policy is unchanged (compare with the list captured
-- before deployment).
select schemaname, tablename, policyname, cmd
from pg_policies
where schemaname in ('public', 'storage')
order by schemaname, tablename, policyname;

-- 7. Library row counts are unchanged (compare with the counts captured
-- before deployment). The archive starts empty.
select 'artists' as table_name, count(*) from public.artists
union all select 'albums', count(*) from public.albums
union all select 'album_editions', count(*) from public.album_editions
union all select 'songs', count(*) from public.songs
union all select 'artwork_assets', count(*) from public.artwork_assets
union all select 'sonus_archive_records', count(*) from public.sonus_archive_records;

-- 8. After the app has synced: records per account and kind, removals,
-- and that no permanent key is duplicated.
select user_id, kind, count(*) as records,
       count(*) filter (where is_deleted) as removed
from public.sonus_archive_records
group by user_id, kind
order by user_id, kind;

select count(*) as duplicate_keys
from (
  select user_id, library_id, kind, record_key
  from public.sonus_archive_records
  group by user_id, library_id, kind, record_key
  having count(*) > 1
) d;
