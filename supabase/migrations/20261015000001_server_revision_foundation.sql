-- SN-41A.3.1a: Server-managed cloud entity revisions.
--
-- Existing rows begin at revision 1.
-- Every INSERT receives revision 1.
-- Every UPDATE advances the previous revision by exactly 1.
--
-- This migration does not yet enforce compare-and-set writes.
-- Direct authenticated writes remain available for compatibility.

ALTER TABLE public.artwork_assets
    ADD COLUMN server_revision bigint NOT NULL DEFAULT 1
    CHECK (server_revision > 0);

ALTER TABLE public.artists
    ADD COLUMN server_revision bigint NOT NULL DEFAULT 1
    CHECK (server_revision > 0);

ALTER TABLE public.albums
    ADD COLUMN server_revision bigint NOT NULL DEFAULT 1
    CHECK (server_revision > 0);

ALTER TABLE public.album_editions
    ADD COLUMN server_revision bigint NOT NULL DEFAULT 1
    CHECK (server_revision > 0);

ALTER TABLE public.songs
    ADD COLUMN server_revision bigint NOT NULL DEFAULT 1
    CHECK (server_revision > 0);

CREATE FUNCTION public.set_cloud_server_revision()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.server_revision := 1;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.server_revision = 9223372036854775807 THEN
            RAISE EXCEPTION 'Cloud server revision exhausted';
        END IF;

        NEW.server_revision := OLD.server_revision + 1;
    END IF;

    RETURN NEW;
END;
$function$;

CREATE TRIGGER artwork_assets_set_server_revision
BEFORE INSERT OR UPDATE ON public.artwork_assets
FOR EACH ROW
EXECUTE FUNCTION public.set_cloud_server_revision();

CREATE TRIGGER artists_set_server_revision
BEFORE INSERT OR UPDATE ON public.artists
FOR EACH ROW
EXECUTE FUNCTION public.set_cloud_server_revision();

CREATE TRIGGER albums_set_server_revision
BEFORE INSERT OR UPDATE ON public.albums
FOR EACH ROW
EXECUTE FUNCTION public.set_cloud_server_revision();

CREATE TRIGGER album_editions_set_server_revision
BEFORE INSERT OR UPDATE ON public.album_editions
FOR EACH ROW
EXECUTE FUNCTION public.set_cloud_server_revision();

CREATE TRIGGER songs_set_server_revision
BEFORE INSERT OR UPDATE ON public.songs
FOR EACH ROW
EXECUTE FUNCTION public.set_cloud_server_revision();