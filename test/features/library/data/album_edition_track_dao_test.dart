import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('one permanent song can belong to multiple album editions', () async {
    final db = await appDatabase.database;
    final dao = AlbumEditionTrackDao(db);
    final now = DateTime.utc(2026, 10, 1, 12);

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_1',
      'name': 'Artist',
      'canonical_name': 'artist',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album_1',
      'artist_id': 'artist_1',
      'title': 'Album',
      'canonical_title': 'album',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    for (final edition in const [
      ('edition_standard', 'Standard', 'standard', 1),
      ('edition_deluxe', 'Deluxe', 'deluxe', 0),
    ]) {
      await db.insert(DatabaseTables.albumEditions, {
        'id': edition.$1,
        'album_id': 'album_1',
        'title': edition.$2,
        'type': edition.$3,
        'is_primary': edition.$4,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    }

    await db.insert(DatabaseTables.songs, {
      'id': 'song_shared',
      'artist_id': 'artist_1',
      'album_id': 'album_1',
      'album_edition_id': 'edition_standard',
      'title': 'Shared Song',
      'canonical_title': 'shared song',
      'track_number': 2,
      'disc_number': 1,
      'duration_seconds': 200,
      'is_single': 0,
      'is_blocked': 0,
      'featured_artists': '[]',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await dao.insert(
      AlbumEditionTrack(
        albumEditionId: 'edition_standard',
        songId: 'song_shared',
        discNumber: 1,
        trackNumber: 2,
        sortPosition: 1,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await dao.insert(
      AlbumEditionTrack(
        albumEditionId: 'edition_deluxe',
        songId: 'song_shared',
        discNumber: 2,
        trackNumber: 5,
        sortPosition: 17,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final memberships = await dao.findBySongId('song_shared');

    expect(memberships, hasLength(2));

    final standard = memberships.singleWhere(
      (value) => value.albumEditionId == 'edition_standard',
    );
    final deluxe = memberships.singleWhere(
      (value) => value.albumEditionId == 'edition_deluxe',
    );

    expect(standard.trackNumber, 2);
    expect(standard.sortPosition, 1);

    expect(deluxe.discNumber, 2);
    expect(deluxe.trackNumber, 5);
    expect(deluxe.sortPosition, 17);

    final songRows = await db.query(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: ['song_shared'],
    );

    // Permanent Song identity is still one row.
    expect(songRows, hasLength(1));
  });

  test('edition query follows explicit manual sort position', () async {
    final db = await appDatabase.database;
    final dao = AlbumEditionTrackDao(db);
    final now = DateTime.utc(2026, 10, 1, 12);

    await db.insert(DatabaseTables.artists, {
      'id': 'artist_order',
      'name': 'Artist',
      'canonical_name': 'artist',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await db.insert(DatabaseTables.albums, {
      'id': 'album_order',
      'artist_id': 'artist_order',
      'title': 'Album',
      'canonical_title': 'album',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await db.insert(DatabaseTables.albumEditions, {
      'id': 'edition_order',
      'album_id': 'album_order',
      'title': 'Standard',
      'type': 'standard',
      'is_primary': 1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    for (final songId in const ['song_a', 'song_b']) {
      await db.insert(DatabaseTables.songs, {
        'id': songId,
        'artist_id': 'artist_order',
        'album_id': 'album_order',
        'album_edition_id': 'edition_order',
        'title': songId,
        'canonical_title': songId,
        'track_number': 1,
        'disc_number': 1,
        'duration_seconds': 180,
        'is_single': 0,
        'is_blocked': 0,
        'featured_artists': '[]',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
    }

    await dao.insert(
      AlbumEditionTrack(
        albumEditionId: 'edition_order',
        songId: 'song_a',
        discNumber: 1,
        trackNumber: 1,
        sortPosition: 10,
        orderingAuthority: AlbumEditionTrackAuthority.manual,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await dao.insert(
      AlbumEditionTrack(
        albumEditionId: 'edition_order',
        songId: 'song_b',
        discNumber: 1,
        trackNumber: 99,
        sortPosition: 2,
        orderingAuthority: AlbumEditionTrackAuthority.manual,
        createdAt: now,
        updatedAt: now,
      ),
    );

    // A deliberately reordered edition keeps its order (J3); without manual
    // ordering the edition would follow disc and track numbers instead.
    final ordered = await dao.findByEditionId('edition_order');

    expect(ordered.map((value) => value.songId), ['song_b', 'song_a']);
  });
}
