import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/song_artist_credit_service.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Database db;
  late SongArtistCreditService service;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    db = await appDatabase.database;

    service = SongArtistCreditService(
      mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
    );

    await _insertArtist(
      db,
      id: 'artist_madison',
      name: 'Madison Beer',
      canonicalName: 'madison beer',
    );

    await _insertAlbumStructure(db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test(
    'feature-only credit stays unlinked and does not create an Artist',
    () async {
      final credits = await service.replaceCredits(
        userId: null,
        songId: 'song_1',
        primaryArtistId: 'artist_madison',
        additionalCredits: const [
          SongArtistCreditInput(
            creditedName: 'Tate McRae',
            role: SongArtistCreditRole.featured,
          ),
        ],
        now: DateTime.utc(2026, 10, 1, 12),
      );

      expect(credits, hasLength(2));

      expect(credits[0].role, SongArtistCreditRole.primary);
      expect(credits[0].artistId, 'artist_madison');

      expect(credits[1].role, SongArtistCreditRole.featured);
      expect(credits[1].creditedName, 'Tate McRae');
      expect(credits[1].artistId, isNull);

      final artists = await db.query(DatabaseTables.artists);

      expect(artists, hasLength(1));

      final songRows = await db.query(
        DatabaseTables.songs,
        where: 'id = ?',
        whereArgs: ['song_1'],
      );

      expect(songRows.single['featured_artists'], '["Tate McRae"]');
    },
  );

  test(
    'automatically links a credit when exactly one matching Artist exists',
    () async {
      await _insertArtist(
        db,
        id: 'artist_tate',
        name: 'Tate McRae',
        canonicalName: 'tate mcrae',
      );

      final credits = await service.replaceCredits(
        userId: null,
        songId: 'song_1',
        primaryArtistId: 'artist_madison',
        additionalCredits: const [
          SongArtistCreditInput(
            creditedName: 'Tate McRae',
            role: SongArtistCreditRole.featured,
          ),
        ],
      );

      expect(credits, hasLength(2));
      expect(credits[1].artistId, 'artist_tate');
    },
  );

  test('deduplicates credits by canonical artist identity', () async {
    final credits = await service.replaceCredits(
      userId: null,
      songId: 'song_1',
      primaryArtistId: 'artist_madison',
      additionalCredits: const [
        SongArtistCreditInput(
          creditedName: 'Tate McRae',
          role: SongArtistCreditRole.featured,
        ),
        SongArtistCreditInput(
          creditedName: '  TATE MCRAE  ',
          role: SongArtistCreditRole.featured,
        ),
        SongArtistCreditInput(
          creditedName: 'Madison Beer',
          role: SongArtistCreditRole.featured,
        ),
      ],
    );

    expect(credits, hasLength(2));
    expect(credits[0].creditedName, 'Madison Beer');
    expect(credits[1].creditedName, 'Tate McRae');
  });

  test('preserves guest separately from legacy featured artists', () async {
    final credits = await service.replaceCredits(
      userId: null,
      songId: 'song_1',
      primaryArtistId: 'artist_madison',
      additionalCredits: const [
        SongArtistCreditInput(
          creditedName: 'Artist A',
          role: SongArtistCreditRole.guest,
        ),
        SongArtistCreditInput(
          creditedName: 'Artist B',
          role: SongArtistCreditRole.featured,
        ),
      ],
    );

    expect(credits, hasLength(3));
    expect(credits[1].role, SongArtistCreditRole.guest);
    expect(credits[2].role, SongArtistCreditRole.featured);

    final songRows = await db.query(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: ['song_1'],
    );

    expect(songRows.single['featured_artists'], '["Artist B"]');
  });

  test(
    'links old unlinked credits when an Artist later enters the library',
    () async {
      await service.replaceCredits(
        userId: null,
        songId: 'song_1',
        primaryArtistId: 'artist_madison',
        additionalCredits: const [
          SongArtistCreditInput(
            creditedName: 'Tate McRae',
            role: SongArtistCreditRole.featured,
          ),
        ],
      );

      var rows = await db.query(
        DatabaseTables.songArtistCredits,
        where: 'canonical_credited_name = ?',
        whereArgs: ['tate mcrae'],
      );

      expect(rows.single['artist_id'], isNull);

      await _insertArtist(
        db,
        id: 'artist_tate',
        name: 'Tate McRae',
        canonicalName: 'tate mcrae',
      );

      final linkedCount = await service.linkUnlinkedCreditsForArtist(
        artistId: 'artist_tate',
        now: DateTime.utc(2026, 10, 1, 14),
      );

      expect(linkedCount, 1);

      rows = await db.query(
        DatabaseTables.songArtistCredits,
        where: 'canonical_credited_name = ?',
        whereArgs: ['tate mcrae'],
      );

      expect(rows.single['artist_id'], 'artist_tate');
    },
  );

  test(
    'does not auto-link when canonical Artist identity is ambiguous',
    () async {
      await service.replaceCredits(
        userId: null,
        songId: 'song_1',
        primaryArtistId: 'artist_madison',
        additionalCredits: const [
          SongArtistCreditInput(
            creditedName: 'Same Artist',
            role: SongArtistCreditRole.featured,
          ),
        ],
      );

      await _insertArtist(
        db,
        id: 'artist_same_1',
        name: 'Same Artist',
        canonicalName: 'same artist',
      );

      await _insertArtist(
        db,
        id: 'artist_same_2',
        name: 'Same Artist',
        canonicalName: 'same artist',
      );

      final linkedCount = await service.linkUnlinkedCreditsForArtist(
        artistId: 'artist_same_1',
      );

      expect(linkedCount, 0);

      final rows = await db.query(
        DatabaseTables.songArtistCredits,
        where: 'canonical_credited_name = ?',
        whereArgs: ['same artist'],
      );

      expect(rows.single['artist_id'], isNull);
    },
  );

  test('creates Artist identity for a new co-primary credit', () async {
    final credits = await service.replaceCredits(
      userId: 'user_1',
      songId: 'song_1',
      primaryArtistId: 'artist_madison',
      additionalCredits: const [
        SongArtistCreditInput(
          creditedName: 'Tate McRae',
          role: SongArtistCreditRole.coPrimary,
        ),
      ],
      now: DateTime.utc(2026, 10, 1, 15),
    );

    expect(credits, hasLength(2));
    expect(credits[1].role, SongArtistCreditRole.coPrimary);
    expect(credits[1].artistId, isNotNull);

    final artists = await db.query(DatabaseTables.artists);

    expect(artists, hasLength(2));

    final tate = artists.singleWhere(
      (row) => row['canonical_name'] == 'tate mcrae',
    );

    expect(tate['name'], 'Tate McRae');
    expect(credits[1].artistId, tate['id']);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.artist);
    expect(pending.single.entityId, tate['id']);
  });

  test('reuses existing Artist identity for a co-primary credit', () async {
    await _insertArtist(
      db,
      id: 'artist_tate',
      name: 'Tate McRae',
      canonicalName: 'tate mcrae',
    );

    final credits = await service.replaceCredits(
      userId: 'user_1',
      songId: 'song_1',
      primaryArtistId: 'artist_madison',
      additionalCredits: const [
        SongArtistCreditInput(
          creditedName: 'Tate McRae',
          role: SongArtistCreditRole.coPrimary,
        ),
      ],
    );

    expect(credits, hasLength(2));
    expect(credits[1].role, SongArtistCreditRole.coPrimary);
    expect(credits[1].artistId, 'artist_tate');

    final artists = await db.query(DatabaseTables.artists);
    expect(artists, hasLength(2));
  });

  test(
    'rejects ambiguous canonical identity for a co-primary credit',
    () async {
      await _insertArtist(
        db,
        id: 'artist_same_1',
        name: 'Same Artist',
        canonicalName: 'same artist',
      );

      await _insertArtist(
        db,
        id: 'artist_same_2',
        name: 'Same Artist',
        canonicalName: 'same artist',
      );

      await expectLater(
        () => service.replaceCredits(
          userId: 'user_1',
          songId: 'song_1',
          primaryArtistId: 'artist_madison',
          additionalCredits: const [
            SongArtistCreditInput(
              creditedName: 'Same Artist',
              role: SongArtistCreditRole.coPrimary,
            ),
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('ambiguous'),
          ),
        ),
      );

      final artists = await db.query(DatabaseTables.artists);
      expect(artists, hasLength(3));

      final credits = await db.query(DatabaseTables.songArtistCredits);
      expect(credits, isEmpty);

      expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
    },
  );
  test('explicit artist identity overrides name-based linking', () async {
    await _insertArtist(
      db,
      id: 'artist_guest',
      name: 'Official Guest',
      canonicalName: 'official guest',
    );

    final credits = await service.replaceCredits(
      userId: null,
      songId: 'song_1',
      primaryArtistId: 'artist_madison',
      additionalCredits: const [
        SongArtistCreditInput(
          creditedName: 'Displayed Guest Credit',
          role: SongArtistCreditRole.featured,
          artistId: 'artist_guest',
        ),
      ],
    );

    expect(credits[1].artistId, 'artist_guest');
    expect(credits[1].creditedName, 'Displayed Guest Credit');
  });
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
    'artist_id': 'artist_madison',
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
    'artist_id': 'artist_madison',
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
