-- Release readiness: cloud protection for user-created and historical data
-- that the library tables do not carry. Purely additive: one new table,
-- its own policies, the existing timestamp and revision triggers. No
-- existing table, row, policy or function changes.
--
-- Each row is one record of one kind, identified by a permanent key:
--   playlist                (playlist id; name and ordered items)
--   listening_session       (playback session id; session, segments and
--                            its qualified play, if any)
--   lyrics                  (song id)
--   artwork_crop            (target type and id)
--   release_classification  (album id)
--   project_assignment      (artist id)
--   all_time_moment         (Moment deduplication key)
-- library_id is reserved for separate cloud libraries in one account and
-- is always 'main' today. Rows are never deleted by the app: a removal is
-- recorded as is_deleted.

create table if not exists public.sonus_archive_records (
  user_id uuid not null references auth.users(id) on delete cascade,
  library_id text not null default 'main'
    check (length(library_id) between 1 and 64),
  kind text not null
    check (kind in (
      'playlist',
      'listening_session',
      'lyrics',
      'artwork_crop',
      'release_classification',
      'project_assignment',
      'all_time_moment'
    )),
  record_key text not null check (length(record_key) between 1 and 512),
  record_id text generated always as (kind || ':' || record_key) stored,
  payload jsonb not null
    check (
      jsonb_typeof(payload) = 'object'
      and octet_length(payload::text) <= 1048576
    ),
  is_deleted boolean not null default false,
  client_updated_at timestamptz not null,
  created_at timestamptz not null default now(),
  server_updated_at timestamptz not null default now(),
  server_revision bigint not null default 1 check (server_revision > 0),
  primary key (user_id, library_id, kind, record_key)
);

create index if not exists sonus_archive_records_sync_cursor
  on public.sonus_archive_records
  (user_id, library_id, server_updated_at, record_id);

alter table public.sonus_archive_records enable row level security;

revoke all on table public.sonus_archive_records from anon, authenticated;
grant select, insert, update on table public.sonus_archive_records
  to authenticated;

do $migration$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'sonus_archive_records'
      and policyname = 'Users can read own archive records'
  ) then
    create policy "Users can read own archive records"
      on public.sonus_archive_records for select to authenticated
      using ((select auth.uid()) = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'sonus_archive_records'
      and policyname = 'Users can insert own archive records'
  ) then
    create policy "Users can insert own archive records"
      on public.sonus_archive_records for insert to authenticated
      with check ((select auth.uid()) = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'sonus_archive_records'
      and policyname = 'Users can update own archive records'
  ) then
    create policy "Users can update own archive records"
      on public.sonus_archive_records for update to authenticated
      using ((select auth.uid()) = user_id)
      with check ((select auth.uid()) = user_id);
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgname = 'sonus_archive_records_set_server_updated_at'
  ) then
    create trigger sonus_archive_records_set_server_updated_at
      before insert or update on public.sonus_archive_records
      for each row execute function public.set_server_updated_at();
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgname = 'sonus_archive_records_set_server_revision'
  ) then
    create trigger sonus_archive_records_set_server_revision
      before insert or update on public.sonus_archive_records
      for each row execute function public.set_cloud_server_revision();
  end if;
end
$migration$;
