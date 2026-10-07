import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/artist_merge_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_artist_credit_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late ArtistMergeService service;

  final originalTime = DateTime.utc(2026, 10, 7, 12);
  final mutationTime = DateTime.utc(2026, 10, 7, 13);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextOutboxId = 0;

    service = ArtistMergeService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'merge_outbox_${++nextOutboxId}',
        now: () => mutationTime,
      ),
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<Artist> createArtist(String name) async {
    final artist = EntityFactory.createArtist(name: name, now: originalTime);

    final db = await appDatabase.database;
    await ArtistDao(db).insert(artist);

    return artist;
  }

  Future<Album> createAlbum({
    required Artist artist,
    required String id,
    required String title,
  }) async {
    final album = Album(
      id: id,
      artistId: artist.id,
      title: title,
      canonicalTitle: title.toLowerCase(),
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final db = await appDatabase.database;
    await AlbumDao(db).insert(album);

    return album;
  }

  Future<AlbumEdition> createEdition({
    required Album album,
    required String id,
  }) async {
    final edition = AlbumEdition(
      id: id,
      albumId: album.id,
      title: album.title,
      type: AlbumEditionType.standard,
      isPrimary: true,
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final db = await appDatabase.database;
    await AlbumEditionDao(db).insert(edition);

    return edition;
  }

  Future<Song> createSong({
    required Artist artist,
    required Album album,
    required AlbumEdition edition,
    required String id,
    required String title,
    List<String> featuredArtists = const [],
  }) async {
    final song = Song(
      id: id,
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: title,
      canonicalTitle: title.toLowerCase(),
      trackNumber: 1,
      discNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      featuredArtists: featuredArtists,
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final db = await appDatabase.database;
    await SongDao(db).insert(song);

    return song;
  }

  test(
    'merges owned albums and songs into target permanent identity',
    () async {
      final source = await createArtist('Weeknd');
      final target = await createArtist('The Weeknd');

      final album = await createAlbum(
        artist: source,
        id: 'album-source',
        title: 'After Hours',
      );
      final edition = await createEdition(album: album, id: 'edition-source');
      final song = await createSong(
        artist: source,
        album: album,
        edition: edition,
        id: 'song-source',
        title: 'Blinding Lights',
      );

      final db = await appDatabase.database;

      await SongArtistCreditDao(db).insert(
        SongArtistCredit(
          id: 'credit-primary',
          songId: song.id,
          artistId: source.id,
          creditedName: source.name,
          canonicalCreditedName: source.canonicalName,
          role: SongArtistCreditRole.primary,
          position: 0,
          createdAt: originalTime,
          updatedAt: originalTime,
        ),
      );

      final result = await service.mergeArtists(
        userId: 'user-1',
        sourceArtistId: source.id,
        targetArtistId: target.id,
        now: mutationTime,
      );

      expect(result.sourceArtistId, source.id);
      expect(result.targetArtistId, target.id);
      expect(result.movedAlbumCount, 1);
      expect(result.movedPrimarySongCount, 1);

      expect(await ArtistDao(db).findById(source.id), isNull);
      expect(await ArtistDao(db).findById(target.id), isNotNull);

      final storedAlbum = await AlbumDao(db).findById(album.id);
      expect(storedAlbum, isNotNull);
      expect(storedAlbum!.artistId, target.id);

      final storedSong = await SongDao(db).findById(song.id);
      expect(storedSong, isNotNull);
      expect(storedSong!.artistId, target.id);

      final credits = await SongArtistCreditDao(db).findBySongId(song.id);
      expect(credits, hasLength(1));
      expect(credits.single.role, SongArtistCreditRole.primary);
      expect(credits.single.artistId, target.id);
      expect(credits.single.creditedName, target.name);

      final pending = await LocalSyncDao(db).findPending('user-1');

      expect(
        pending.any(
          (entry) =>
              entry.entityType == CloudDataEntity.album &&
              entry.entityId == album.id &&
              entry.operation == SyncOutboxOperation.upsert,
        ),
        isTrue,
      );

      expect(
        pending.any(
          (entry) =>
              entry.entityType == CloudDataEntity.song &&
              entry.entityId == song.id &&
              entry.operation == SyncOutboxOperation.upsert,
        ),
        isTrue,
      );

      expect(
        pending.any(
          (entry) =>
              entry.entityType == CloudDataEntity.artist &&
              entry.entityId == source.id &&
              entry.operation == SyncOutboxOperation.delete,
        ),
        isTrue,
      );
    },
  );

  test(
    'relinks collaboration credit without changing credited display name',
    () async {
      final primary = await createArtist('Primary Artist');
      final source = await createArtist('Guest Alias');
      final target = await createArtist('Official Guest');

      final album = await createAlbum(
        artist: primary,
        id: 'album-primary',
        title: 'Collaboration Album',
      );
      final edition = await createEdition(album: album, id: 'edition-primary');
      final song = await createSong(
        artist: primary,
        album: album,
        edition: edition,
        id: 'song-collaboration',
        title: 'Feature Song',
        featuredArtists: const ['Guest Alias'],
      );

      final db = await appDatabase.database;

      await SongArtistCreditDao(db).insert(
        SongArtistCredit(
          id: 'credit-primary',
          songId: song.id,
          artistId: primary.id,
          creditedName: primary.name,
          canonicalCreditedName: primary.canonicalName,
          role: SongArtistCreditRole.primary,
          position: 0,
          createdAt: originalTime,
          updatedAt: originalTime,
        ),
      );

      await SongArtistCreditDao(db).insert(
        SongArtistCredit(
          id: 'credit-feature',
          songId: song.id,
          artistId: source.id,
          creditedName: 'Guest Alias',
          canonicalCreditedName: 'guest alias',
          role: SongArtistCreditRole.featured,
          position: 1,
          createdAt: originalTime,
          updatedAt: originalTime,
        ),
      );

      final result = await service.mergeArtists(
        userId: 'user-1',
        sourceArtistId: source.id,
        targetArtistId: target.id,
        now: mutationTime,
      );

      expect(result.relinkedCreditCount, 1);
      expect(await ArtistDao(db).findById(source.id), isNull);

      final credits = await SongArtistCreditDao(db).findBySongId(song.id);
      final feature = credits.singleWhere(
        (credit) => credit.role == SongArtistCreditRole.featured,
      );

      expect(feature.artistId, target.id);
      expect(feature.creditedName, 'Guest Alias');
      expect(feature.canonicalCreditedName, 'guest alias');
    },
  );

  test('rejects album collision without mutating either identity', () async {
    final source = await createArtist('Duplicate Artist');
    final target = await createArtist('Canonical Artist');

    await createAlbum(
      artist: source,
      id: 'album-source',
      title: 'Shared Album',
    );

    await createAlbum(
      artist: target,
      id: 'album-target',
      title: 'Shared Album',
    );

    await expectLater(
      () => service.mergeArtists(
        userId: 'user-1',
        sourceArtistId: source.id,
        targetArtistId: target.id,
        now: mutationTime,
      ),
      throwsA(isA<ArtistMergeAlbumCollisionException>()),
    );

    final db = await appDatabase.database;

    expect(await ArtistDao(db).findById(source.id), isNotNull);
    expect(await ArtistDao(db).findById(target.id), isNotNull);

    expect((await AlbumDao(db).findById('album-source'))!.artistId, source.id);
    expect((await AlbumDao(db).findById('album-target'))!.artistId, target.id);

    expect(await LocalSyncDao(db).findPending('user-1'), isEmpty);
  });

  test('rejects merging an artist into itself', () async {
    final artist = await createArtist('Artist');

    await expectLater(
      () => service.mergeArtists(
        userId: 'user-1',
        sourceArtistId: artist.id,
        targetArtistId: artist.id,
      ),
      throwsA(isA<ArtistMergeSameIdentityException>()),
    );
  });

  test(
    'rejects collaboration merge when song already references target',
    () async {
      final primary = await createArtist('Primary Artist');
      final source = await createArtist('Guest Alias');
      final target = await createArtist('Official Guest');

      final album = await createAlbum(
        artist: primary,
        id: 'album-credit-collision',
        title: 'Credit Collision Album',
      );
      final edition = await createEdition(
        album: album,
        id: 'edition-credit-collision',
      );
      final song = await createSong(
        artist: primary,
        album: album,
        edition: edition,
        id: 'song-credit-collision',
        title: 'Collision Song',
      );

      final db = await appDatabase.database;

      await SongArtistCreditDao(db).insert(
        SongArtistCredit(
          id: 'credit-source',
          songId: song.id,
          artistId: source.id,
          creditedName: source.name,
          canonicalCreditedName: source.canonicalName,
          role: SongArtistCreditRole.featured,
          position: 1,
          createdAt: originalTime,
          updatedAt: originalTime,
        ),
      );

      await SongArtistCreditDao(db).insert(
        SongArtistCredit(
          id: 'credit-target',
          songId: song.id,
          artistId: target.id,
          creditedName: target.name,
          canonicalCreditedName: target.canonicalName,
          role: SongArtistCreditRole.guest,
          position: 2,
          createdAt: originalTime,
          updatedAt: originalTime,
        ),
      );

      await expectLater(
        () => service.mergeArtists(
          userId: 'user-1',
          sourceArtistId: source.id,
          targetArtistId: target.id,
          now: mutationTime,
        ),
        throwsA(isA<ArtistMergeCreditCollisionException>()),
      );

      expect(await ArtistDao(db).findById(source.id), isNotNull);

      final credits = await SongArtistCreditDao(db).findBySongId(song.id);

      expect(
        credits.singleWhere((credit) => credit.id == 'credit-source').artistId,
        source.id,
      );
      expect(
        credits.singleWhere((credit) => credit.id == 'credit-target').artistId,
        target.id,
      );

      expect(await LocalSyncDao(db).findPending('user-1'), isEmpty);
    },
  );

  test(
    'links unique unlinked target credits after source identity is removed',
    () async {
      final source = await createArtist('Alias Name');
      final target = await createArtist('Official Artist');

      final primary = await createArtist('Primary Artist');

      final album = await createAlbum(
        artist: primary,
        id: 'album-unlinked',
        title: 'Unlinked Album',
      );
      final edition = await createEdition(album: album, id: 'edition-unlinked');
      final song = await createSong(
        artist: primary,
        album: album,
        edition: edition,
        id: 'song-unlinked',
        title: 'Unlinked Credit Song',
      );

      final db = await appDatabase.database;

      await SongArtistCreditDao(db).insert(
        SongArtistCredit(
          id: 'credit-unlinked',
          songId: song.id,
          artistId: null,
          creditedName: target.name,
          canonicalCreditedName: target.canonicalName,
          role: SongArtistCreditRole.featured,
          position: 1,
          createdAt: originalTime,
          updatedAt: originalTime,
        ),
      );

      final result = await service.mergeArtists(
        userId: 'user-1',
        sourceArtistId: source.id,
        targetArtistId: target.id,
        now: mutationTime,
      );

      expect(result.linkedUnlinkedCreditCount, 1);

      final credit = await SongArtistCreditDao(db).findById('credit-unlinked');

      expect(credit, isNotNull);
      expect(credit!.artistId, target.id);
    },
  );

  test('structured credit failure rolls back entire artist merge', () async {
    final source = await createArtist('Source Artist');
    final target = await createArtist('Target Artist');

    final album = await createAlbum(
      artist: source,
      id: 'album-rollback',
      title: 'Rollback Album',
    );
    final edition = await createEdition(album: album, id: 'edition-rollback');
    final song = await createSong(
      artist: source,
      album: album,
      edition: edition,
      id: 'song-rollback',
      title: 'Rollback Song',
    );

    final db = await appDatabase.database;

    await SongArtistCreditDao(db).insert(
      SongArtistCredit(
        id: 'credit-rollback-primary',
        songId: song.id,
        artistId: source.id,
        creditedName: source.name,
        canonicalCreditedName: source.canonicalName,
        role: SongArtistCreditRole.primary,
        position: 0,
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    await db.execute('''
      CREATE TRIGGER fail_merge_credit_insert
      BEFORE INSERT ON ${DatabaseTables.songArtistCredits}
      BEGIN
        SELECT RAISE(ABORT, 'forced merge credit failure');
      END
    ''');

    await expectLater(
      () => service.mergeArtists(
        userId: 'user-1',
        sourceArtistId: source.id,
        targetArtistId: target.id,
        now: mutationTime,
      ),
      throwsA(anything),
    );

    final storedSource = await ArtistDao(db).findById(source.id);
    final storedTarget = await ArtistDao(db).findById(target.id);
    final storedAlbum = await AlbumDao(db).findById(album.id);
    final storedSong = await SongDao(db).findById(song.id);
    final credits = await SongArtistCreditDao(db).findBySongId(song.id);

    expect(storedSource, isNotNull);
    expect(storedTarget, isNotNull);

    expect(storedAlbum, isNotNull);
    expect(storedAlbum!.artistId, source.id);

    expect(storedSong, isNotNull);
    expect(storedSong!.artistId, source.id);

    expect(credits, hasLength(1));
    expect(credits.single.artistId, source.id);

    expect(await LocalSyncDao(db).findPending('user-1'), isEmpty);
  });

  test('remaps historical playback artist identity to merge target', () async {
    final source = await createArtist('Old Artist');
    final target = await createArtist('New Artist');

    final db = await appDatabase.database;

    await db.insert(DatabaseTables.playbackSessions, {
      'id': 'playback-merge',
      'user_id': null,
      'song_id': 'historical-song',
      'artist_id': source.id,
      'album_id': 'historical-album',
      'album_edition_id': 'historical-edition',
      'song_title': 'Historical Song',
      'artist_name': source.name,
      'album_title': 'Historical Album',
      'album_edition_title': 'Standard',
      'started_at': originalTime.toIso8601String(),
      'ended_at': mutationTime.toIso8601String(),
      'listened_duration_ms': 180000,
      'track_duration_ms': 180000,
      'final_position_ms': 180000,
      'end_reason': 'completed',
      'source_context': 'merge-test',
      'created_at': originalTime.toIso8601String(),
      'updated_at': originalTime.toIso8601String(),
    });

    await service.mergeArtists(
      userId: 'user-1',
      sourceArtistId: source.id,
      targetArtistId: target.id,
      now: mutationTime,
    );

    final rows = await db.query(
      DatabaseTables.playbackSessions,
      where: 'id = ?',
      whereArgs: ['playback-merge'],
    );

    expect(rows, hasLength(1));
    expect(rows.single['artist_id'], target.id);
    expect(rows.single['artist_name'], target.name);
  });
}
