-- SN-41A.3.2C: Receipt-aware artist creation.
--
-- Requires the artist write receipt foundation.
-- Additive RPC; existing creation behavior remains unchanged.
--
-- Explicit artist outbox mutations use this function.
-- Dependency creation continues to use create_artist_if_absent
-- until separately migrated.
--
-- A replay is recognized only when the exact mutation identity,
-- synchronized payload, and current server revision match.

CREATE FUNCTION public.create_artist_with_receipt(
    p_artist_id text,
    p_outbox_id text,
    p_mutation_revision bigint,
    p_name text,
    p_canonical_name text,
    p_header_artwork_id text,
    p_top_artists_artwork_id text,
    p_metadata_field_states jsonb,
    p_created_at timestamptz,
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

    IF p_artist_id IS NULL
       OR length(trim(p_artist_id)) = 0
       OR p_outbox_id IS NULL
       OR length(trim(p_outbox_id)) = 0
       OR p_mutation_revision IS NULL
       OR p_mutation_revision < 1
       OR p_name IS NULL
       OR length(trim(p_name)) = 0
       OR p_canonical_name IS NULL
       OR length(trim(p_canonical_name)) = 0
       OR p_created_at IS NULL
       OR p_updated_at IS NULL THEN
        RAISE EXCEPTION 'Invalid receipt-aware artist creation arguments'
            USING ERRCODE = '22023';
    END IF;

    IF p_metadata_field_states IS NOT NULL
       AND jsonb_typeof(p_metadata_field_states)
           IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Artist metadata field states must be an array'
            USING ERRCODE = '22023';
    END IF;

    -- This INSERT and its receipt are atomic.
    -- The existing revision trigger initializes server_revision to 1.
    INSERT INTO public.artists (
        id,
        user_id,
        name,
        canonical_name,
        header_artwork_id,
        top_artists_artwork_id,
        metadata_field_states,
        created_at,
        updated_at,
        last_write_outbox_id,
        last_write_mutation_revision,
        last_write_server_revision
    )
    VALUES (
        p_artist_id,
        v_user_id,
        p_name,
        p_canonical_name,
        p_header_artwork_id,
        p_top_artists_artwork_id,
        p_metadata_field_states,
        p_created_at,
        p_updated_at,
        p_outbox_id,
        p_mutation_revision,
        1
    )
    ON CONFLICT (id) DO NOTHING
    RETURNING public.artists.server_revision
    INTO v_revision;

    IF FOUND THEN
        IF v_revision <> 1 THEN
            RAISE EXCEPTION 'New cloud artist must start at revision 1';
        END IF;

        RETURN QUERY SELECT 'applied'::text, v_revision;
        RETURN;
    END IF;

    -- A collision is not automatically proof of a successful retry.
    -- Lock the record while verifying the previously applied mutation.
    -- Only the authenticated owner's record is eligible for replay.
    SELECT
        a.server_revision,
        a.last_write_outbox_id,
        a.last_write_mutation_revision,
        a.last_write_server_revision,
        a.name,
        a.canonical_name,
        a.header_artwork_id,
        a.top_artists_artwork_id,
        a.metadata_field_states,
        a.created_at,
        a.updated_at,
        a.is_blacklisted,
        a.deleted_at
    INTO v_record
    FROM public.artists AS a
    WHERE a.id = p_artist_id
      AND a.user_id = v_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        -- Do not reveal another account's artist revision.
        RETURN QUERY SELECT 'not_found'::text, NULL::bigint;
        RETURN;
    END IF;

    IF v_record.server_revision = 1
       AND v_record.last_write_outbox_id = p_outbox_id
       AND v_record.last_write_mutation_revision = p_mutation_revision
       AND v_record.last_write_server_revision = 1
       AND v_record.deleted_at IS NULL
       AND v_record.is_blacklisted = false
       AND v_record.name IS NOT DISTINCT FROM p_name
       AND v_record.canonical_name IS NOT DISTINCT FROM p_canonical_name
       AND v_record.header_artwork_id
           IS NOT DISTINCT FROM p_header_artwork_id
       AND v_record.top_artists_artwork_id
           IS NOT DISTINCT FROM p_top_artists_artwork_id
       AND v_record.metadata_field_states
           IS NOT DISTINCT FROM p_metadata_field_states
       AND v_record.created_at IS NOT DISTINCT FROM p_created_at
       AND v_record.updated_at IS NOT DISTINCT FROM p_updated_at THEN
        RETURN QUERY SELECT 'replayed'::text, 1::bigint;
        RETURN;
    END IF;

    RETURN QUERY SELECT 'conflict'::text, v_record.server_revision;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_artist_with_receipt(
    text, text, bigint, text, text, text, text,
    jsonb, timestamptz, timestamptz
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_artist_with_receipt(
    text, text, bigint, text, text, text, text,
    jsonb, timestamptz, timestamptz
) TO authenticated;