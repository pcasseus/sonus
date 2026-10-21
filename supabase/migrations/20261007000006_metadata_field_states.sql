-- SN-40.3C
-- Persist field-level metadata authority/provenance with each cloud-owned
-- library entity. Existing rows intentionally remain NULL so legacy cloud
-- data is not mistaken for an authoritative empty provenance snapshot.

alter table public.artists
  add column if not exists metadata_field_states jsonb null;

alter table public.albums
  add column if not exists metadata_field_states jsonb null;

alter table public.album_editions
  add column if not exists metadata_field_states jsonb null;

alter table public.songs
  add column if not exists metadata_field_states jsonb null;

alter table public.artists
  add constraint artists_metadata_field_states_is_array
  check (
    metadata_field_states is null
    or jsonb_typeof(metadata_field_states) = 'array'
  );

alter table public.albums
  add constraint albums_metadata_field_states_is_array
  check (
    metadata_field_states is null
    or jsonb_typeof(metadata_field_states) = 'array'
  );

alter table public.album_editions
  add constraint album_editions_metadata_field_states_is_array
  check (
    metadata_field_states is null
    or jsonb_typeof(metadata_field_states) = 'array'
  );

alter table public.songs
  add constraint songs_metadata_field_states_is_array
  check (
    metadata_field_states is null
    or jsonb_typeof(metadata_field_states) = 'array'
  );