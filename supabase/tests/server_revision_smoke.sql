BEGIN;

DO $test$
DECLARE
    v_user_id uuid := gen_random_uuid();
    v_artist_id text := 'sn41-revision-smoke-test';
    v_revision bigint;
BEGIN
    INSERT INTO auth.users (id)
    VALUES (v_user_id);

    INSERT INTO public.artists (
        id,
        user_id,
        name,
        canonical_name,
        created_at,
        updated_at,
        server_revision
    )
    VALUES (
        v_artist_id,
        v_user_id,
        'Revision Test Artist',
        'revision test artist',
        now(),
        now(),
        999
    )
    RETURNING server_revision INTO v_revision;

    IF v_revision <> 1 THEN
        RAISE EXCEPTION
            'INSERT failed: expected revision 1, got %',
            v_revision;
    END IF;

    RAISE NOTICE 'PASS: Insert forces revision 1';

    UPDATE public.artists
    SET name = 'Updated Artist'
    WHERE id = v_artist_id
    RETURNING server_revision INTO v_revision;

    IF v_revision <> 2 THEN
        RAISE EXCEPTION
            'UPDATE failed: expected revision 2, got %',
            v_revision;
    END IF;

    RAISE NOTICE 'PASS: First update advances to revision 2';

    UPDATE public.artists
    SET server_revision = 500
    WHERE id = v_artist_id
    RETURNING server_revision INTO v_revision;

    IF v_revision <> 3 THEN
        RAISE EXCEPTION
            'Revision protection failed: expected 3, got %',
            v_revision;
    END IF;

    RAISE NOTICE 'PASS: Client cannot force revision 500';

    UPDATE public.artists
    SET name = 'Final Artist Name'
    WHERE id = v_artist_id
    RETURNING server_revision INTO v_revision;

    IF v_revision <> 4 THEN
        RAISE EXCEPTION
            'Final update failed: expected 4, got %',
            v_revision;
    END IF;

    RAISE NOTICE 'PASS: Subsequent update advances to revision 4';
END;
$test$;

ROLLBACK;