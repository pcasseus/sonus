import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/song_artist_credit_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Database db;
  late TrackProfileEditingService service;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    db = await appDatabase.database;

    service = TrackProfileEditingService(
      mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
    );

    await _insertArtist(
      db,
      id: 'artist_primary',
      name: 'Primary Artist',
      canonicalName: 'primary artist',
    );

    await _insertArtist(
      db,
      id: 'artist_second',
      name: 'Second Artist',
      canonicalName: 'second artist',
    );

    await _insertAlbumStructure(db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('manual featured-artist edit writes structured credits', () async {
    final result = await service.updateTrack(
      userId: null,
      songId: 'song_1',
      title: 'Test Song',
      trackNumber: 1,
      discNumber: 1,
      featuredArtists: const ['Featured Artist'],
      isSingle: false,
      now: DateTime.utc(2026, 10, 1, 12),
    );

    expect(result.changed, isTrue);

    final credits = await db.query(
      DatabaseTables.songArtistCredits,
      where: 'song_id = ?',
      whereArgs: ['song_1'],
      orderBy: 'position ASC',
    );

    expect(credits, hasLength(2));

    expect(credits[0]['artist_id'], 'artist_primary');
    expect(credits[0]['credited_name'], 'Primary Artist');
    expect(credits[0]['role'], 'primary');

    expect(credits[1]['artist_id'], isNull);
    expect(credits[1]['credited_name'], 'Featured Artist');
    expect(credits[1]['canonical_credited_name'], 'featured artist');
    expect(credits[1]['role'], 'featured');

    final song = await _songRow(db);

    expect(jsonDecode(song['featured_artists'] as String), ['Featured Artist']);
  });

  test(
    'changing primary artist also replaces the primary structured credit',
    () async {
      await service.updateTrack(
        userId: null,
        songId: 'song_1',
        title: 'Test Song',
        trackNumber: 1,
        discNumber: 1,
        featuredArtists: const [],
        isSingle: false,
        artistId: 'artist_second',
      );

      final song = await _songRow(db);

      expect(song['artist_id'], 'artist_second');

      final credits = await db.query(
        DatabaseTables.songArtistCredits,
        where: 'song_id = ?',
        whereArgs: ['song_1'],
        orderBy: 'position ASC',
      );

      expect(credits, hasLength(1));
      expect(credits.single['artist_id'], 'artist_second');
      expect(credits.single['credited_name'], 'Second Artist');
      expect(credits.single['role'], 'primary');
    },
  );

  test(
    'canonical duplicate feature names collapse to one structured credit',
    () async {
      await service.updateTrack(
        userId: null,
        songId: 'song_1',
        title: 'Test Song',
        trackNumber: 1,
        discNumber: 1,
        featuredArtists: const [
          'Featured Artist',
          '  FEATURED ARTIST  ',
          'Primary Artist',
        ],
        isSingle: false,
      );

      final credits = await db.query(
        DatabaseTables.songArtistCredits,
        where: 'song_id = ?',
        whereArgs: ['song_1'],
        orderBy: 'position ASC',
      );

      expect(credits, hasLength(2));

      expect(credits[0]['credited_name'], 'Primary Artist');
      expect(credits[1]['credited_name'], 'Featured Artist');

      final song = await _songRow(db);

      expect(jsonDecode(song['featured_artists'] as String), [
        'Featured Artist',
      ]);
    },
  );

  test(
    'structured edit preserves co-primary and guest roles while only featured projects to Song',
    () async {
      final result = await service.updateTrackWithCredits(
        userId: null,
        songId: 'song_1',
        title: 'Test Song',
        trackNumber: 1,
        discNumber: 1,
        additionalCredits: const [
          SongArtistCreditInput(
            creditedName: 'Second Artist',
            role: SongArtistCreditRole.coPrimary,
            artistId: 'artist_second',
          ),
          SongArtistCreditInput(
            creditedName: 'Guest Artist',
            role: SongArtistCreditRole.guest,
          ),
          SongArtistCreditInput(
            creditedName: 'Featured Artist',
            role: SongArtistCreditRole.featured,
          ),
        ],
        isSingle: false,
        now: DateTime.utc(2026, 10, 1, 12),
      );

      expect(result.changed, isTrue);

      final credits = await db.query(
        DatabaseTables.songArtistCredits,
        where: 'song_id = ?',
        whereArgs: ['song_1'],
        orderBy: 'position ASC',
      );

      expect(credits, hasLength(4));

      expect(credits[0]['artist_id'], 'artist_primary');
      expect(credits[0]['credited_name'], 'Primary Artist');
      expect(credits[0]['role'], 'primary');

      expect(credits[1]['artist_id'], 'artist_second');
      expect(credits[1]['credited_name'], 'Second Artist');
      expect(credits[1]['role'], 'coPrimary');

      expect(credits[2]['artist_id'], isNull);
      expect(credits[2]['credited_name'], 'Guest Artist');
      expect(credits[2]['role'], 'guest');

      expect(credits[3]['artist_id'], isNull);
      expect(credits[3]['credited_name'], 'Featured Artist');
      expect(credits[3]['role'], 'featured');

      final song = await _songRow(db);

      expect(jsonDecode(song['featured_artists'] as String), [
        'Featured Artist',
      ]);
    },
  );
  test('credit persistence failure rolls back the Song edit', () async {
    await db.execute('''
        CREATE TRIGGER fail_song_artist_credit_insert
        BEFORE INSERT ON ${DatabaseTables.songArtistCredits}
        BEGIN
          SELECT RAISE(ABORT, 'forced structured credit failure');
        END
      ''');

    await expectLater(
      service.updateTrack(
        userId: null,
        songId: 'song_1',
        title: 'Changed Title',
        trackNumber: 5,
        discNumber: 2,
        featuredArtists: const ['Featured Artist'],
        isSingle: true,
      ),
      throwsA(anything),
    );

    final song = await _songRow(db);

    expect(song['title'], 'Test Song');
    expect(song['track_number'], 1);
    expect(song['disc_number'], 1);
    expect(song['is_single'], 0);

    expect(jsonDecode(song['featured_artists'] as String), isEmpty);

    final credits = await db.query(
      DatabaseTables.songArtistCredits,
      where: 'song_id = ?',
      whereArgs: ['song_1'],
    );

    expect(credits, isEmpty);
  });
}

Future<Map<String, Object?>> _songRow(Database db) async {
  final rows = await db.query(
    DatabaseTables.songs,
    where: 'id = ?',
    whereArgs: ['song_1'],
  );

  return rows.single;
}

Future<void> _insertArtist(
  Database db, {
  required String id,
  required String name,
  required String canonicalName,
}) {
  final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

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

Future<void> _insertAlbumStructure(Database db) async {
  final timestamp = DateTime.utc(2026, 10, 1).toIso8601String();

  await db.insert(DatabaseTables.albums, {
    'id': 'album_1',
    'artist_id': 'artist_primary',
    'title': 'Test Album',
    'canonical_title': 'test album',
    'created_at': timestamp,
    'updated_at': timestamp,
  });

  await db.insert(DatabaseTables.albumEditions, {
    'id': 'edition_1',
    'album_id': 'album_1',
    'title': 'Test Album',
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
    'artist_id': 'artist_primary',
    'album_id': 'album_1',
    'album_edition_id': 'edition_1',
    'title': 'Test Song',
    'canonical_title': 'test song',
    'track_number': 1,
    'disc_number': 1,
    'duration_seconds': 180,
    'is_single': 0,
    'is_blocked': 0,
    'featured_artists': '[]',
    'artwork_id': null,
    'created_at': timestamp,
    'updated_at': timestamp,
  });
}
