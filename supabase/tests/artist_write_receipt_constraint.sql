-- SN-41A.3.2C: Artist receipt consistency regression.
--
-- Requires the artist_write_receipt migration.
-- Uses a temporary table; does not modify real artist records.

CREATE TEMP TABLE artist_receipt_test (
    LIKE public.artists INCLUDING DEFAULTS INCLUDING CONSTRAINTS
) ON COMMIT DROP;

DO $test$
DECLARE
    v_count integer;
BEGIN
    -- An artist without a receipt is valid.
    INSERT INTO artist_receipt_test (
        id, user_id, name, canonical_name,
        created_at, updated_at
    )
    VALUES (
        'receipt-none',
        '00000000-0000-0000-0000-000000000001',
        'Test Artist', 'test artist',
        now(), now()
    );

    RAISE NOTICE 'PASS: Missing receipt accepted';

    -- A complete receipt is valid.
    INSERT INTO artist_receipt_test (
        id, user_id, name, canonical_name,
        created_at, updated_at,
        last_write_outbox_id,
        last_write_mutation_revision,
        last_write_server_revision
    )
    VALUES (
        'receipt-valid',
        '00000000-0000-0000-0000-000000000001',
        'Test Artist', 'test artist',
        now(), now(),
        'outbox-1', 3, 8
    );

    RAISE NOTICE 'PASS: Complete receipt accepted';

    -- A partial receipt must fail.
    BEGIN
        INSERT INTO artist_receipt_test (
            id, user_id, name, canonical_name,
            created_at, updated_at,
            last_write_outbox_id
        )
        VALUES (
            'receipt-partial',
            '00000000-0000-0000-0000-000000000001',
            'Test Artist', 'test artist',
            now(), now(),
            'outbox-2'
        );

        RAISE EXCEPTION 'FAIL: Partial receipt accepted'
            USING ERRCODE = 'P0001';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: Partial receipt rejected';
    END;

    -- A zero mutation revision must fail.
    BEGIN
        INSERT INTO artist_receipt_test (
            id, user_id, name, canonical_name,
            created_at, updated_at,
            last_write_outbox_id,
            last_write_mutation_revision,
            last_write_server_revision
        )
        VALUES (
            'receipt-zero',
            '00000000-0000-0000-0000-000000000001',
            'Test Artist', 'test artist',
            now(), now(),
            'outbox-3', 0, 8
        );

        RAISE EXCEPTION 'FAIL: Zero mutation revision accepted'
            USING ERRCODE = 'P0001';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: Zero mutation revision rejected';
    END;

    -- A blank outbox ID must fail.
    BEGIN
        INSERT INTO artist_receipt_test (
            id, user_id, name, canonical_name,
            created_at, updated_at,
            last_write_outbox_id,
            last_write_mutation_revision,
            last_write_server_revision
        )
        VALUES (
            'receipt-blank',
            '00000000-0000-0000-0000-000000000001',
            'Test Artist', 'test artist',
            now(), now(),
            '   ', 2, 8
        );

        RAISE EXCEPTION 'FAIL: Blank outbox ID accepted'
            USING ERRCODE = 'P0001';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: Blank outbox ID rejected';
    END;

    -- A zero server revision must fail.
    BEGIN
        INSERT INTO artist_receipt_test (
            id, user_id, name, canonical_name,
            created_at, updated_at,
            last_write_outbox_id,
            last_write_mutation_revision,
            last_write_server_revision
        )
        VALUES (
            'receipt-server-zero',
            '00000000-0000-0000-0000-000000000001',
            'Test Artist', 'test artist',
            now(), now(),
            'outbox-4', 2, 0
        );

        RAISE EXCEPTION 'FAIL: Zero server revision accepted'
            USING ERRCODE = 'P0001';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS: Zero server revision rejected';
    END;

    SELECT count(*) INTO v_count
    FROM artist_receipt_test;

    IF v_count <> 2 THEN
        RAISE EXCEPTION
            'Unexpected number of accepted rows: %', v_count;
    END IF;

    RAISE NOTICE 'PASS: Exactly two valid receipts accepted';
END;
$test$;