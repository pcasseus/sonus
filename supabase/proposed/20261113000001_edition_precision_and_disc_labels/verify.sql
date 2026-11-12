-- Read-only checks after applying the PROPOSED migration 20261113000001.
-- Expected: both columns present and nullable; three constraint/function
-- objects present; no row has a value yet (straight after deployment);
-- row and revision counts unchanged from the pre-deployment snapshot.

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'album_editions'
  and column_name in ('release_date_partial', 'disc_labels')
order by column_name;

select conname
from pg_constraint
where conrelid = 'public.album_editions'::regclass
  and conname in (
    'album_editions_release_date_partial_format',
    'album_editions_disc_labels_valid'
  )
order by conname;

select proname
from pg_proc
where proname = 'album_edition_disc_labels_valid';

select
  count(*) as editions,
  count(release_date_partial) as with_partial,
  count(disc_labels) as with_disc_labels,
  max(server_revision) as max_revision
from public.album_editions;
