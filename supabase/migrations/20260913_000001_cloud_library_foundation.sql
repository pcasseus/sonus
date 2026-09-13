-- SN-17: Cloud library foundation.
--
-- Local SQLite remains responsible for device-specific state such as
-- media_file_bindings and import_batches.
--
-- Cloud rows use Sonus logical IDs as text while ownership is anchored
-- to Supabase Auth UUIDs.
--
-- deleted_at is a sync tombstone. Normal application deletion should
-- mark rows deleted rather than immediately hard-delete them.

create table public.artwork_assets (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_object_key text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint artwork_assets_id_not_blank
    check (length(trim(id)) > 0),

  constraint artwork_assets_storage_object_key_not_blank
    check (length(trim(storage_object_key)) > 0),

  constraint artwork_assets_user_id_id_unique
    unique (user_id, id),

  constraint artwork_assets_user_storage_object_key_unique
    unique (user_id, storage_object_key)
);

create table public.artists (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  canonical_name text not null,
  header_artwork_id text,
  top_artists_artwork_id text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint artists_id_not_blank
    check (length(trim(id)) > 0),

  constraint artists_name_not_blank
    check (length(trim(name)) > 0),

  constraint artists_canonical_name_not_blank
    check (length(trim(canonical_name)) > 0),

  constraint artists_user_id_id_unique
    unique (user_id, id),

  constraint artists_header_artwork_fk
    foreign key (user_id, header_artwork_id)
    references public.artwork_assets(user_id, id),

  constraint artists_top_artists_artwork_fk
    foreign key (user_id, top_artists_artwork_id)
    references public.artwork_assets(user_id, id)
);

create table public.albums (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  artist_id text not null,
  title text not null,
  canonical_title text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint albums_id_not_blank
    check (length(trim(id)) > 0),

  constraint albums_title_not_blank
    check (length(trim(title)) > 0),

  constraint albums_canonical_title_not_blank
    check (length(trim(canonical_title)) > 0),

  constraint albums_user_id_id_unique
    unique (user_id, id),

  constraint albums_user_artist_id_id_unique
    unique (user_id, artist_id, id),

  constraint albums_artist_fk
    foreign key (user_id, artist_id)
    references public.artists(user_id, id)
);

create table public.album_editions (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  album_id text not null,
  title text not null,
  type text not null,
  is_primary boolean not null,
  release_date timestamptz,
  genre text,
  artwork_id text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint album_editions_id_not_blank
    check (length(trim(id)) > 0),

  constraint album_editions_title_not_blank
    check (length(trim(title)) > 0),

  constraint album_editions_type_not_blank
    check (length(trim(type)) > 0),

  constraint album_editions_user_id_id_unique
    unique (user_id, id),

  constraint album_editions_user_album_id_id_unique
    unique (user_id, album_id, id),

  constraint album_editions_album_fk
    foreign key (user_id, album_id)
    references public.albums(user_id, id),

  constraint album_editions_artwork_fk
    foreign key (user_id, artwork_id)
    references public.artwork_assets(user_id, id)
);

create table public.songs (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  artist_id text not null,
  album_id text not null,
  album_edition_id text not null,
  title text not null,
  canonical_title text not null,
  track_number integer not null,
  duration_seconds integer not null,
  is_single boolean not null,
  featured_artists text[] not null default '{}',
  artwork_id text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  server_updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint songs_id_not_blank
    check (length(trim(id)) > 0),

  constraint songs_title_not_blank
    check (length(trim(title)) > 0),

  constraint songs_canonical_title_not_blank
    check (length(trim(canonical_title)) > 0),

  constraint songs_track_number_nonnegative
    check (track_number >= 0),

  constraint songs_duration_seconds_nonnegative
    check (duration_seconds >= 0),

  constraint songs_user_id_id_unique
    unique (user_id, id),

  constraint songs_artist_fk
    foreign key (user_id, artist_id)
    references public.artists(user_id, id),

  constraint songs_album_artist_fk
    foreign key (user_id, artist_id, album_id)
    references public.albums(user_id, artist_id, id),

  constraint songs_album_edition_fk
    foreign key (user_id, album_id, album_edition_id)
    references public.album_editions(user_id, album_id, id),

  constraint songs_artwork_fk
    foreign key (user_id, artwork_id)
    references public.artwork_assets(user_id, id)
);

create or replace function public.set_server_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.server_updated_at = now();
  return new;
end;
$$;

create trigger artwork_assets_set_server_updated_at
before insert or update on public.artwork_assets
for each row
execute function public.set_server_updated_at();

create trigger artists_set_server_updated_at
before insert or update on public.artists
for each row
execute function public.set_server_updated_at();

create trigger albums_set_server_updated_at
before insert or update on public.albums
for each row
execute function public.set_server_updated_at();

create trigger album_editions_set_server_updated_at
before insert or update on public.album_editions
for each row
execute function public.set_server_updated_at();

create trigger songs_set_server_updated_at
before insert or update on public.songs
for each row
execute function public.set_server_updated_at();

create index artwork_assets_user_server_updated_idx
  on public.artwork_assets (user_id, server_updated_at, id);

create index artists_user_server_updated_idx
  on public.artists (user_id, server_updated_at, id);

create index albums_user_server_updated_idx
  on public.albums (user_id, server_updated_at, id);

create index album_editions_user_server_updated_idx
  on public.album_editions (user_id, server_updated_at, id);

create index songs_user_server_updated_idx
  on public.songs (user_id, server_updated_at, id);

create index artwork_assets_user_updated_idx
  on public.artwork_assets (user_id, updated_at);

create index artists_user_updated_idx
  on public.artists (user_id, updated_at);

create index albums_user_updated_idx
  on public.albums (user_id, updated_at);

create index album_editions_user_updated_idx
  on public.album_editions (user_id, updated_at);

create index songs_user_updated_idx
  on public.songs (user_id, updated_at);

create index artwork_assets_user_deleted_idx
  on public.artwork_assets (user_id, deleted_at)
  where deleted_at is not null;

create index artists_user_deleted_idx
  on public.artists (user_id, deleted_at)
  where deleted_at is not null;

create index albums_user_deleted_idx
  on public.albums (user_id, deleted_at)
  where deleted_at is not null;

create index album_editions_user_deleted_idx
  on public.album_editions (user_id, deleted_at)
  where deleted_at is not null;

create index songs_user_deleted_idx
  on public.songs (user_id, deleted_at)
  where deleted_at is not null;

alter table public.artwork_assets enable row level security;
alter table public.artists enable row level security;
alter table public.albums enable row level security;
alter table public.album_editions enable row level security;
alter table public.songs enable row level security;

revoke all on table public.artwork_assets from anon, authenticated;
revoke all on table public.artists from anon, authenticated;
revoke all on table public.albums from anon, authenticated;
revoke all on table public.album_editions from anon, authenticated;
revoke all on table public.songs from anon, authenticated;

grant select, insert, update on table public.artwork_assets to authenticated;
grant select, insert, update on table public.artists to authenticated;
grant select, insert, update on table public.albums to authenticated;
grant select, insert, update on table public.album_editions to authenticated;
grant select, insert, update on table public.songs to authenticated;

create policy "Users can read own artwork assets"
  on public.artwork_assets
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can insert own artwork assets"
  on public.artwork_assets
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update own artwork assets"
  on public.artwork_assets
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can read own artists"
  on public.artists
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can insert own artists"
  on public.artists
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update own artists"
  on public.artists
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can read own albums"
  on public.albums
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can insert own albums"
  on public.albums
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update own albums"
  on public.albums
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can read own album editions"
  on public.album_editions
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can insert own album editions"
  on public.album_editions
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update own album editions"
  on public.album_editions
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users can read own songs"
  on public.songs
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can insert own songs"
  on public.songs
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users can update own songs"
  on public.songs
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

insert into storage.buckets (id, name, public)
values ('artwork', 'artwork', false)
on conflict (id) do nothing;

create policy "Users can read own artwork objects"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'artwork'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users can upload own artwork objects"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'artwork'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users can update own artwork objects"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'artwork'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'artwork'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users can delete own artwork objects"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'artwork'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
