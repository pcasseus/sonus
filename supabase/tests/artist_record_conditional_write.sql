\set ON_ERROR_STOP on

BEGIN;

SELECT
    gen_random_uuid() AS owner_id,
    gen_random_uuid() AS other_id
\gset

INSERT INTO auth.users (id)
VALUES (:'owner_id'::uuid), (:'other_id'::uuid);

INSERT INTO public.artwork_assets (
    id, user_id, storage_object_key, created_at, updated_at
)
VALUES (
    'sn41-full-artist-artwork',
    :'owner_id'::uuid,
    'sn41/full-artist-artwork',
    now(),
    now()
);

INSERT INTO public.artists (
    id, user_id, name, canonical_name, is_blacklisted,
    created_at, updated_at, metadata_field_states
)
VALUES (
    'sn41-full-artist',
    :'owner_id'::uuid,
    'Original Artist',
    'original artist',
    true,
    now(),
    now(),
    '[{"field_name":"name","authority":"manual","source":"user","updated_at":"2026-10-17T00:00:00Z"}]'::jsonb
);

SELECT set_config('sn41.owner_id', :'owner_id', true);
SELECT set_config('sn41.other_id', :'other_id', true);

DO $test$
BEGIN
    IF has_function_privilege(
        'anon',
        'public.update_artist_record_if_revision(text,bigint,text,text,text,text,jsonb,timestamptz)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'Anonymous role may execute full artist RPC';
    END IF;
    RAISE NOTICE 'PASS: Anonymous RPC access denied';
END;
$test$;

SET LOCAL ROLE authenticated;

SELECT set_config(
    'request.jwt.claim.sub',
    current_setting('sn41.owner_id'),
    true
);

DO $test$
DECLARE
    v_outcome text;
    v_revision bigint;
BEGIN
    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_if_revision(
        'sn41-full-artist',
        1,
        'Updated Artist',
        'updated artist',
        'sn41-full-artist-artwork',
        NULL,
        '[{"field_name":"name","authority":"confirmed","source":"user","updated_at":"2026-10-17T01:00:00Z"}]'::jsonb,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'applied'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Expected applied/2, got %/%',
            v_outcome, v_revision;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-full-artist'
          AND name = 'Updated Artist'
          AND canonical_name = 'updated artist'
          AND header_artwork_id = 'sn41-full-artist-artwork'
          AND top_artists_artwork_id IS NULL
          AND metadata_field_states->0->>'authority' = 'confirmed'
          AND is_blacklisted = true
          AND deleted_at IS NULL
          AND server_revision = 2
    ) THEN
        RAISE EXCEPTION 'Full artist payload or preserved fields incorrect';
    END IF;

    RAISE NOTICE 'PASS: Complete artist update applied';
    RAISE NOTICE 'PASS: Blacklist state preserved';

    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_if_revision(
        'sn41-full-artist',
        1,
        'Stale Artist',
        'stale artist',
        NULL,
        NULL,
        '[]'::jsonb,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Expected conflict/2, got %/%',
            v_outcome, v_revision;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-full-artist'
          AND name = 'Updated Artist'
          AND header_artwork_id = 'sn41-full-artist-artwork'
          AND server_revision = 2
    ) THEN
        RAISE EXCEPTION 'Stale write damaged the artist';
    END IF;

    RAISE NOTICE 'PASS: Stale write preserved full artist data';

    PERFORM set_config(
        'request.jwt.claim.sub',
        current_setting('sn41.other_id'),
        true
    );

    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_if_revision(
        'sn41-full-artist',
        2,
        'Wrong Owner',
        'wrong owner',
        NULL,
        NULL,
        NULL,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'not_found'
       OR v_revision IS NOT NULL THEN
        RAISE EXCEPTION 'Cross-account update was not isolated';
    END IF;

    RAISE NOTICE 'PASS: Cross-account isolation';

    PERFORM set_config(
        'request.jwt.claim.sub',
        current_setting('sn41.owner_id'),
        true
    );

    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_if_revision(
        'sn41-full-artist',
        2,
        'Final Artist',
        'final artist',
        NULL,
        NULL,
        NULL,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'applied'
       OR v_revision IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION 'Expected applied/3, got %/%',
            v_outcome, v_revision;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-full-artist'
          AND header_artwork_id IS NULL
          AND metadata_field_states IS NULL
          AND is_blacklisted = true
          AND server_revision = 3
    ) THEN
        RAISE EXCEPTION 'Nullable artist fields were not updated correctly';
    END IF;

    RAISE NOTICE 'PASS: Nullable artwork and metadata supported';
END;
$test$;

ROLLBACK;