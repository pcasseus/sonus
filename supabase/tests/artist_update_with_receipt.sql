-- SN-41A.3.2C: Receipt-aware artist update behavior.
-- Transaction boundaries are supplied by the test runner.
-- Requires migrations 20261017000003 and 20261017000004.

SELECT
    gen_random_uuid() AS owner_id,
    gen_random_uuid() AS other_id
\gset

INSERT INTO auth.users (id)
VALUES (:'owner_id'::uuid), (:'other_id'::uuid);

INSERT INTO public.artists (
    id, user_id, name, canonical_name,
    is_blacklisted, created_at, updated_at
)
VALUES (
    'sn41-receipt-update-test',
    :'owner_id'::uuid,
    'Original Artist',
    'original artist',
    true,
    now(),
    now()
);

SELECT set_config('sn41.owner_id', :'owner_id', true);
SELECT set_config('sn41.other_id', :'other_id', true);

-- Verify the RPC privilege boundary before assuming the client role.
DO $test$
BEGIN
    IF has_function_privilege(
        'anon',
        'public.update_artist_record_with_receipt(
            text,bigint,text,bigint,text,text,text,text,
            jsonb,timestamptz
        )',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'Anonymous execution must be denied';
    END IF;

    RAISE NOTICE 'PASS: Anonymous execution denied';
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
    -- First write: revision 1 -> 2.
    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_with_receipt(
        'sn41-receipt-update-test',
        1,
        'sn41-outbox-a',
        3,
        'Updated Artist',
        'updated artist',
        NULL,
        NULL,
        '[]'::jsonb,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'applied'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Expected applied/2, got %/%',
            v_outcome, v_revision;
    END IF;

    RAISE NOTICE 'PASS: Initial update applied at revision 2';

    -- Verify receipt persisted atomically with the update.
    IF NOT EXISTS (
        SELECT 1
        FROM public.artists
        WHERE id = 'sn41-receipt-update-test'
          AND name = 'Updated Artist'
          AND is_blacklisted = true
          AND server_revision = 2
          AND last_write_outbox_id = 'sn41-outbox-a'
          AND last_write_mutation_revision = 3
          AND last_write_server_revision = 2
    ) THEN
        RAISE EXCEPTION 'Artist update or receipt is incorrect';
    END IF;

    RAISE NOTICE 'PASS: Receipt and artist data persisted together';
    RAISE NOTICE 'PASS: Blacklist state preserved';

    -- Simulate a successful upload whose response was lost.
    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_with_receipt(
        'sn41-receipt-update-test',
        1,
        'sn41-outbox-a',
        3,
        'Updated Artist',
        'updated artist',
        NULL,
        NULL,
        '[]'::jsonb,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'replayed'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Expected replayed/2, got %/%',
            v_outcome, v_revision;
    END IF;

    RAISE NOTICE 'PASS: Exact mutation identity recognized on retry';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-receipt-update-test'
          AND server_revision = 2
    ) THEN
        RAISE EXCEPTION 'Replay unexpectedly advanced server revision';
    END IF;

    RAISE NOTICE 'PASS: Replay did not advance revision';

    -- Identical mutation identity with different payload is NOT a replay.
    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_with_receipt(
        'sn41-receipt-update-test',
        1,
        'sn41-outbox-a',
        3,
        'Changed Retry Payload',
        'changed retry payload',
        NULL,
        NULL,
        '[]'::jsonb,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION
            'Changed payload incorrectly accepted as replay: %/%',
            v_outcome, v_revision;
    END IF;

    RAISE NOTICE 'PASS: Changed replay payload rejected';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-receipt-update-test'
          AND name = 'Updated Artist'
          AND server_revision = 2
    ) THEN
        RAISE EXCEPTION 'Changed retry damaged stored artist';
    END IF;

    RAISE NOTICE 'PASS: Changed retry preserved cloud data';

    -- Same outbox ID, different mutation revision.
    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_with_receipt(
        'sn41-receipt-update-test',
        1,
        'sn41-outbox-a',
        4,
        'Wrong Mutation',
        'wrong mutation',
        NULL,
        NULL,
        NULL,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Different mutation revision was accepted';
    END IF;

    RAISE NOTICE 'PASS: Different mutation revision rejected';

    -- Different outbox ID.
    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_with_receipt(
        'sn41-receipt-update-test',
        1,
        'sn41-outbox-b',
        3,
        'Wrong Outbox',
        'wrong outbox',
        NULL,
        NULL,
        NULL,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Different outbox identity was accepted';
    END IF;

    RAISE NOTICE 'PASS: Different outbox ID rejected';

    -- Reusing the identity with a different expected revision
    -- must not be recognized as a replay.
    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_with_receipt(
        'sn41-receipt-update-test',
        3,
        'sn41-outbox-a',
        3,
        'Wrong Expected Revision',
        'wrong expected revision',
        NULL,
        NULL,
        NULL,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Wrong expected revision was accepted';
    END IF;

    RAISE NOTICE 'PASS: Wrong expected revision rejected';

    -- Another signed-in account must not see or update
    -- the owner's artist.
    PERFORM set_config(
        'request.jwt.claim.sub',
        current_setting('sn41.other_id'),
        true
    );

    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_with_receipt(
        'sn41-receipt-update-test',
        2,
        'sn41-foreign-outbox',
        1,
        'Foreign Update',
        'foreign update',
        NULL,
        NULL,
        NULL,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'not_found'
       OR v_revision IS NOT NULL THEN
        RAISE EXCEPTION 'Cross-account ownership isolation failed';
    END IF;

    RAISE NOTICE 'PASS: Cross-account update denied';

    -- Restore the original owner.
    PERFORM set_config(
        'request.jwt.claim.sub',
        current_setting('sn41.owner_id'),
        true
    );

    -- Another valid write advances revision 2 -> 3.
    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_with_receipt(
        'sn41-receipt-update-test',
        2,
        'sn41-outbox-b',
        1,
        'Newer Artist',
        'newer artist',
        NULL,
        NULL,
        NULL,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'applied'
       OR v_revision IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION 'Expected competing write applied/3';
    END IF;

    RAISE NOTICE 'PASS: Newer mutation advanced cloud revision';

    -- A formerly successful mutation is no longer the
    -- latest server write and cannot be replay-acknowledged.
    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_with_receipt(
        'sn41-receipt-update-test',
        1,
        'sn41-outbox-a',
        3,
        'Updated Artist',
        'updated artist',
        NULL,
        NULL,
        '[]'::jsonb,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 3 THEN
        RAISE EXCEPTION 'Obsolete receipt was incorrectly replayed';
    END IF;

    RAISE NOTICE 'PASS: Obsolete receipt cannot replay';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-receipt-update-test'
          AND name = 'Newer Artist'
          AND server_revision = 3
    ) THEN
        RAISE EXCEPTION 'Conflict overwrote newer cloud data';
    END IF;

    RAISE NOTICE 'PASS: Newer cloud data preserved';

    -- Tombstone the artist to check that updates cannot revive it.
    UPDATE public.artists
    SET deleted_at = now()
    WHERE id = 'sn41-receipt-update-test';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-receipt-update-test'
          AND server_revision = 4
          AND deleted_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Tombstone setup failed';
    END IF;

    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.update_artist_record_with_receipt(
        'sn41-receipt-update-test',
        4,
        'sn41-outbox-c',
        1,
        'Revived Artist',
        'revived artist',
        NULL,
        NULL,
        NULL,
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 4 THEN
        RAISE EXCEPTION 'Deleted artist was incorrectly updated';
    END IF;

    RAISE NOTICE 'PASS: Deleted artist cannot be revived';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-receipt-update-test'
          AND name = 'Newer Artist'
          AND server_revision = 4
          AND deleted_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Deleted artist contents were modified';
    END IF;

    RAISE NOTICE 'PASS: Tombstone remains intact';
END;
$test$;