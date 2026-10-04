import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/malformed_artist_identity_repair_service.dart';
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
  late MalformedArtistIdentityRepairService service;

  final originalTime = DateTime.utc(2026, 10, 3, 12);
  final repairTime = DateTime.utc(2026, 10, 3, 13);
  final weekStart = DateTime.utc(2026, 9, 28);
  final weekEnd = DateTime.utc(2026, 10, 5);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextOutboxId = 0;

    service = MalformedArtistIdentityRepairService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'outbox_${++nextOutboxId}',
        now: () => repairTime,
      ),
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<Artist> insertArtist(String name) async {
    final artist = EntityFactory.createArtist(name: name, now: originalTime);

    final db = await appDatabase.database;
    await ArtistDao(db).insert(artist);

    return artist;
  }

  Future<Album> insertAlbum({
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

  Future<AlbumEdition> insertEdition(Album album) async {
    final edition = AlbumEdition(
      id: '${album.id}-edition',
      albumId: album.id,
      title: 'Standard',
      type: AlbumEditionType.standard,
      isPrimary: true,
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final db = await appDatabase.database;
    await AlbumEditionDao(db).insert(edition);

    return edition;
  }

  Future<Song> insertSong({
    required Artist artist,
    required Album album,
    required AlbumEdition edition,
  }) async {
    final song = Song(
      id: 'song-1',
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: 'Test Song',
      canonicalTitle: 'test song',
      trackNumber: 1,
      discNumber: 1,
      durationSeconds: 200,
      isSingle: false,
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final db = await appDatabase.database;
    await SongDao(db).insert(song);

    await SongArtistCreditDao(db).insert(
      SongArtistCredit(
        id: 'credit-primary',
        songId: song.id,
        artistId: artist.id,
        creditedName: artist.name,
        canonicalCreditedName: artist.canonicalName,
        role: SongArtistCreditRole.primary,
        position: 0,
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    return song;
  }

  Future<void> insertHistoricalRows({
    required Artist sourceArtist,
    required Album album,
    required AlbumEdition edition,
    required Song song,
  }) async {
    final db = await appDatabase.database;

    await db.insert(DatabaseTables.playbackSessions, <String, Object?>{
      'id': 'session-1',
      'user_id': 'user_1',
      'song_id': song.id,
      'artist_id': sourceArtist.id,
      'album_id': album.id,
      'album_edition_id': edition.id,
      'song_title': song.title,
      'artist_name': sourceArtist.name,
      'album_title': album.title,
      'album_edition_title': edition.title,
      'started_at': originalTime.toIso8601String(),
      'ended_at': originalTime
          .add(const Duration(minutes: 3))
          .toIso8601String(),
      'listened_duration_ms': 180000,
      'track_duration_ms': 200000,
      'final_position_ms': 180000,
      'end_reason': 'stopped',
      'created_at': originalTime.toIso8601String(),
      'updated_at': originalTime.toIso8601String(),
    });

    await db.insert(DatabaseTables.qualifiedPlays, <String, Object?>{
      'id': 'qualified-1',
      'playback_session_id': 'session-1',
      'user_id': 'user_1',
      'song_id': song.id,
      'artist_id': sourceArtist.id,
      'album_id': album.id,
      'album_edition_id': edition.id,
      'qualified_at': originalTime
          .add(const Duration(seconds: 30))
          .toIso8601String(),
      'listened_duration_ms': 180000,
      'track_duration_ms': 200000,
      'created_at': originalTime.toIso8601String(),
    });

    await db.insert(DatabaseTables.chartSnapshots, <String, Object?>{
      'id': 'snapshot-1',
      'chart_type': 'songs',
      'week_start_utc': weekStart.toIso8601String(),
      'week_end_utc': weekEnd.toIso8601String(),
      'revision': 1,
      'created_at': originalTime.toIso8601String(),
      'updated_at': originalTime.toIso8601String(),
    });

    await db.insert(DatabaseTables.chartEntries, <String, Object?>{
      'id': 'chart-entry-1',
      'chart_snapshot_id': 'snapshot-1',
      'entity_id': song.id,
      'title': song.title,
      'artist_id': sourceArtist.id,
      'artist_name': sourceArtist.name,
      'album_title': album.title,
      'rank': 1,
      'qualified_stream_count': 1,
      'peak_rank': 1,
      'peak_achieved_at': originalTime.toIso8601String(),
      'weeks_on_chart': 1,
      'movement': 'newEntry',
      'last_qualified_at': originalTime.toIso8601String(),
      'created_at': originalTime.toIso8601String(),
      'updated_at': originalTime.toIso8601String(),
    });

    await db.insert(DatabaseTables.chartMomentEvents, <String, Object?>{
      'id': 'moment-1',
      'deduplication_key': 'moment-1-key',
      'user_id': 'user_1',
      'chart_type': 'songs',
      'scope': 'finalized',
      'event_type': 'test',
      'entity_id': song.id,
      'entity_title': song.title,
      'entity_artist_id': sourceArtist.id,
      'entity_artist_name': sourceArtist.name,
      'entity_album_title': album.title,
      'related_entity_id': album.id,
      'related_entity_title': album.title,
      'related_entity_artist_id': sourceArtist.id,
      'related_entity_artist_name': sourceArtist.name,
      'related_entity_album_title': album.title,
      'week_start_utc': weekStart.toIso8601String(),
      'week_end_utc': weekEnd.toIso8601String(),
      'occurred_at': originalTime.toIso8601String(),
      'created_at': originalTime.toIso8601String(),
    });
  }

  test('repairs malformed feature artist identity end to end', () async {
    final targetArtist = await insertArtist('Beyonce');
    final sourceArtist = await insertArtist('Beyonce [Ft. Jack White]');

    final album = await insertAlbum(
      artist: sourceArtist,
      id: 'album-1',
      title: 'Repair Album',
    );

    final edition = await insertEdition(album);

    final song = await insertSong(
      artist: sourceArtist,
      album: album,
      edition: edition,
    );

    await insertHistoricalRows(
      sourceArtist: sourceArtist,
      album: album,
      edition: edition,
      song: song,
    );

    final result = await service.repairArtist(
      userId: ' user_1 ',
      artistId: sourceArtist.id,
      now: repairTime,
    );

    expect(result.status, ArtistIdentityRepairStatus.repaired);
    expect(result.targetArtistId, targetArtist.id);
    expect(result.repairedAlbumCount, 1);
    expect(result.repairedSongCount, 1);

    final db = await appDatabase.database;

    expect(await ArtistDao(db).findById(sourceArtist.id), isNull);

    final storedAlbum = await AlbumDao(db).findById(album.id);
    expect(storedAlbum!.artistId, targetArtist.id);

    final storedSong = await SongDao(db).findById(song.id);
    expect(storedSong!.artistId, targetArtist.id);
    expect(storedSong.featuredArtists, ['Jack White']);

    final credits = await SongArtistCreditDao(db).findBySongId(song.id);

    expect(credits, hasLength(2));
    expect(credits[0].role, SongArtistCreditRole.primary);
    expect(credits[0].artistId, targetArtist.id);
    expect(credits[1].role, SongArtistCreditRole.featured);
    expect(credits[1].creditedName, 'Jack White');

    final playback = await db.query(
      DatabaseTables.playbackSessions,
      where: 'id = ?',
      whereArgs: ['session-1'],
    );

    expect(playback.single['artist_id'], targetArtist.id);
    expect(playback.single['artist_name'], targetArtist.name);

    final qualified = await db.query(
      DatabaseTables.qualifiedPlays,
      where: 'id = ?',
      whereArgs: ['qualified-1'],
    );

    expect(qualified.single['artist_id'], targetArtist.id);

    final chartEntry = await db.query(
      DatabaseTables.chartEntries,
      where: 'id = ?',
      whereArgs: ['chart-entry-1'],
    );

    expect(chartEntry.single['artist_id'], targetArtist.id);
    expect(chartEntry.single['artist_name'], targetArtist.name);

    final moment = await db.query(
      DatabaseTables.chartMomentEvents,
      where: 'id = ?',
      whereArgs: ['moment-1'],
    );

    expect(moment.single['entity_artist_id'], targetArtist.id);
    expect(moment.single['entity_artist_name'], targetArtist.name);
    expect(moment.single['related_entity_artist_id'], targetArtist.id);
    expect(moment.single['related_entity_artist_name'], targetArtist.name);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(3));

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
            entry.entityId == sourceArtist.id &&
            entry.operation == SyncOutboxOperation.delete,
      ),
      isTrue,
    );

    final secondResult = await service.repairArtist(
      userId: 'user_1',
      artistId: sourceArtist.id,
      now: repairTime,
    );

    expect(secondResult.status, ArtistIdentityRepairStatus.sourceMissing);
    expect(secondResult.sourceArtistId, sourceArtist.id);

    final pendingAfterSecondRun = await LocalSyncDao(db).findPending('user_1');

    expect(pendingAfterSecondRun, hasLength(3));
  });

  test('does not repair when clean primary artist is missing', () async {
    final sourceArtist = await insertArtist('Beyonce [Ft. Jack White]');

    final result = await service.repairArtist(
      userId: 'user_1',
      artistId: sourceArtist.id,
      now: repairTime,
    );

    expect(result.status, ArtistIdentityRepairStatus.primaryArtistMissing);

    final db = await appDatabase.database;
    expect(await ArtistDao(db).findById(sourceArtist.id), isNotNull);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('does not repair ambiguous clean primary identity', () async {
    await insertArtist('Beyonce');
    await insertArtist('Beyonce');

    final sourceArtist = await insertArtist('Beyonce [Ft. Jack White]');

    final result = await service.repairArtist(
      userId: 'user_1',
      artistId: sourceArtist.id,
      now: repairTime,
    );

    expect(result.status, ArtistIdentityRepairStatus.primaryArtistAmbiguous);
  });

  test('refuses to merge into a malformed target artist', () async {
    final targetArtist = await insertArtist('Beyonce [Ft. Existing Guest]');

    final sourceArtist = await insertArtist('Beyonce [Ft. Jack White]');

    final db = await appDatabase.database;

    await db.update(
      DatabaseTables.artists,
      <String, Object?>{'canonical_name': 'beyonce'},
      where: 'id = ?',
      whereArgs: <Object?>[targetArtist.id],
    );

    final result = await service.repairArtist(
      userId: 'user_1',
      artistId: sourceArtist.id,
      now: repairTime,
    );

    expect(result.status, ArtistIdentityRepairStatus.targetArtistMalformed);
    expect(result.sourceArtistId, sourceArtist.id);
    expect(result.targetArtistId, targetArtist.id);

    expect(await ArtistDao(db).findById(sourceArtist.id), isNotNull);
    expect(await ArtistDao(db).findById(targetArtist.id), isNotNull);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });
  test('preserves legacy featured artists during identity repair', () async {
    final targetArtist = await insertArtist('Beyonce');
    final sourceArtist = await insertArtist('Beyonce [Ft. Jack White]');

    final album = await insertAlbum(
      artist: sourceArtist,
      id: 'legacy-feature-album',
      title: 'Legacy Feature Album',
    );

    final edition = await insertEdition(album);

    final song = Song(
      id: 'legacy-feature-song',
      artistId: sourceArtist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: 'Legacy Feature Song',
      canonicalTitle: 'legacy feature song',
      trackNumber: 1,
      discNumber: 1,
      durationSeconds: 200,
      isSingle: false,
      featuredArtists: const ['Existing Guest'],
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final db = await appDatabase.database;
    await SongDao(db).insert(song);

    await SongArtistCreditDao(db).insert(
      SongArtistCredit(
        id: 'legacy-feature-primary',
        songId: song.id,
        artistId: sourceArtist.id,
        creditedName: sourceArtist.name,
        canonicalCreditedName: sourceArtist.canonicalName,
        role: SongArtistCreditRole.primary,
        position: 0,
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    final result = await service.repairArtist(
      userId: 'user_1',
      artistId: sourceArtist.id,
      now: repairTime,
    );

    expect(result.status, ArtistIdentityRepairStatus.repaired);

    final storedSong = await SongDao(db).findById(song.id);

    expect(
      storedSong!.featuredArtists,
      containsAll(<String>['Existing Guest', 'Jack White']),
    );

    final credits = await SongArtistCreditDao(db).findBySongId(song.id);

    expect(
      credits
          .where((credit) => credit.role == SongArtistCreditRole.featured)
          .map((credit) => credit.creditedName),
      containsAll(<String>['Existing Guest', 'Jack White']),
    );

    expect(await ArtistDao(db).findById(targetArtist.id), isNotNull);
  });
  test('does not repair when album identity would collide', () async {
    final targetArtist = await insertArtist('Beyonce');
    final sourceArtist = await insertArtist('Beyonce [Ft. Jack White]');

    await insertAlbum(
      artist: targetArtist,
      id: 'target-album',
      title: 'Same Album',
    );

    await insertAlbum(
      artist: sourceArtist,
      id: 'source-album',
      title: 'Same Album',
    );

    final result = await service.repairArtist(
      userId: 'user_1',
      artistId: sourceArtist.id,
      now: repairTime,
    );

    expect(result.status, ArtistIdentityRepairStatus.albumCollision);

    final db = await appDatabase.database;
    expect(await ArtistDao(db).findById(sourceArtist.id), isNotNull);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });
}
