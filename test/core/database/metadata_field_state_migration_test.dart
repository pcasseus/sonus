import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/library_schema.dart';

void main() {
  sqfliteFfiInit();

  test(
    'version 27 adds metadata field state persistence without changing library data',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      try {
        await db.execute('PRAGMA foreign_keys = ON');
        await LibrarySchema.create(db);

        // Simulate the relevant v26 state: the library exists, but the
        // metadata field-state table introduced in v27 does not.
        await db.execute('DROP TABLE ${DatabaseTables.metadataFieldStates}');

        const createdAt = '2026-10-07T10:00:00.000Z';
        const updatedAt = '2026-10-07T11:00:00.000Z';

        await db.insert(DatabaseTables.artists, {
          'id': 'artist_1',
          'name': 'Artist',
          'canonical_name': 'artist',
          'created_at': createdAt,
          'updated_at': updatedAt,
        });

        await db.insert(DatabaseTables.albums, {
          'id': 'album_1',
          'artist_id': 'artist_1',
          'title': 'Album',
          'canonical_title': 'album',
          'created_at': createdAt,
          'updated_at': updatedAt,
        });

        await db.insert(DatabaseTables.albumEditions, {
          'id': 'edition_1',
          'album_id': 'album_1',
          'title': 'Standard',
          'type': 'standard',
          'is_primary': 1,
          'created_at': createdAt,
          'updated_at': updatedAt,
        });

        await db.insert(DatabaseTables.songs, {
          'id': 'song_1',
          'artist_id': 'artist_1',
          'album_id': 'album_1',
          'album_edition_id': 'edition_1',
          'title': 'Track',
          'canonical_title': 'track',
          'track_number': 1,
          'disc_number': 1,
          'duration_seconds': 180,
          'is_single': 0,
          'is_blocked': 0,
          'featured_artists': '[]',
          'version_characteristics': '[]',
          'release_status': 'released',
          'is_leak': 0,
          'created_at': createdAt,
          'updated_at': updatedAt,
        });

        await DatabaseMigrations.migrate(db, oldVersion: 26, newVersion: 27);

        final metadataTables = await db.rawQuery(
          '''
          SELECT name
          FROM sqlite_master
          WHERE type = 'table'
            AND name = ?
          ''',
          [DatabaseTables.metadataFieldStates],
        );

        expect(metadataTables, hasLength(1));

        final artists = await db.query(DatabaseTables.artists);
        final albums = await db.query(DatabaseTables.albums);
        final editions = await db.query(DatabaseTables.albumEditions);
        final songs = await db.query(DatabaseTables.songs);

        expect(artists, hasLength(1));
        expect(albums, hasLength(1));
        expect(editions, hasLength(1));
        expect(songs, hasLength(1));

        expect(artists.single['id'], 'artist_1');
        expect(albums.single['id'], 'album_1');
        expect(editions.single['id'], 'edition_1');
        expect(songs.single['id'], 'song_1');
        expect(songs.single['title'], 'Track');
      } finally {
        await db.close();
      }
    },
  );
}
