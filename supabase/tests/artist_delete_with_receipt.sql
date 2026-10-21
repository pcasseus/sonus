-- SN-41A.3.2C: Receipt-aware artist deletion.
-- Runner supplies BEGIN and ROLLBACK.

SELECT gen_random_uuid() AS owner_id,
       gen_random_uuid() AS other_id
\gset

INSERT INTO auth.users (id)
VALUES (:'owner_id'::uuid), (:'other_id'::uuid);

SELECT set_config('sn41.delete_owner', :'owner_id', true);
SELECT set_config('sn41.delete_other', :'other_id', true);

INSERT INTO public.artists (
    id, user_id, name, canonical_name, is_blacklisted,
    created_at, updated_at, metadata_field_states
)
VALUES
(
    'sn41-delete-receipt-test',
    :'owner_id'::uuid,
    'Deletion Artist',
    'deletion artist',
    true,
    '2026-10-17T08:00:00Z',
    '2026-10-17T09:00:00Z',
    '[]'::jsonb
),
(
    'sn41-stale-delete-test',
    :'owner_id'::uuid,
    'Still Active',
    'still active',
    false,
    '2026-10-17T08:00:00Z',
    '2026-10-17T09:00:00Z',
    '[]'::jsonb
);

DO $test$
BEGIN
    IF has_function_privilege(
        'anon',
        'public.delete_artist_with_receipt(text,bigint,text,bigint,timestamptz)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'Anonymous artist deletion RPC is executable';
    END IF;

    RAISE NOTICE 'PASS: Anonymous deletion execution denied';
END;
$test$;

SET LOCAL ROLE authenticated;

SELECT set_config(
    'request.jwt.claim.sub',
    current_setting('sn41.delete_owner'),
    true
);

DO $test$
DECLARE
    v_outcome text;
    v_revision bigint;
    v_deleted_at timestamptz := '2026-10-17T12:00:00Z';
BEGIN
    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.delete_artist_with_receipt(
        'sn41-delete-receipt-test',
        1,
        'sn41-delete-outbox-a',
        3,
        v_deleted_at
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'applied'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'First deletion expected applied/2, got %/%',
            v_outcome, v_revision;
    END IF;
    RAISE NOTICE 'PASS: First deletion applied at revision 2';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-delete-receipt-test'
          AND deleted_at = v_deleted_at
          AND updated_at = v_deleted_at
          AND server_revision = 2
          AND last_write_outbox_id = 'sn41-delete-outbox-a'
          AND last_write_mutation_revision = 3
          AND last_write_server_revision = 2
    ) THEN
        RAISE EXCEPTION 'Tombstone or deletion receipt missing';
    END IF;
    RAISE NOTICE 'PASS: Tombstone and receipt persisted atomically';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-delete-receipt-test'
          AND name = 'Deletion Artist'
          AND canonical_name = 'deletion artist'
          AND is_blacklisted = true
          AND created_at = '2026-10-17T08:00:00Z'::timestamptz
          AND metadata_field_states = '[]'::jsonb
    ) THEN
        RAISE EXCEPTION 'Deletion changed protected artist fields';
    END IF;
    RAISE NOTICE 'PASS: Artist metadata and blacklist preserved';

    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.delete_artist_with_receipt(
        'sn41-delete-receipt-test',
        1,
        'sn41-delete-outbox-a',
        3,
        v_deleted_at
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'replayed'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Exact deletion retry expected replayed/2';
    END IF;
    RAISE NOTICE 'PASS: Exact deletion retry recognized';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-delete-receipt-test'
          AND server_revision = 2
    ) THEN
        RAISE EXCEPTION 'Replay advanced the server revision';
    END IF;
    RAISE NOTICE 'PASS: Replay did not increment revision';

    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.delete_artist_with_receipt(
        'sn41-delete-receipt-test',
        1,
        'sn41-delete-outbox-b',
        3,
        v_deleted_at
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Different outbox ID was accepted';
    END IF;
    RAISE NOTICE 'PASS: Different outbox ID rejected';

    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.delete_artist_with_receipt(
        'sn41-delete-receipt-test',
        1,
        'sn41-delete-outbox-a',
        4,
        v_deleted_at
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Different mutation revision was accepted';
    END IF;
    RAISE NOTICE 'PASS: Different mutation revision rejected';

    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.delete_artist_with_receipt(
        'sn41-delete-receipt-test',
        1,
        'sn41-delete-outbox-a',
        3,
        v_deleted_at + interval '1 minute'
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Changed deletion timestamp was accepted';
    END IF;
    RAISE NOTICE 'PASS: Changed deletion payload rejected';

    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.delete_artist_with_receipt(
        'sn41-delete-receipt-test',
        2,
        'sn41-delete-outbox-a',
        3,
        v_deleted_at
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Incorrect expected revision was accepted';
    END IF;
    RAISE NOTICE 'PASS: Wrong expected revision rejected';

    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.delete_artist_with_receipt(
        'sn41-no-such-artist',
        1,
        'sn41-delete-missing',
        1,
        v_deleted_at
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'not_found'
       OR v_revision IS NOT NULL THEN
        RAISE EXCEPTION 'Missing artist returned unexpected result';
    END IF;
    RAISE NOTICE 'PASS: Missing artist returns not_found';

    PERFORM set_config(
        'request.jwt.claim.sub',
        current_setting('sn41.delete_other'),
        true
    );

    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.delete_artist_with_receipt(
        'sn41-delete-receipt-test',
        1,
        'sn41-delete-outbox-a',
        3,
        v_deleted_at
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'not_found'
       OR v_revision IS NOT NULL THEN
        RAISE EXCEPTION 'Cross-account deletion exposed artist state';
    END IF;
    RAISE NOTICE 'PASS: Cross-account deletion isolated';

    PERFORM set_config(
        'request.jwt.claim.sub',
        current_setting('sn41.delete_owner'),
        true
    );

    -- Advance another artist with a newer valid edit.
    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.update_artist_record_with_receipt(
        'sn41-stale-delete-test',
        1,
        'sn41-newer-edit-outbox',
        1,
        'Newer Artist Name',
        'newer artist name',
        NULL,
        NULL,
        '[]'::jsonb,
        '2026-10-17T11:00:00Z'::timestamptz
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'applied'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Newer update failed before stale deletion test';
    END IF;
    RAISE NOTICE 'PASS: Newer artist edit applied';

    SELECT r.outcome, r.server_revision
      INTO v_outcome, v_revision
    FROM public.delete_artist_with_receipt(
        'sn41-stale-delete-test',
        1,
        'sn41-stale-delete-outbox',
        1,
        v_deleted_at
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'Stale deletion was accepted';
    END IF;
    RAISE NOTICE 'PASS: Stale deletion rejected';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-stale-delete-test'
          AND deleted_at IS NULL
          AND name = 'Newer Artist Name'
          AND server_revision = 2
    ) THEN
        RAISE EXCEPTION 'Stale deletion damaged newer cloud data';
    END IF;
    RAISE NOTICE 'PASS: Newer live artist preserved';

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-delete-receipt-test'
          AND deleted_at = v_deleted_at
          AND server_revision = 2
          AND last_write_outbox_id = 'sn41-delete-outbox-a'
    ) THEN
        RAISE EXCEPTION 'Rejected retries changed original tombstone';
    END IF;
    RAISE NOTICE 'PASS: Rejected retries preserved tombstone';
END;
$test$;