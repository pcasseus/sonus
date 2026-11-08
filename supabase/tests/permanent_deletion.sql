\set ON_ERROR_STOP on

-- App Update 1.2 (migration 20261108000001). Run against a throwaway
-- database with every migration applied, never production. Each block
-- rolls back.

BEGIN;

DO $test$
DECLARE
    v_user uuid := gen_random_uuid();
    v_caps text[];
BEGIN
    INSERT INTO auth.users (id) VALUES (v_user);

    -- The capability probe.
    SELECT public.sonus_capabilities() INTO v_caps;
    IF NOT ('permanent_deletion_v1' = ANY (v_caps)) THEN
        RAISE EXCEPTION 'FAIL capability missing';
    END IF;
    RAISE NOTICE 'PASS capability';

    -- A library tombstone is final.
    INSERT INTO public.artists (
        id, user_id, name, canonical_name, created_at, updated_at
    ) VALUES ('pd-artist', v_user, 'A', 'a', now(), now());
    UPDATE public.artists SET deleted_at = now()
        WHERE id = 'pd-artist' AND user_id = v_user;
    BEGIN
        UPDATE public.artists SET deleted_at = NULL
            WHERE id = 'pd-artist' AND user_id = v_user;
        RAISE EXCEPTION 'FAIL library tombstone revived';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS library tombstone is final';
    END;
    -- Other updates of a tombstone (a later delete time) still work.
    UPDATE public.artists SET deleted_at = now() + interval '1 second'
        WHERE id = 'pd-artist' AND user_id = v_user;
    RAISE NOTICE 'PASS tombstone may be re-stamped';

    -- The new kind is accepted.
    INSERT INTO public.sonus_archive_records (
        user_id, kind, record_key, payload, client_updated_at
    ) VALUES (
        v_user, 'library_deletion', 'deletion_1',
        '{"operation":"userDeletion","entries":[["song","s1"]]}', now()
    );
    RAISE NOTICE 'PASS library_deletion kind';

    -- A deletion record is permanent.
    BEGIN
        UPDATE public.sonus_archive_records
            SET is_deleted = true, payload = '{}'
            WHERE user_id = v_user AND kind = 'library_deletion';
        RAISE EXCEPTION 'FAIL deletion record removed';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS deletion record is permanent';
    END;

    -- A deleted history record keeps no content and stays deleted.
    INSERT INTO public.sonus_archive_records (
        user_id, kind, record_key, payload, client_updated_at
    ) VALUES (
        v_user, 'listening_session', 'session_1',
        '{"session":{"song_title":"Deleted song"}}', now()
    );
    BEGIN
        UPDATE public.sonus_archive_records SET is_deleted = true
            WHERE user_id = v_user AND record_key = 'session_1';
        RAISE EXCEPTION 'FAIL deleted session kept its content';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'PASS deleted history keeps no content';
    END;
    UPDATE public.sonus_archive_records
        SET is_deleted = true, payload = '{}'
        WHERE user_id = v_user AND record_key = 'session_1';
    BEGIN
        UPDATE public.sonus_archive_records
            SET is_deleted = false,
                payload = '{"session":{"song_title":"Deleted song"}}'
            WHERE user_id = v_user AND record_key = 'session_1';
        RAISE EXCEPTION 'FAIL deleted session revived';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS deleted history is final';
    END;

    -- Mutable kinds keep today's rules (existing clients unaffected).
    INSERT INTO public.sonus_archive_records (
        user_id, kind, record_key, payload, client_updated_at
    ) VALUES (v_user, 'playlist', 'pl_1', '{"name":"Road"}', now());
    UPDATE public.sonus_archive_records SET is_deleted = true
        WHERE user_id = v_user AND record_key = 'pl_1';
    UPDATE public.sonus_archive_records SET is_deleted = false
        WHERE user_id = v_user AND record_key = 'pl_1';
    RAISE NOTICE 'PASS mutable kinds unchanged';
END;
$test$;

ROLLBACK;
