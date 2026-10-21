-- SN-41A.3.2C: Receipt-aware, revision-conditional artist deletion.
--
-- Additive migration. Does not activate the final privilege cutover.
-- Soft deletion preserves the artist row and its related foreign keys.
--
-- A retry is recognized only if this precise deletion remains
-- the most recent successful mutation of the artist.

CREATE FUNCTION public.delete_artist_with_receipt(
    p_artist_id text,
    p_expected_revision bigint,
    p_outbox_id text,
    p_mutation_revision bigint,
    p_deleted_at timestamptz
)
RETURNS TABLE (
    outcome text,
    server_revision bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
    v_user_id uuid;
    v_revision bigint;
    v_record record;
BEGIN
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required'
            USING ERRCODE = '28000';
    END IF;

    IF p_artist_id IS NULL
       OR length(trim(p_artist_id)) = 0
       OR p_expected_revision IS NULL
       OR p_expected_revision < 1
       OR p_expected_revision >= 9223372036854775807
       OR p_outbox_id IS NULL
       OR length(trim(p_outbox_id)) = 0
       OR p_mutation_revision IS NULL
       OR p_mutation_revision < 1
       OR p_deleted_at IS NULL THEN
        RAISE EXCEPTION 'Invalid receipt-aware artist deletion arguments'
            USING ERRCODE = '22023';
    END IF;

    -- Soft-delete only a live artist at the expected server revision.
    -- The revision trigger advances the server revision by exactly one.
    -- Record the deletion identity in the same atomic UPDATE.
    UPDATE public.artists AS a
    SET
        deleted_at = p_deleted_at,
        updated_at = p_deleted_at,
        last_write_outbox_id = p_outbox_id,
        last_write_mutation_revision = p_mutation_revision,
        last_write_server_revision = p_expected_revision + 1
    WHERE a.id = p_artist_id
      AND a.user_id = v_user_id
      AND a.deleted_at IS NULL
      AND a.server_revision = p_expected_revision
    RETURNING a.server_revision INTO v_revision;

    IF FOUND THEN
        IF v_revision <> p_expected_revision + 1 THEN
            RAISE EXCEPTION 'Unexpected artist deletion server revision';
        END IF;

        RETURN QUERY SELECT 'applied'::text, v_revision;
        RETURN;
    END IF;

    -- Lock the current record before deciding whether this was
    -- a previously successful deletion with a lost response.
    SELECT
        a.server_revision,
        a.last_write_outbox_id,
        a.last_write_mutation_revision,
        a.last_write_server_revision,
        a.deleted_at,
        a.updated_at
    INTO v_record
    FROM public.artists AS a
    WHERE a.id = p_artist_id
      AND a.user_id = v_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Do not disclose another account's cloud revision.
        RETURN QUERY SELECT 'not_found'::text, NULL::bigint;
        RETURN;
    END IF;

    IF v_record.deleted_at IS NOT DISTINCT FROM p_deleted_at
       AND v_record.deleted_at IS NOT NULL
       AND v_record.updated_at IS NOT DISTINCT FROM p_deleted_at
       AND v_record.last_write_outbox_id = p_outbox_id
       AND v_record.last_write_mutation_revision = p_mutation_revision
       AND v_record.last_write_server_revision = v_record.server_revision
       AND v_record.server_revision = p_expected_revision + 1 THEN
        RETURN QUERY
            SELECT 'replayed'::text, v_record.server_revision;
        RETURN;
    END IF;

    RETURN QUERY
        SELECT 'conflict'::text, v_record.server_revision;
END;
$function$;

REVOKE ALL ON FUNCTION public.delete_artist_with_receipt(
    text, bigint, text, bigint, timestamptz
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.delete_artist_with_receipt(
    text, bigint, text, bigint, timestamptz
) TO authenticated;