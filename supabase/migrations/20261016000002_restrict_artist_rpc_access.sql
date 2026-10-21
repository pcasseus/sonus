-- SN-41A.3.1b: Restrict artist conditional-write RPC access.
--
-- Explicitly revoke Supabase's anonymous API-role grant.
-- Preserve authenticated access and SECURITY INVOKER semantics.

REVOKE EXECUTE ON FUNCTION
    public.update_artist_name_if_revision(
        text,
        bigint,
        text,
        text,
        timestamptz
    )
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
    public.update_artist_name_if_revision(
        text,
        bigint,
        text,
        text,
        timestamptz
    )
TO authenticated;