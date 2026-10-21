-- SN-41A.3.2B: Full-record, revision-conditional artist updates.
-- Existing artists only. Creation remains a separate operation.
-- The server_revision trigger determines the new revision.
-- Do not modify is_blacklisted, created_at, or deleted_at.

CREATE FUNCTION public.update_artist_record_if_revision(
    p_artist_id text,
    p_expected_revision bigint,
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
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
    v_user_id uuid;
    v_revision bigint;
BEGIN
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required'
            USING ERRCODE = '28000';
    END IF;

    IF p_artist_id IS NULL OR length(trim(p_artist_id)) = 0
       OR p_expected_revision IS NULL
       OR p_expected_revision < 1
       OR p_name IS NULL OR length(trim(p_name)) = 0
       OR p_canonical_name IS NULL OR length(trim(p_canonical_name)) = 0
       OR p_updated_at IS NULL THEN
        RAISE EXCEPTION 'Invalid artist conditional-write arguments'
            USING ERRCODE = '22023';
    END IF;

    IF p_metadata_field_states IS NOT NULL
       AND jsonb_typeof(p_metadata_field_states) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Artist metadata field states must be an array'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.artists AS a
    SET
        name = p_name,
        canonical_name = p_canonical_name,
        header_artwork_id = p_header_artwork_id,
        top_artists_artwork_id = p_top_artists_artwork_id,
        metadata_field_states = p_metadata_field_states,
        updated_at = p_updated_at
    WHERE a.id = p_artist_id
      AND a.user_id = v_user_id
      AND a.deleted_at IS NULL
      AND a.server_revision = p_expected_revision
    RETURNING a.server_revision INTO v_revision;

    IF FOUND THEN
        RETURN QUERY SELECT 'applied'::text, v_revision;
        RETURN;
    END IF;

    SELECT a.server_revision
    INTO v_revision
    FROM public.artists AS a
    WHERE a.id = p_artist_id
      AND a.user_id = v_user_id;

    IF FOUND THEN
        RETURN QUERY SELECT 'conflict'::text, v_revision;
    ELSE
        RETURN QUERY SELECT 'not_found'::text, NULL::bigint;
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.update_artist_record_if_revision(
    text, bigint, text, text, text, text, jsonb, timestamptz
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.update_artist_record_if_revision(
    text, bigint, text, text, text, text, jsonb, timestamptz
) TO authenticated;