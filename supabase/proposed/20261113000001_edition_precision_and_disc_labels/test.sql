\set ON_ERROR_STOP on

-- PROPOSED migration 20261113000001: run against an isolated local Supabase
-- after migration.sql. Never against staging or production without an
-- approved rehearsal. Everything is rolled back at the end.

BEGIN;

SELECT gen_random_uuid() AS owner_id \gset

INSERT INTO auth.users (id) VALUES (:'owner_id'::uuid);
SELECT set_config('test.owner', :'owner_id', true);

INSERT INTO public.artists (id, user_id, name, canonical_name, created_at, updated_at)
VALUES ('p12-artist', :'owner_id'::uuid, 'Artist', 'artist', now(), now());

INSERT INTO public.albums (id, user_id, artist_id, title, canonical_title, created_at, updated_at)
VALUES ('p12-album', :'owner_id'::uuid, 'p12-artist', 'Album', 'album', now(), now());

-- An older app writes an edition without the new columns.
INSERT INTO public.album_editions (
    id, user_id, album_id, title, type, is_primary, release_date,
    created_at, updated_at
)
VALUES (
    'p12-standard', :'owner_id'::uuid, 'p12-album', 'Standard', 'standard',
    true, '2019-01-01T00:00:00Z', now(), now()
);

DO $test$
DECLARE
    revision_before bigint;
    revision_after bigint;
BEGIN
    IF (SELECT release_date_partial IS NOT NULL OR disc_labels IS NOT NULL
        FROM public.album_editions WHERE id = 'p12-standard') THEN
        RAISE EXCEPTION 'Rows written without the columns must keep NULL.';
    END IF;

    -- A newer app writes a year-only date and disc names.
    SELECT server_revision INTO revision_before
    FROM public.album_editions WHERE id = 'p12-standard';

    INSERT INTO public.album_editions (
        id, user_id, album_id, title, type, is_primary, release_date,
        release_date_partial, disc_labels, created_at, updated_at
    )
    VALUES (
        'p12-standard', current_setting('test.owner')::uuid, 'p12-album',
        'Standard', 'standard', true, '2019-01-01T00:00:00Z', '2019',
        '{"2": "Bonus Tracks"}', now(), now()
    )
    ON CONFLICT (id) DO UPDATE
    SET release_date = excluded.release_date,
        release_date_partial = excluded.release_date_partial,
        disc_labels = excluded.disc_labels,
        updated_at = excluded.updated_at;

    SELECT server_revision INTO revision_after
    FROM public.album_editions WHERE id = 'p12-standard';
    IF revision_after IS NOT DISTINCT FROM revision_before THEN
        RAISE EXCEPTION 'Writing the new columns must advance the revision.';
    END IF;

    -- An older app then updates the edition, naming only its own columns
    -- (as PostgREST upserts do): the disc names stay, and the partial now
    -- disagrees with the new date, so apps ignore it.
    INSERT INTO public.album_editions (
        id, user_id, album_id, title, type, is_primary, release_date,
        created_at, updated_at
    )
    VALUES (
        'p12-standard', current_setting('test.owner')::uuid, 'p12-album',
        'Standard', 'standard', true, '2019-03-15T00:00:00Z', now(), now()
    )
    ON CONFLICT (id) DO UPDATE
    SET release_date = excluded.release_date,
        updated_at = excluded.updated_at;

    IF (SELECT disc_labels <> '{"2": "Bonus Tracks"}'::jsonb
        FROM public.album_editions WHERE id = 'p12-standard') THEN
        RAISE EXCEPTION 'An older app must never erase disc names.';
    END IF;
    IF (SELECT release_date_partial <> '2019'
        FROM public.album_editions WHERE id = 'p12-standard') THEN
        RAISE EXCEPTION 'An older app leaves the partial as it was.';
    END IF;

    -- Malformed values are refused.
    BEGIN
        UPDATE public.album_editions SET release_date_partial = '19'
        WHERE id = 'p12-standard';
        RAISE EXCEPTION 'A malformed partial date was accepted.';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.album_editions SET disc_labels = '{"0": "Zero"}'
        WHERE id = 'p12-standard';
        RAISE EXCEPTION 'Disc 0 was accepted.';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.album_editions SET disc_labels = '{"2": "  "}'
        WHERE id = 'p12-standard';
        RAISE EXCEPTION 'A blank disc name was accepted.';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE public.album_editions SET disc_labels = '["Bonus"]'
        WHERE id = 'p12-standard';
        RAISE EXCEPTION 'A disc name list was accepted.';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- No names is an empty object, distinct from "not provided".
    UPDATE public.album_editions SET disc_labels = '{}'
    WHERE id = 'p12-standard';
END
$test$;

ROLLBACK;
