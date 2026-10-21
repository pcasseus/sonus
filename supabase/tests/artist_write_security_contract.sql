-- SN-41A.3.2C: Artist write security regression contract.
--
-- Run after the guarded artist RPC and permission migrations.
-- This test documents the desired security configuration.
-- It is expected to fail against the current baseline.
--
-- Read-only assertions. No persistent data modifications.

DO $test$
DECLARE
    v_column text;
    v_rpc text;
    v_function oid;
BEGIN
    -- Reading owned artist records must remain possible.
    IF NOT has_table_privilege(
        'authenticated', 'public.artists', 'SELECT'
    ) THEN
        RAISE EXCEPTION 'Authenticated artist SELECT is required';
    END IF;

    -- Direct client writes must not bypass guarded RPCs.
    IF has_table_privilege(
        'authenticated', 'public.artists', 'INSERT'
    ) THEN
        RAISE EXCEPTION 'Unsafe direct artist INSERT remains granted';
    END IF;

    IF has_table_privilege(
        'authenticated', 'public.artists', 'UPDATE'
    ) THEN
        RAISE EXCEPTION 'Unsafe direct artist UPDATE remains granted';
    END IF;

    -- No column-level write grants may bypass the table revocation.
    FOR v_column IN
        SELECT a.attname
        FROM pg_attribute AS a
        WHERE a.attrelid = 'public.artists'::regclass
          AND a.attnum > 0
          AND NOT a.attisdropped
    LOOP
        IF has_column_privilege(
            'authenticated',
            'public.artists',
            v_column,
            'UPDATE'
        ) THEN
            RAISE EXCEPTION
                'Direct UPDATE privilege remains on %', v_column;
        END IF;
    END LOOP;

    -- Guarded routines must remain executable by authenticated users.
    FOREACH v_rpc IN ARRAY ARRAY[
        'create_artist_if_absent',
        'update_artist_record_if_revision'
    ]
    LOOP
        SELECT p.oid
        INTO v_function
        FROM pg_proc AS p
        JOIN pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = v_rpc
        LIMIT 1;

        IF v_function IS NULL THEN
            RAISE EXCEPTION 'Missing guarded RPC: %', v_rpc;
        END IF;

        IF NOT has_function_privilege(
            'authenticated',
            v_function,
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'Authenticated execution missing: %', v_rpc;
        END IF;

        IF has_function_privilege(
            'anon',
            v_function,
            'EXECUTE'
        ) THEN
            RAISE EXCEPTION
                'Anonymous execution unexpectedly granted: %', v_rpc;
        END IF;
    END LOOP;

    -- Artist ownership isolation must remain enabled.
    IF NOT (
        SELECT relrowsecurity
        FROM pg_class
        WHERE oid = 'public.artists'::regclass
    ) THEN
        RAISE EXCEPTION 'Artist RLS is disabled';
    END IF;

    RAISE NOTICE 'PASS: Artist direct-write security contract';
END;
$test$;