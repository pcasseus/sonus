\set ON_ERROR_STOP on

-- SN-45: run against an isolated local Supabase after
-- 20261025000001_song_memberships_and_credits.sql. Never against production.

BEGIN;

SELECT gen_random_uuid() AS owner_id \gset

INSERT INTO auth.users (id) VALUES (:'owner_id'::uuid);

INSERT INTO public.artists (id, user_id, name, canonical_name, created_at, updated_at)
VALUES ('sn45-artist', :'owner_id'::uuid, 'Artist', 'artist', now(), now());

INSERT INTO public.albums (id, user_id, artist_id, title, canonical_title, created_at, updated_at)
VALUES ('sn45-album', :'owner_id'::uuid, 'sn45-artist', 'Album', 'album', now(), now());

INSERT INTO public.album_editions (id, user_id, album_id, title, type, is_primary, created_at, updated_at)
VALUES ('sn45-standard', :'owner_id'::uuid, 'sn45-album', 'Standard', 'standard', true, now(), now());

-- A row written without the new columns keeps them NULL.
INSERT INTO public.songs (
    id, user_id, artist_id, album_id, album_edition_id, title, canonical_title,
    track_number, duration_seconds, is_single, featured_artists,
    created_at, updated_at
)
VALUES (
    'sn45-song', :'owner_id'::uuid, 'sn45-artist', 'sn45-album',
    'sn45-standard', 'Song', 'song', 1, 200, false, '{}', now(), now()
);

DO $test$
DECLARE
    revision_before bigint;
    revision_after bigint;
BEGIN
    IF (SELECT edition_memberships IS NOT NULL OR artist_credits IS NOT NULL
        FROM public.songs WHERE id = 'sn45-song') THEN
        RAISE EXCEPTION 'Legacy rows must keep the new columns NULL.';
    END IF;

    SELECT server_revision INTO revision_before
    FROM public.songs WHERE id = 'sn45-song';

    UPDATE public.songs
    SET edition_memberships = '[{"album_edition_id":"sn45-standard","disc_number":1,"track_number":1,"sort_position":0,"numbering_authority":"inferred","ordering_authority":"inferred"}]',
        artist_credits = '[{"id":"c1","artist_id":"sn45-artist","credited_name":"Artist","canonical_credited_name":"artist","role":"primary","position":0}]'
    WHERE id = 'sn45-song';

    SELECT server_revision INTO revision_after
    FROM public.songs WHERE id = 'sn45-song';

    IF revision_after <> revision_before + 1 THEN
        RAISE EXCEPTION 'Writing the new columns must advance server_revision.';
    END IF;

    -- An update that leaves the columns out keeps them.
    UPDATE public.songs SET title = 'Song (renamed)' WHERE id = 'sn45-song';

    IF (SELECT jsonb_array_length(edition_memberships)
        FROM public.songs WHERE id = 'sn45-song') <> 1 THEN
        RAISE EXCEPTION 'Updates without the columns must not clear them.';
    END IF;

    BEGIN
        UPDATE public.songs SET artist_credits = '{"not":"an array"}'
        WHERE id = 'sn45-song';
        RAISE EXCEPTION 'A non-array credit list must be refused.';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END
$test$;

ROLLBACK;
