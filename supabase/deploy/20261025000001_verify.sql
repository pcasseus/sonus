-- Read-only checks for migration 20261025000001 (song edition memberships
-- and credits). Safe on staging and production: SELECT only, no writes.

-- 1. Both columns exist, are nullable jsonb, with no default.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'songs'
  and column_name in ('edition_memberships', 'artist_credits')
order by column_name;

-- 2. Both array checks exist.
select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.songs'::regclass
  and conname in (
    'songs_edition_memberships_is_array',
    'songs_artist_credits_is_array'
  )
order by conname;

-- 3. Row-level security is still on and the song policies are unchanged
-- (compare with the list captured before deployment).
select relrowsecurity as rls_enabled
from pg_class where oid = 'public.songs'::regclass;

select policyname, cmd, roles::text, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'songs'
order by policyname;

-- 4. Row counts per table (compare with the counts captured before).
select 'artists' as table_name, count(*) from public.artists
union all select 'albums', count(*) from public.albums
union all select 'album_editions', count(*) from public.album_editions
union all select 'songs', count(*) from public.songs
union all select 'artwork_assets', count(*) from public.artwork_assets;

-- 5. Existing rows were not touched: right after deployment every value is
-- NULL. Later, only apps that know the columns fill them in.
select count(*) as songs,
       count(edition_memberships) as with_memberships,
       count(artist_credits) as with_credits
from public.songs;

-- 6. No duplicate permanent identities.
select id, count(*) from public.songs group by id having count(*) > 1;
