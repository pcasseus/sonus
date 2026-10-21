\set ON_ERROR_STOP on

BEGIN;

-- Generate two independent test accounts.
SELECT
    gen_random_uuid() AS owner_id,
    gen_random_uuid() AS other_id
\gset

-- Seed test data using the database administrator.
INSERT INTO auth.users (id)
VALUES (:'owner_id'::uuid), (:'other_id'::uuid);

INSERT INTO public.artists (
    id,
    user_id,
    name,
    canonical_name,
    created_at,
    updated_at
)
VALUES (
    'sn41-conditional-artist',
    :'owner_id'::uuid,
    'Original Artist',
    'original artist',
    now(),
    now()
);

-- Preserve generated IDs in transaction-local settings.
SELECT set_config('sn41.owner_id', :'owner_id', true);
SELECT set_config('sn41.other_id', :'other_id', true);

-- All subsequent calls execute as an authenticated user.
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
    -- Matching revision should succeed.
    SELECT outcome, server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_name_if_revision(
        'sn41-conditional-artist',
        1,
        'Updated Artist',
        'updated artist',
        now()
    );

    IF v_outcome IS DISTINCT FROM 'applied'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION
            'Expected applied/2, got %/%',
            v_outcome, v_revision;
    END IF;

    RAISE NOTICE 'PASS: Matching revision applies update';

    -- Stale revision must not overwrite the current record.
    SELECT outcome, server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_name_if_revision(
        'sn41-conditional-artist',
        1,
        'Stale Artist',
        'stale artist',
        now()
    );

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION
            'Expected conflict/2, got %/%',
            v_outcome, v_revision;
    END IF;

    RAISE NOTICE 'PASS: Stale revision rejected';

    -- Confirm stale write did not change the record.
    IF NOT EXISTS (
        SELECT 1
        FROM public.artists
        WHERE id = 'sn41-conditional-artist'
          AND name = 'Updated Artist'
          AND server_revision = 2
    ) THEN
        RAISE EXCEPTION
            'Stale write modified the artist';
    END IF;

    RAISE NOTICE 'PASS: Stale write preserves current data';

    -- Simulate switching to a different signed-in account.
    PERFORM set_config(
        'request.jwt.claim.sub',
        current_setting('sn41.other_id'),
        true
    );

    SELECT outcome, server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_name_if_revision(
        'sn41-conditional-artist',
        2,
        'Unauthorized Artist',
        'unauthorized artist',
        now()
    );

    IF v_outcome IS DISTINCT FROM 'not_found'
       OR v_revision IS NOT NULL THEN
        RAISE EXCEPTION
            'Cross-account access not isolated: %/%',
            v_outcome, v_revision;
    END IF;

    RAISE NOTICE 'PASS: Cross-account update blocked';

    -- Return to the record owner.
    PERFORM set_config(
        'request.jwt.claim.sub',
        current_setting('sn41.owner_id'),
        true
    );

    SELECT outcome, server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_name_if_revision(
        'sn41-conditional-artist',
        2,
        'Final Artist',
        'final artist',
        now()
    );

    IF v_outcome IS DISTINCT FROM 'applied'
       OR v_revision IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION
            'Expected applied/3, got %/%',
            v_outcome, v_revision;
    END IF;

    RAISE NOTICE 'PASS: Current revision updates successfully';
END;
$test$;

ROLLBACK;