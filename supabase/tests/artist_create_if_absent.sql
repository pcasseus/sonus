\set ON_ERROR_STOP on

BEGIN;

SELECT
    gen_random_uuid() AS owner_id,
    gen_random_uuid() AS other_id
\gset

INSERT INTO auth.users (id)
VALUES (:'owner_id'::uuid), (:'other_id'::uuid);

INSERT INTO public.artists (
    id, user_id, name, canonical_name, created_at, updated_at
)
VALUES (
    'sn41-create-foreign',
    :'other_id'::uuid,
    'Foreign Artist',
    'foreign artist',
    now(),
    now()
);

DO $test$
BEGIN
    IF has_function_privilege(
        'anon',
        'public.create_artist_if_absent(text,text,text,text,text,jsonb,timestamptz,timestamptz)',
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
    :'owner_id',
    true
);

DO $test$
DECLARE
    v_outcome text;
    v_revision bigint;
BEGIN
    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.create_artist_if_absent(
        'sn41-create-artist',
        'Original Artist',
        'original artist',
        NULL,
        NULL,
        '[]'::jsonb,
        now(),
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'applied'
       OR v_revision IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Expected applied/1, got %/%',
            v_outcome, v_revision;
    END IF;

    RAISE NOTICE 'PASS: New artist created at revision 1';

    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.create_artist_if_absent(
        'sn41-create-artist',
        'Overwrite Attempt',
        'overwrite attempt',
        NULL,
        NULL,
        NULL,
        now(),
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'conflict'
       OR v_revision IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Existing artist should conflict';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.artists
        WHERE id = 'sn41-create-artist'
          AND name = 'Original Artist'
          AND server_revision = 1
    ) THEN
        RAISE EXCEPTION 'Duplicate creation overwrote existing artist';
    END IF;

    RAISE NOTICE 'PASS: Duplicate cannot overwrite artist';

    SELECT r.outcome, r.server_revision
    INTO v_outcome, v_revision
    FROM public.create_artist_if_absent(
        'sn41-create-foreign',
        'Cross Account Attempt',
        'cross account attempt',
        NULL,
        NULL,
        NULL,
        now(),
        now()
    ) AS r;

    IF v_outcome IS DISTINCT FROM 'not_found'
       OR v_revision IS NOT NULL THEN
        RAISE EXCEPTION 'Foreign artist creation leaked ownership';
    END IF;

    RAISE NOTICE 'PASS: Cross-account collision cannot overwrite';
END;
$test$;

ROLLBACK;