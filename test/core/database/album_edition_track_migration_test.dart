import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/library_schema.dart';

void main() {
  sqfliteFfiInit();

  test(
    'version 23 backfills edition membership from legacy song fields',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      try {
        await db.execute('PRAGMA foreign_keys = ON');
        await LibrarySchema.create(db);

        // Simulate a v22 library: all legacy tables exist, but the new
        // membership table does not.
        await db.execute('DROP TABLE ${DatabaseTables.albumEditionTracks}');

        const createdAt = '2026-10-01T10:00:00.000Z';
        const updatedAt = '2026-10-01T11:00:00.000Z';

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

        Future<void> insertSong({
          required String id,
          required String title,
          required int disc,
          required int track,
        }) async {
          await db.insert(DatabaseTables.songs, {
            'id': id,
            'artist_id': 'artist_1',
            'album_id': 'album_1',
            'album_edition_id': 'edition_1',
            'title': title,
            'canonical_title': title.toLowerCase(),
            'track_number': track,
            'disc_number': disc,
            'duration_seconds': 180,
            'is_single': 0,
            'is_blocked': 0,
            'featured_artists': '[]',
            'created_at': createdAt,
            'updated_at': updatedAt,
          });
        }

        await insertSong(id: 'song_2', title: 'Second', disc: 1, track: 2);
        await insertSong(id: 'song_1', title: 'First', disc: 1, track: 1);

        await DatabaseMigrations.migrate(db, oldVersion: 22, newVersion: 23);

        final rows = await db.query(
          DatabaseTables.albumEditionTracks,
          orderBy: 'sort_position ASC',
        );

        expect(rows, hasLength(2));

        expect(rows[0]['song_id'], 'song_1');
        expect(rows[0]['album_edition_id'], 'edition_1');
        expect(rows[0]['disc_number'], 1);
        expect(rows[0]['track_number'], 1);
        expect(rows[0]['sort_position'], 0);

        expect(rows[1]['song_id'], 'song_2');
        expect(rows[1]['sort_position'], 1);

        // Legacy Song identity/placement remains intact during the
        // compatibility phase.
        final songs = await db.query(DatabaseTables.songs, orderBy: 'id ASC');

        expect(songs, hasLength(2));
        expect(songs[0]['album_edition_id'], 'edition_1');
        expect(songs[0]['track_number'], 1);
      } finally {
        await db.close();
      }
    },
  );
}
