-- SN-41A.3.2C: Receipt-aware artist creation regression.
-- Runner supplies BEGIN and ROLLBACK.

SELECT gen_random_uuid() AS owner_id,
       gen_random_uuid() AS other_id
\gset

INSERT INTO auth.users (id)
VALUES (:'owner_id'::uuid), (:'other_id'::uuid);

SELECT set_config('sn41.owner_id', :'owner_id', true);
SELECT set_config('sn41.other_id', :'other_id', true);

DO $test$
BEGIN
    IF has_function_privilege(
        'anon',
        'public.create_artist_with_receipt(text,text,bigint,text,text,text,text,jsonb,timestamptz,timestamptz)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'Anonymous creation RPC access allowed';
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
    v_created timestamptz := '2026-10-17T10:00:00Z';
    v_updated timestamptz := '2026-10-17T10:01:00Z';
BEGIN
    -- First creation.
    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.create_artist_with_receipt(
        'sn41-receipt-create-test',
        'sn41-create-outbox-a',
        3,
        'Original Artist',
        'original artist',
        NULL,
        NULL,
        '[]'::jsonb,
        v_created,
        v_updated
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'applied'
       OR v_revision IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Expected applied/1, got %/%',
            v_outcome, v_revision;
    END IF;
    RAISE NOTICE 'PASS: First creation applied at revision 1';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-receipt-create-test'
          AND server_revision = 1
          AND last_write_outbox_id = 'sn41-create-outbox-a'
          AND last_write_mutation_revision = 3
          AND last_write_server_revision = 1
    ) THEN
        RAISE EXCEPTION 'Creation receipt was not stored';
    END IF;
    RAISE NOTICE 'PASS: Creation receipt stored atomically';

    -- Lost-response retry: exactly the same payload.
    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.create_artist_with_receipt(
        'sn41-receipt-create-test',
        'sn41-create-outbox-a',
        3,
        'Original Artist',
        'original artist',
        NULL,
        NULL,
        '[]'::jsonb,
        v_created,
        v_updated
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'replayed'
       OR v_revision IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Expected replayed/1, got %/%',
            v_outcome, v_revision;
    END IF;
    RAISE NOTICE 'PASS: Exact creation retry recognized';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-receipt-create-test'
          AND server_revision = 1
          AND name = 'Original Artist'
    ) THEN
        RAISE EXCEPTION 'Retry modified the original creation';
    END IF;
    RAISE NOTICE 'PASS: Retry did not increment revision';

    -- Same identity, altered artist payload.
    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.create_artist_with_receipt(
        'sn41-receipt-create-test',
        'sn41-create-outbox-a',
        3,
        'Changed Artist',
        'changed artist',
        NULL,
        NULL,
        '[]'::jsonb,
        v_created,
        v_updated
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Changed creation payload was accepted';
    END IF;
    RAISE NOTICE 'PASS: Changed payload rejected';

    -- Different outbox identity.
    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.create_artist_with_receipt(
        'sn41-receipt-create-test',
        'sn41-create-outbox-b',
        3,
        'Original Artist',
        'original artist',
        NULL,
        NULL,
        '[]'::jsonb,
        v_created,
        v_updated
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Different creation identity was accepted';
    END IF;
    RAISE NOTICE 'PASS: Different outbox ID rejected';

    -- Same outbox ID, different mutation revision.
    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.create_artist_with_receipt(
        'sn41-receipt-create-test',
        'sn41-create-outbox-a',
        4,
        'Original Artist',
        'original artist',
        NULL,
        NULL,
        '[]'::jsonb,
        v_created,
        v_updated
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Different mutation revision was accepted';
    END IF;
    RAISE NOTICE 'PASS: Different mutation revision rejected';

    -- Another account cannot view the receipt or revision.
    PERFORM set_config(
        'request.jwt.claim.sub',
        current_setting('sn41.other_id'),
        true
    );

    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.create_artist_with_receipt(
        'sn41-receipt-create-test',
        'sn41-create-outbox-a',
        3,
        'Original Artist',
        'original artist',
        NULL,
        NULL,
        '[]'::jsonb,
        v_created,
        v_updated
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'not_found'
       OR v_revision IS NOT NULL THEN
        RAISE EXCEPTION 'Cross-account creation collision leaked data';
    END IF;
    RAISE NOTICE 'PASS: Cross-account collision isolated';

    PERFORM set_config(
        'request.jwt.claim.sub',
        current_setting('sn41.owner_id'),
        true
    );

    -- A newer valid edit advances the artist to revision 2.
    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.update_artist_record_with_receipt(
        'sn41-receipt-create-test',
        1,
        'sn41-update-outbox',
        1,
        'Newer Artist',
        'newer artist',
        NULL,
        NULL,
        '[]'::jsonb,
        '2026-10-17T11:00:00Z'::timestamptz
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'applied'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Newer artist update failed';
    END IF;
    RAISE NOTICE 'PASS: Newer artist update applied';

    -- Original creation receipt must now be obsolete.
    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.create_artist_with_receipt(
        'sn41-receipt-create-test',
        'sn41-create-outbox-a',
        3,
        'Original Artist',
        'original artist',
        NULL,
        NULL,
        '[]'::jsonb,
        v_created,
        v_updated
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Obsolete creation incorrectly replayed';
    END IF;
    RAISE NOTICE 'PASS: Obsolete creation receipt rejected';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-receipt-create-test'
          AND name = 'Newer Artist'
          AND server_revision = 2
    ) THEN
        RAISE EXCEPTION 'Creation retry damaged newer cloud data';
    END IF;
    RAISE NOTICE 'PASS: Newer cloud data preserved';
END;
$test$;