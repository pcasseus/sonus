\set ON_ERROR_STOP on

BEGIN;

DO $test$
DECLARE
    v_user uuid := gen_random_uuid();
    v_table text;
    v_revision bigint;
    v_id text;
BEGIN
    INSERT INTO auth.users (id) VALUES (v_user);

    INSERT INTO public.artwork_assets (
        id, user_id, storage_object_key,
        created_at, updated_at, server_revision
    ) VALUES (
        'sn41-artwork', v_user, 'sn41/test-artwork',
        now(), now(), 999
    );

    INSERT INTO public.artists (
        id, user_id, name, canonical_name,
        created_at, updated_at, server_revision
    ) VALUES (
        'sn41-artist', v_user, 'Test Artist', 'test artist',
        now(), now(), 999
    );

    INSERT INTO public.albums (
        id, user_id, artist_id, title, canonical_title,
        created_at, updated_at, server_revision
    ) VALUES (
        'sn41-album', v_user, 'sn41-artist',
        'Test Album', 'test album',
        now(), now(), 999
    );

    INSERT INTO public.album_editions (
        id, user_id, album_id, title, type, is_primary,
        created_at, updated_at, server_revision
    ) VALUES (
        'sn41-edition', v_user, 'sn41-album',
        'Test Edition', 'standard', true,
        now(), now(), 999
    );

    INSERT INTO public.songs (
        id, user_id, artist_id, album_id, album_edition_id,
        title, canonical_title, track_number, duration_seconds,
        is_single, created_at, updated_at, server_revision
    ) VALUES (
        'sn41-song', v_user, 'sn41-artist',
        'sn41-album', 'sn41-edition',
        'Test Song', 'test song', 1, 180,
        false, now(), now(), 999
    );

    FOR v_table, v_id IN
        SELECT *
        FROM (VALUES
            ('artwork_assets', 'sn41-artwork'),
            ('artists', 'sn41-artist'),
            ('albums', 'sn41-album'),
            ('album_editions', 'sn41-edition'),
            ('songs', 'sn41-song')
        ) AS entities(table_name, entity_id)
    LOOP
        EXECUTE format(
            'SELECT server_revision FROM public.%I WHERE id = $1 AND user_id = $2',
            v_table
        )
        INTO v_revision
        USING v_id, v_user;

        IF v_revision IS DISTINCT FROM 1 THEN
            RAISE EXCEPTION
                '% INSERT: expected revision 1, got %',
                v_table, v_revision;
        END IF;

        RAISE NOTICE 'PASS: % insert forces revision 1', v_table;

        EXECUTE format(
            'UPDATE public.%I SET server_revision = 500
             WHERE id = $1 AND user_id = $2
             RETURNING server_revision',
            v_table
        )
        INTO v_revision
        USING v_id, v_user;

        IF v_revision IS DISTINCT FROM 2 THEN
            RAISE EXCEPTION
                '% UPDATE: expected revision 2, got %',
                v_table, v_revision;
        END IF;

        RAISE NOTICE 'PASS: % update forces revision 2', v_table;
    END LOOP;
END;
$test$;

ROLLBACK;