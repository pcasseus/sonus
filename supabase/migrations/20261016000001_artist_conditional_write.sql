-- SN-41A.3.1b: First revision-aware cloud write operation.
-- Artist name update proof of concept.
--
-- Compatibility stage:
-- Existing direct authenticated writes remain enabled.
-- This function does not yet make all cloud writes conflict-safe.

CREATE FUNCTION public.update_artist_name_if_revision(
    p_artist_id text,
    p_expected_revision bigint,
    p_name text,
    p_canonical_name text,
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

    IF p_expected_revision IS NULL OR p_expected_revision < 1 THEN
        RAISE EXCEPTION 'Invalid expected revision'
            USING ERRCODE = '22023';
    END IF;

    -- Atomic conditional UPDATE. PostgreSQL locks the row and
    -- rechecks the revision condition after concurrent updates.
    UPDATE public.artists AS a
    SET
        name = p_name,
        canonical_name = p_canonical_name,
        updated_at = p_updated_at
    WHERE a.id = p_artist_id
      AND a.user_id = v_user_id
      AND a.server_revision = p_expected_revision
    RETURNING a.server_revision
    INTO v_revision;

    IF FOUND THEN
        RETURN QUERY SELECT 'applied'::text, v_revision;
        RETURN;
    END IF;

    -- The current user may inspect only their own artist.
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

-- PostgreSQL functions normally grant EXECUTE to PUBLIC.
-- Restrict this RPC to authenticated users.
REVOKE ALL ON FUNCTION public.update_artist_name_if_revision(
    text, bigint, text, text, timestamptz
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.update_artist_name_if_revision(
    text, bigint, text, text, timestamptz
) TO authenticated;