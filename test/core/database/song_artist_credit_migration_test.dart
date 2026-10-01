import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/database_migrations.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/library_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'v21 migration backfills primary and featured credits without creating artists',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

      await LibrarySchema.create(db);

      await db.execute('DROP TABLE ${DatabaseTables.songArtistCredits}');

      final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

      await db.insert(DatabaseTables.artists, {
        'id': 'artist_madison',
        'name': 'Madison Beer',
        'canonical_name': 'madison beer',
        'header_artwork_id': null,
        'top_artists_artwork_id': null,
        'is_blacklisted': 0,
        'created_at': timestamp,
        'updated_at': timestamp,
      });

      await db.insert(DatabaseTables.albums, {
        'id': 'album_1',
        'artist_id': 'artist_madison',
        'title': 'Album',
        'canonical_title': 'album',
        'created_at': timestamp,
        'updated_at': timestamp,
      });

      await db.insert(DatabaseTables.albumEditions, {
        'id': 'edition_1',
        'album_id': 'album_1',
        'title': 'Album',
        'type': 'standard',
        'is_primary': 1,
        'release_date': null,
        'genre': null,
        'artwork_id': null,
        'created_at': timestamp,
        'updated_at': timestamp,
      });

      await db.insert(DatabaseTables.songs, {
        'id': 'song_1',
        'artist_id': 'artist_madison',
        'album_id': 'album_1',
        'album_edition_id': 'edition_1',
        'title': 'Example',
        'canonical_title': 'example',
        'track_number': 1,
        'disc_number': 1,
        'duration_seconds': 180,
        'is_single': 0,
        'is_blocked': 0,
        'featured_artists': jsonEncode([
          'Tate McRae',
          'Madison Beer',
          'Tate McRae',
        ]),
        'artwork_id': null,
        'created_at': timestamp,
        'updated_at': timestamp,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 20, newVersion: 21);

      final credits = await db.query(
        DatabaseTables.songArtistCredits,
        where: 'song_id = ?',
        whereArgs: ['song_1'],
        orderBy: 'position ASC',
      );

      expect(credits, hasLength(2));

      expect(credits[0]['credited_name'], 'Madison Beer');
      expect(credits[0]['artist_id'], 'artist_madison');
      expect(credits[0]['role'], 'primary');

      expect(credits[1]['credited_name'], 'Tate McRae');
      expect(credits[1]['artist_id'], isNull);
      expect(credits[1]['role'], 'featured');

      final artists = await db.query(DatabaseTables.artists);

      expect(artists, hasLength(1));

      await db.close();
    },
  );

  test(
    'v21 migration links a featured credit when exactly one artist already exists',
    () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

      await LibrarySchema.create(db);

      await db.execute('DROP TABLE ${DatabaseTables.songArtistCredits}');

      final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

      Future<void> insertArtist(String id, String name, String canonicalName) {
        return db.insert(DatabaseTables.artists, {
          'id': id,
          'name': name,
          'canonical_name': canonicalName,
          'header_artwork_id': null,
          'top_artists_artwork_id': null,
          'is_blacklisted': 0,
          'created_at': timestamp,
          'updated_at': timestamp,
        });
      }

      await insertArtist('artist_madison', 'Madison Beer', 'madison beer');

      await insertArtist('artist_tate', 'Tate McRae', 'tate mcrae');

      await db.insert(DatabaseTables.albums, {
        'id': 'album_1',
        'artist_id': 'artist_madison',
        'title': 'Album',
        'canonical_title': 'album',
        'created_at': timestamp,
        'updated_at': timestamp,
      });

      await db.insert(DatabaseTables.albumEditions, {
        'id': 'edition_1',
        'album_id': 'album_1',
        'title': 'Album',
        'type': 'standard',
        'is_primary': 1,
        'release_date': null,
        'genre': null,
        'artwork_id': null,
        'created_at': timestamp,
        'updated_at': timestamp,
      });

      await db.insert(DatabaseTables.songs, {
        'id': 'song_1',
        'artist_id': 'artist_madison',
        'album_id': 'album_1',
        'album_edition_id': 'edition_1',
        'title': 'Example',
        'canonical_title': 'example',
        'track_number': 1,
        'disc_number': 1,
        'duration_seconds': 180,
        'is_single': 0,
        'is_blocked': 0,
        'featured_artists': jsonEncode(['Tate McRae']),
        'artwork_id': null,
        'created_at': timestamp,
        'updated_at': timestamp,
      });

      await DatabaseMigrations.migrate(db, oldVersion: 20, newVersion: 21);

      final featureRows = await db.query(
        DatabaseTables.songArtistCredits,
        where: 'song_id = ? AND role = ?',
        whereArgs: ['song_1', 'featured'],
      );

      expect(featureRows, hasLength(1));
      expect(featureRows.single['artist_id'], 'artist_tate');

      await db.close();
    },
  );
}
