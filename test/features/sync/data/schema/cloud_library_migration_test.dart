import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/data/contracts/supabase_sync_contract.dart';

void main() {
  group('cloud library migration', () {
    late String migration;
    late String discNumberMigration;
    late String songVersionMetadataMigration;

    setUpAll(() {
      migration = File(
        'supabase/migrations/20260913_000001_cloud_library_foundation.sql',
      ).readAsStringSync();
      discNumberMigration = File(
        'supabase/migrations/20260917_000002_song_disc_number.sql',
      ).readAsStringSync();
      songVersionMetadataMigration = File(
        'supabase/migrations/20261003_000003_song_version_metadata.sql',
      ).readAsStringSync();
    });

    test('creates every declared cloud table', () {
      for (final table in SupabaseSyncContract.cloudTables) {
        expect(
          migration,
          contains('create table public.$table'),
          reason: 'Missing cloud table: $table',
        );
      }
    });

    test('does not create device-local tables', () {
      for (final table in SupabaseSyncContract.deviceLocalTables) {
        expect(
          migration,
          isNot(contains('create table public.$table')),
          reason: 'Device-local table leaked into cloud schema: $table',
        );
      }
    });

    test('cloud tables contain ownership and sync lifecycle columns', () {
      for (final column in SupabaseSyncContract.requiredOwnedColumns) {
        expect(
          migration,
          contains(column),
          reason: 'Missing required cloud column: $column',
        );
      }
    });

    test('enables row level security for every cloud table', () {
      for (final table in SupabaseSyncContract.cloudTables) {
        expect(
          migration,
          contains('alter table public.$table enable row level security;'),
          reason: 'RLS is not enabled for: $table',
        );
      }
    });

    test('anchors cloud ownership to Supabase Auth', () {
      expect(
        migration,
        contains(
          'user_id uuid not null references auth.users(id) on delete cascade',
        ),
      );

      expect(migration, contains('(select auth.uid()) = user_id'));
    });

    test('uses ownership-safe relationship foreign keys', () {
      expect(migration, contains('foreign key (user_id, artist_id)'));

      expect(migration, contains('foreign key (user_id, artist_id, album_id)'));

      expect(
        migration,
        contains('foreign key (user_id, album_id, album_edition_id)'),
      );

      expect(migration, contains('foreign key (user_id, artwork_id)'));
    });

    test('declares tombstone indexes for incremental deletion sync', () {
      for (final table in SupabaseSyncContract.cloudTables) {
        expect(
          migration,
          contains('${table}_user_deleted_idx'),
          reason: 'Missing tombstone index for: $table',
        );
      }
    });

    test('creates private artwork bucket', () {
      expect(
        migration,
        contains(
          "values ('${SupabaseSyncContract.artworkBucket}', "
          "'${SupabaseSyncContract.artworkBucket}', false)",
        ),
      );
    });

    test('scopes artwork storage policies to authenticated user folder', () {
      expect(
        migration,
        contains("(storage.foldername(name))[1] = (select auth.uid())::text"),
      );
    });

    test('prevents authenticated clients from hard deleting cloud rows', () {
      for (final table in SupabaseSyncContract.cloudTables) {
        expect(
          migration,
          contains(
            'grant select, insert, update on table public.$table '
            'to authenticated;',
          ),
          reason: 'Unexpected authenticated privileges for: $table',
        );
      }

      expect(
        migration,
        isNot(contains('grant select, insert, update, delete')),
      );

      expect(migration, isNot(contains('Users can delete own songs')));
    });

    test('revokes implicit cloud-table privileges', () {
      for (final table in SupabaseSyncContract.cloudTables) {
        expect(
          migration,
          contains(
            'revoke all on table public.$table from anon, authenticated;',
          ),
          reason: 'Missing explicit privilege revocation for: $table',
        );
      }
    });

    test('declares a server-controlled synchronization cursor', () {
      expect(
        migration,
        contains('server_updated_at timestamptz not null default now()'),
      );

      expect(migration, contains('new.server_updated_at = now();'));

      for (final table in SupabaseSyncContract.cloudTables) {
        expect(
          migration,
          contains('before insert or update on public.$table'),
          reason: 'Server cursor is not protected on insert/update: $table',
        );
      }

      expect(migration, contains(SupabaseSyncContract.serverUpdatedAtColumn));
    });

    test('indexes server cursor with stable ID tie breaker', () {
      for (final table in SupabaseSyncContract.cloudTables) {
        expect(
          migration,
          contains(
            'on public.$table '
            '(user_id, server_updated_at, id);',
          ),
          reason: 'Missing server cursor index for: $table',
        );
      }
    });

    test('does not persist local artwork filesystem paths', () {
      expect(migration, isNot(contains('file_path')));
      expect(migration, isNot(contains('normalized_path')));

      expect(migration, contains(SupabaseSyncContract.storageObjectKeyColumn));
    });

    test('adds nonnegative disc number to cloud songs', () {
      expect(
        discNumberMigration,
        contains(
          'add column if not exists ${SupabaseSyncContract.discNumberColumn} '
          'integer not null default 1',
        ),
      );

      expect(discNumberMigration, contains('songs_disc_number_nonnegative'));

      expect(
        discNumberMigration,
        contains('check (${SupabaseSyncContract.discNumberColumn} >= 0)'),
      );
    });
    test('adds song version metadata to cloud songs', () {
      expect(
        songVersionMetadataMigration,
        contains('add column if not exists version_label text'),
      );

      expect(
        songVersionMetadataMigration,
        contains(
          "add column if not exists version_characteristics text[] not null default '{}'",
        ),
      );

      expect(
        songVersionMetadataMigration,
        contains(
          "add column if not exists release_status text not null default 'released'",
        ),
      );

      expect(
        songVersionMetadataMigration,
        contains(
          'add column if not exists is_leak boolean not null default false',
        ),
      );

      expect(
        songVersionMetadataMigration,
        contains('songs_release_status_valid'),
      );

      expect(
        songVersionMetadataMigration,
        contains("check (release_status in ('released', 'unreleased'))"),
      );
    });
    test('artists persist blacklist state in cloud schema', () {
      expect(
        migration,
        contains(
          '${SupabaseSyncContract.isBlacklistedColumn} boolean not null default false',
        ),
      );
    });
  });
}
