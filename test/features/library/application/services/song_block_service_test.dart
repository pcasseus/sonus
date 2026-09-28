import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_session_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/qualified_play_dao.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_session_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_qualified_play_repository.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/library/application/services/song_block_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SongBlockService service;

  final originalTime = DateTime.utc(2026, 9, 26, 10);
  final mutationTime = DateTime.utc(2026, 9, 26, 11);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextOutboxId = 0;

    service = SongBlockService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'outbox_${++nextOutboxId}',
        now: () => mutationTime,
      ),
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<String> createSong() async {
    final db = await appDatabase.database;

    const artistId = 'artist_song_block_service';
    const albumId = 'album_song_block_service';
    const editionId = 'edition_song_block_service';
    const songId = 'song_block_service';

    await ArtistDao(db).insert(
      Artist(
        id: artistId,
        name: 'Block Artist',
        canonicalName: 'block artist',
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    await AlbumDao(db).insert(
      Album(
        id: albumId,
        artistId: artistId,
        title: 'Block Album',
        canonicalTitle: 'block album',
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    await AlbumEditionDao(db).insert(
      AlbumEdition(
        id: editionId,
        albumId: albumId,
        title: 'Block Album',
        type: AlbumEditionType.standard,
        isPrimary: true,
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    await SongDao(db).insert(
      Song(
        id: songId,
        artistId: artistId,
        albumId: albumId,
        albumEditionId: editionId,
        title: 'Block Song',
        canonicalTitle: 'block song',
        trackNumber: 1,
        durationSeconds: 180,
        isSingle: false,
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    return songId;
  }

  test('blocks song and records cloud upsert atomically', () async {
    final songId = await createSong();

    final result = await service.setBlocked(
      userId: ' user_1 ',
      songId: songId,
      isBlocked: true,
      now: mutationTime,
    );

    expect(result.id, songId);
    expect(result.isBlocked, isTrue);
    expect(result.updatedAt, mutationTime);

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(songId);

    expect(stored, isNotNull);
    expect(stored!.isBlocked, isTrue);
    expect(stored.updatedAt, mutationTime);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.song);
    expect(pending.single.entityId, songId);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test(
    'signed-out blocking updates locally without creating an outbox entry',
    () async {
      final songId = await createSong();

      final result = await service.setBlocked(
        songId: songId,
        isBlocked: true,
        now: mutationTime,
      );

      expect(result.id, songId);
      expect(result.isBlocked, isTrue);
      expect(result.updatedAt, mutationTime);

      final db = await appDatabase.database;
      final stored = await SongDao(db).findById(songId);

      expect(stored, isNotNull);
      expect(stored!.isBlocked, isTrue);
      expect(stored.updatedAt, mutationTime);

      final outboxRows = await db.query('sync_outbox');

      expect(outboxRows, isEmpty);
    },
  );
  test('unblocks song and keeps the same permanent identity', () async {
    final songId = await createSong();

    await service.setBlocked(
      userId: 'user_1',
      songId: songId,
      isBlocked: true,
      now: mutationTime,
    );

    final unblockTime = mutationTime.add(const Duration(minutes: 1));

    final result = await service.setBlocked(
      userId: 'user_1',
      songId: songId,
      isBlocked: false,
      now: unblockTime,
    );

    expect(result.id, songId);
    expect(result.isBlocked, isFalse);
    expect(result.updatedAt, unblockTime);

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(songId);

    expect(stored, isNotNull);
    expect(stored!.id, songId);
    expect(stored.isBlocked, isFalse);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.song);
    expect(pending.single.entityId, songId);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test('blocking and unblocking preserve historical analytics', () async {
    final songId = await createSong();
    final db = await appDatabase.database;

    final playbackSessions = SqlitePlaybackSessionRepository(
      PlaybackSessionDao(db),
    );
    final qualifiedPlays = SqliteQualifiedPlayRepository(QualifiedPlayDao(db));

    const artistId = 'artist_song_block_service';
    const albumId = 'album_song_block_service';
    const editionId = 'edition_song_block_service';

    final startedAt = originalTime.add(const Duration(minutes: 5));
    final endedAt = startedAt.add(const Duration(minutes: 2));

    final session = PlaybackSession(
      id: 'session_block_history',
      userId: 'user_1',
      songId: songId,
      artistId: artistId,
      albumId: albumId,
      albumEditionId: editionId,
      songTitle: 'Block Song',
      artistName: 'Block Artist',
      albumTitle: 'Block Album',
      albumEditionTitle: 'Block Album',
      startedAt: startedAt,
      endedAt: endedAt,
      listenedDuration: const Duration(seconds: 45),
      trackDuration: const Duration(minutes: 3),
      finalPosition: const Duration(seconds: 45),
      endReason: PlaybackSessionEndReason.skipped,
      sourceContext: 'library',
      createdAt: startedAt,
      updatedAt: endedAt,
    );

    await playbackSessions.create(session);

    final play = QualifiedPlay(
      id: 'play_block_history',
      playbackSessionId: session.id,
      userId: 'user_1',
      songId: songId,
      artistId: artistId,
      albumId: albumId,
      albumEditionId: editionId,
      qualifiedAt: startedAt.add(const Duration(seconds: 30)),
      listenedDuration: const Duration(seconds: 30),
      trackDuration: const Duration(minutes: 3),
      createdAt: startedAt.add(const Duration(seconds: 30)),
    );

    await qualifiedPlays.create(play);

    await service.setBlocked(
      userId: 'user_1',
      songId: songId,
      isBlocked: true,
      now: mutationTime,
    );

    await service.setBlocked(
      userId: 'user_1',
      songId: songId,
      isBlocked: false,
      now: mutationTime.add(const Duration(minutes: 1)),
    );

    final restoredSession = await playbackSessions.getById(session.id);
    final restoredPlay = await qualifiedPlays.getByPlaybackSessionId(
      session.id,
    );

    expect(restoredSession, isNotNull);
    expect(restoredSession!.id, session.id);
    expect(restoredSession.songId, songId);
    expect(restoredSession.listenedDuration, const Duration(seconds: 45));
    expect(restoredSession.endReason, PlaybackSessionEndReason.skipped);

    expect(restoredPlay, isNotNull);
    expect(restoredPlay!.id, play.id);
    expect(restoredPlay.songId, songId);
    expect(restoredPlay.listenedDuration, const Duration(seconds: 30));
  });

  test('missing song fails without creating an outbox entry', () async {
    await expectLater(
      service.setBlocked(
        userId: 'user_1',
        songId: 'song_missing',
        isBlocked: true,
        now: mutationTime,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Song not found: song_missing',
        ),
      ),
    );

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rejects blank user id before mutation', () async {
    final songId = await createSong();

    await expectLater(
      () => service.setBlocked(
        userId: '   ',
        songId: songId,
        isBlocked: true,
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(songId);

    expect(stored, isNotNull);
    expect(stored!.isBlocked, isFalse);
    expect(await LocalSyncDao(db).findPending(''), isEmpty);
  });

  test('rejects blank song id before mutation', () async {
    await expectLater(
      () => service.setBlocked(
        userId: 'user_1',
        songId: '   ',
        isBlocked: true,
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });
}
