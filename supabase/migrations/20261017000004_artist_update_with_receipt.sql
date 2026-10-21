-- SN-41A.3.2C: Receipt-aware artist conditional update.
--
-- Requires 20261017000003_artist_write_receipt.sql.
-- Additive RPC: existing RPC names and production wiring are unchanged.
-- Does not activate final privilege cutover.
--
-- SECURITY DEFINER is intentional: future authenticated clients will
-- not have direct artist UPDATE privileges.
--
-- Every write is explicitly restricted to auth.uid().
-- The function uses a fixed empty search_path and qualified relations.

CREATE FUNCTION public.update_artist_record_with_receipt(
    p_artist_id text,
    p_expected_revision bigint,
    p_outbox_id text,
    p_mutation_revision bigint,
    p_name text,
    p_canonical_name text,
    p_header_artwork_id text,
    p_top_artists_artwork_id text,
    p_metadata_field_states jsonb,
    p_updated_at timestamptz
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

    IF p_artist_id IS NULL OR length(trim(p_artist_id)) = 0
       OR p_expected_revision IS NULL
       OR p_expected_revision < 1
       OR p_expected_revision >= 9223372036854775807
       OR p_outbox_id IS NULL
       OR length(trim(p_outbox_id)) = 0
       OR p_mutation_revision IS NULL
       OR p_mutation_revision < 1
       OR p_name IS NULL OR length(trim(p_name)) = 0
       OR p_canonical_name IS NULL
       OR length(trim(p_canonical_name)) = 0
       OR p_updated_at IS NULL THEN
        RAISE EXCEPTION 'Invalid receipt-aware artist update arguments'
            USING ERRCODE = '22023';
    END IF;

    IF p_metadata_field_states IS NOT NULL
       AND jsonb_typeof(p_metadata_field_states)
           IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Artist metadata field states must be an array'
            USING ERRCODE = '22023';
    END IF;

    -- The artist update and write identity are one database operation.
    -- The existing BEFORE UPDATE trigger increments server_revision.
    UPDATE public.artists AS a
    SET
        name = p_name,
        canonical_name = p_canonical_name,
        header_artwork_id = p_header_artwork_id,
        top_artists_artwork_id = p_top_artists_artwork_id,
        metadata_field_states = p_metadata_field_states,
        updated_at = p_updated_at,
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
            RAISE EXCEPTION 'Unexpected artist server revision';
        END IF;

        RETURN QUERY SELECT 'applied'::text, v_revision;
        RETURN;
    END IF;

    -- No update occurred. Inspect only the caller's own artist.
    -- A replay must still be the current cloud revision.
    -- Lock the current artist while deciding whether a prior write
    -- is still the latest successful mutation.
    SELECT
        a.server_revision,
        a.last_write_outbox_id,
        a.last_write_mutation_revision,
        a.last_write_server_revision,
        a.deleted_at,
        a.name,
        a.canonical_name,
        a.header_artwork_id,
        a.top_artists_artwork_id,
        a.metadata_field_states,
        a.updated_at
    INTO v_record
    FROM public.artists AS a
    WHERE a.id = p_artist_id
      AND a.user_id = v_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, NULL::bigint;
        RETURN;
    END IF;

    IF v_record.deleted_at IS NULL
       AND v_record.last_write_outbox_id = p_outbox_id
       AND v_record.last_write_mutation_revision = p_mutation_revision
       AND v_record.last_write_server_revision = v_record.server_revision
       AND v_record.server_revision = p_expected_revision + 1
       AND v_record.name IS NOT DISTINCT FROM p_name
       AND v_record.canonical_name IS NOT DISTINCT FROM p_canonical_name
       AND v_record.header_artwork_id IS NOT DISTINCT FROM p_header_artwork_id
       AND v_record.top_artists_artwork_id IS NOT DISTINCT FROM p_top_artists_artwork_id
       AND v_record.metadata_field_states IS NOT DISTINCT FROM p_metadata_field_states
       AND v_record.updated_at IS NOT DISTINCT FROM p_updated_at THEN
        RETURN QUERY
            SELECT 'replayed'::text, v_record.server_revision;
        RETURN;
    END IF;

    RETURN QUERY
        SELECT 'conflict'::text, v_record.server_revision;
END;
$function$;

REVOKE ALL ON FUNCTION public.update_artist_record_with_receipt(
    text, bigint, text, bigint, text, text, text, text,
    jsonb, timestamptz
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.update_artist_record_with_receipt(
    text, bigint, text, bigint, text, text, text, text,
    jsonb, timestamptz
) TO authenticated;