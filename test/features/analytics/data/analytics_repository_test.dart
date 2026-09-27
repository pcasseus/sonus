import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/schema/analytics_schema.dart';
import 'package:sonus_next/core/database/schema/library_schema.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_session_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/qualified_play_dao.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_session_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_qualified_play_repository.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late SqlitePlaybackSessionRepository playbackSessions;
  late SqliteQualifiedPlayRepository qualifiedPlays;

  const artistId = 'artist_analytics_repo';
  const albumId = 'album_analytics_repo';
  const editionId = 'edition_analytics_repo';
  const songId = 'song_analytics_repo';

  final seedTime = DateTime.utc(2026, 9, 25, 12);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await LibrarySchema.create(db);
          await AnalyticsSchema.create(db);
        },
      ),
    );

    playbackSessions = SqlitePlaybackSessionRepository(
      PlaybackSessionDao(database),
    );

    qualifiedPlays = SqliteQualifiedPlayRepository(QualifiedPlayDao(database));

    final now = seedTime.toIso8601String();

    await database.insert(DatabaseTables.artists, {
      'id': artistId,
      'name': 'Repository Artist',
      'canonical_name': 'repository artist',
      'is_blacklisted': 0,
      'created_at': now,
      'updated_at': now,
    });

    await database.insert(DatabaseTables.albums, {
      'id': albumId,
      'artist_id': artistId,
      'title': 'Repository Album',
      'canonical_title': 'repository album',
      'created_at': now,
      'updated_at': now,
    });

    await database.insert(DatabaseTables.albumEditions, {
      'id': editionId,
      'album_id': albumId,
      'title': 'Repository Album',
      'type': 'standard',
      'is_primary': 1,
      'created_at': now,
      'updated_at': now,
    });

    await database.insert(DatabaseTables.songs, {
      'id': songId,
      'artist_id': artistId,
      'album_id': albumId,
      'album_edition_id': editionId,
      'title': 'Repository Song',
      'canonical_title': 'repository song',
      'track_number': 1,
      'disc_number': 1,
      'duration_seconds': 240,
      'is_single': 0,
      'featured_artists': '[]',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await database.close();
  });

  PlaybackSession session({
    required String id,
    required DateTime startedAt,
    String? userId,
    Duration listenedDuration = Duration.zero,
    Duration finalPosition = Duration.zero,
    DateTime? endedAt,
    PlaybackSessionEndReason? endReason,
    String? sourceContext = 'library',
  }) {
    return PlaybackSession(
      id: id,
      userId: userId,
      songId: songId,
      artistId: artistId,
      albumId: albumId,
      albumEditionId: editionId,
      songTitle: 'Repository Song',
      artistName: 'Repository Artist',
      albumTitle: 'Repository Album',
      albumEditionTitle: 'Repository Album',
      startedAt: startedAt,
      endedAt: endedAt,
      listenedDuration: listenedDuration,
      trackDuration: const Duration(minutes: 4),
      finalPosition: finalPosition,
      endReason: endReason,
      sourceContext: sourceContext,
      createdAt: startedAt,
      updatedAt: endedAt ?? startedAt,
    );
  }

  QualifiedPlay play({
    required String id,
    required String playbackSessionId,
    required DateTime qualifiedAt,
    String? userId,
  }) {
    return QualifiedPlay(
      id: id,
      playbackSessionId: playbackSessionId,
      userId: userId,
      songId: songId,
      artistId: artistId,
      albumId: albumId,
      albumEditionId: editionId,
      qualifiedAt: qualifiedAt,
      listenedDuration: const Duration(seconds: 30),
      trackDuration: const Duration(minutes: 4),
      createdAt: qualifiedAt,
    );
  }

  test('playback session round trips while signed out', () async {
    final original = session(
      id: 'session_round_trip',
      startedAt: seedTime,
      listenedDuration: const Duration(seconds: 18),
      finalPosition: const Duration(seconds: 18),
    );

    await playbackSessions.create(original);

    final restored = await playbackSessions.getById(original.id);

    expect(restored, isNotNull);
    expect(restored!.id, original.id);
    expect(restored.userId, isNull);
    expect(restored.songId, songId);
    expect(restored.artistId, artistId);
    expect(restored.albumId, albumId);
    expect(restored.albumEditionId, editionId);
    expect(restored.songTitle, 'Repository Song');
    expect(restored.artistName, 'Repository Artist');
    expect(restored.albumTitle, 'Repository Album');
    expect(restored.albumEditionTitle, 'Repository Album');
    expect(restored.startedAt, seedTime);
    expect(restored.endedAt, isNull);
    expect(restored.listenedDuration, const Duration(seconds: 18));
    expect(restored.finalPosition, const Duration(seconds: 18));
    expect(restored.trackDuration, const Duration(minutes: 4));
    expect(restored.sourceContext, 'library');
    expect(restored.isEnded, isFalse);
  });

  test('playback session can be updated when listening ends', () async {
    final original = session(id: 'session_update', startedAt: seedTime);

    await playbackSessions.create(original);

    final endedAt = seedTime.add(const Duration(seconds: 47));

    final ended = original.copyWith(
      endedAt: endedAt,
      listenedDuration: const Duration(seconds: 41),
      finalPosition: const Duration(seconds: 52),
      endReason: PlaybackSessionEndReason.skipped,
      updatedAt: endedAt,
    );

    await playbackSessions.save(ended);

    final restored = await playbackSessions.getById(original.id);

    expect(restored, isNotNull);
    expect(restored!.isEnded, isTrue);
    expect(restored.endedAt, endedAt);
    expect(restored.listenedDuration, const Duration(seconds: 41));
    expect(restored.finalPosition, const Duration(seconds: 52));
    expect(restored.endReason, PlaybackSessionEndReason.skipped);
    expect(restored.updatedAt, endedAt);
  });

  test('saving a missing playback session fails loudly', () async {
    final missing = session(id: 'session_missing', startedAt: seedTime);

    await expectLater(
      playbackSessions.save(missing),
      throwsA(isA<StateError>()),
    );
  });

  test('playback session range query uses half-open boundaries', () async {
    final first = session(
      id: 'session_first',
      startedAt: DateTime.utc(2026, 9, 21, 0),
    );

    final middle = session(
      id: 'session_middle',
      startedAt: DateTime.utc(2026, 9, 24, 12),
    );

    final boundary = session(
      id: 'session_boundary',
      startedAt: DateTime.utc(2026, 9, 28, 0),
    );

    await playbackSessions.create(first);
    await playbackSessions.create(middle);
    await playbackSessions.create(boundary);

    final results = await playbackSessions.getAll(
      startedAtOrAfter: DateTime.utc(2026, 9, 21),
      startedBefore: DateTime.utc(2026, 9, 28),
    );

    expect(results.map((value) => value.id), [
      'session_first',
      'session_middle',
    ]);
  });

  test('row persistence normalizes timestamps to UTC', () async {
    final localOffsetTime = DateTime.parse('2026-09-25T08:30:00-04:00');

    await playbackSessions.create(
      session(id: 'session_utc', startedAt: localOffsetTime),
    );

    final rawRows = await database.query(
      DatabaseTables.playbackSessions,
      where: 'id = ?',
      whereArgs: ['session_utc'],
    );

    expect(rawRows, hasLength(1));
    expect(rawRows.single['started_at'], '2026-09-25T12:30:00.000Z');

    final restored = await playbackSessions.getById('session_utc');

    expect(restored, isNotNull);
    expect(restored!.startedAt.isUtc, isTrue);
    expect(restored.startedAt, DateTime.utc(2026, 9, 25, 12, 30));
  });

  test('getOpen returns only unfinished playback sessions', () async {
    final open = session(id: 'session_open', startedAt: seedTime);

    final closed = session(
      id: 'session_closed',
      startedAt: seedTime.add(const Duration(minutes: 1)),
      endedAt: seedTime.add(const Duration(minutes: 2)),
      endReason: PlaybackSessionEndReason.stopped,
    );

    await playbackSessions.create(open);
    await playbackSessions.create(closed);

    final results = await playbackSessions.getOpen();

    expect(results.map((value) => value.id), ['session_open']);
  });
  test('qualified play round trips and can be found by session id', () async {
    final playbackSession = session(
      id: 'session_for_play',
      startedAt: seedTime,
      listenedDuration: const Duration(seconds: 30),
      finalPosition: const Duration(seconds: 30),
    );

    await playbackSessions.create(playbackSession);

    final original = play(
      id: 'play_round_trip',
      playbackSessionId: playbackSession.id,
      qualifiedAt: seedTime.add(const Duration(seconds: 30)),
    );

    await qualifiedPlays.create(original);

    final byId = await qualifiedPlays.getById(original.id);
    final bySession = await qualifiedPlays.getByPlaybackSessionId(
      playbackSession.id,
    );

    expect(byId, isNotNull);
    expect(bySession, isNotNull);

    expect(byId!.id, original.id);
    expect(bySession!.id, original.id);
    expect(bySession.playbackSessionId, playbackSession.id);
    expect(bySession.songId, songId);
    expect(bySession.artistId, artistId);
    expect(bySession.albumId, albumId);
    expect(bySession.albumEditionId, editionId);
    expect(bySession.listenedDuration, const Duration(seconds: 30));
  });

  test('qualified play can attach a user without changing identity', () async {
    final playbackSession = session(
      id: 'session_attach_user',
      startedAt: seedTime,
      listenedDuration: const Duration(seconds: 30),
      finalPosition: const Duration(seconds: 30),
    );

    await playbackSessions.create(playbackSession);

    final original = play(
      id: 'play_attach_user',
      playbackSessionId: playbackSession.id,
      qualifiedAt: seedTime.add(const Duration(seconds: 30)),
    );

    await qualifiedPlays.create(original);

    final attached = original.copyWith(userId: 'user_1');

    await qualifiedPlays.save(attached);

    final restored = await qualifiedPlays.getById(original.id);

    expect(restored, isNotNull);
    expect(restored!.id, original.id);
    expect(restored.playbackSessionId, original.playbackSessionId);
    expect(restored.userId, 'user_1');
    expect(restored.songId, original.songId);
    expect(restored.artistId, original.artistId);
    expect(restored.albumId, original.albumId);
    expect(restored.albumEditionId, original.albumEditionId);
    expect(restored.qualifiedAt, original.qualifiedAt);
    expect(restored.listenedDuration, original.listenedDuration);
    expect(restored.trackDuration, original.trackDuration);
    expect(restored.createdAt, original.createdAt);
  });

  test('saving a missing qualified play fails loudly', () async {
    final playbackSession = session(
      id: 'session_missing_play_save',
      startedAt: seedTime,
    );

    await playbackSessions.create(playbackSession);

    final missing = play(
      id: 'play_missing_save',
      playbackSessionId: playbackSession.id,
      qualifiedAt: seedTime,
    );

    await expectLater(
      qualifiedPlays.save(missing),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Qualified play not found: play_missing_save',
        ),
      ),
    );
  });

  test('one playback session cannot create two qualified plays', () async {
    final playbackSession = session(
      id: 'session_single_qualification',
      startedAt: seedTime,
      listenedDuration: const Duration(seconds: 30),
      finalPosition: const Duration(seconds: 30),
    );

    await playbackSessions.create(playbackSession);

    final first = play(
      id: 'play_first',
      playbackSessionId: playbackSession.id,
      qualifiedAt: seedTime.add(const Duration(seconds: 30)),
    );

    final duplicate = play(
      id: 'play_duplicate',
      playbackSessionId: playbackSession.id,
      qualifiedAt: seedTime.add(const Duration(seconds: 31)),
    );

    await qualifiedPlays.create(first);

    await expectLater(qualifiedPlays.create(duplicate), throwsA(anything));

    final stored = await qualifiedPlays.getAll();

    expect(stored, hasLength(1));
    expect(stored.single.id, first.id);
  });

  test('qualified play range query uses half-open boundaries', () async {
    final sessions = [
      session(id: 'session_play_1', startedAt: DateTime.utc(2026, 9, 20, 12)),
      session(id: 'session_play_2', startedAt: DateTime.utc(2026, 9, 25, 12)),
      session(id: 'session_play_3', startedAt: DateTime.utc(2026, 10, 1)),
    ];

    for (final value in sessions) {
      await playbackSessions.create(value);
    }

    await qualifiedPlays.create(
      play(
        id: 'play_1',
        playbackSessionId: 'session_play_1',
        qualifiedAt: DateTime.utc(2026, 9, 20, 12, 0, 30),
      ),
    );

    await qualifiedPlays.create(
      play(
        id: 'play_2',
        playbackSessionId: 'session_play_2',
        qualifiedAt: DateTime.utc(2026, 9, 25, 12, 0, 30),
      ),
    );

    await qualifiedPlays.create(
      play(
        id: 'play_3',
        playbackSessionId: 'session_play_3',
        qualifiedAt: DateTime.utc(2026, 10, 1),
      ),
    );

    final results = await qualifiedPlays.getAll(
      qualifiedAtOrAfter: DateTime.utc(2026, 9, 1),
      qualifiedBefore: DateTime.utc(2026, 10, 1),
    );

    expect(results.map((value) => value.id), ['play_1', 'play_2']);
  });

  test('history page orders newest sessions first', () async {
    await playbackSessions.create(
      session(id: 'history_old', startedAt: DateTime.utc(2026, 9, 25, 8)),
    );

    await playbackSessions.create(
      session(id: 'history_new', startedAt: DateTime.utc(2026, 9, 25, 12)),
    );

    final results = await playbackSessions.getHistoryPage(limit: 10);

    expect(results.map((value) => value.id), ['history_new', 'history_old']);
  });

  test(
    'history page uses id descending as deterministic tie breaker',
    () async {
      final startedAt = DateTime.utc(2026, 9, 25, 12);

      await playbackSessions.create(
        session(id: 'history_a', startedAt: startedAt),
      );

      await playbackSessions.create(
        session(id: 'history_c', startedAt: startedAt),
      );

      await playbackSessions.create(
        session(id: 'history_b', startedAt: startedAt),
      );

      final results = await playbackSessions.getHistoryPage(limit: 10);

      expect(results.map((value) => value.id), [
        'history_c',
        'history_b',
        'history_a',
      ]);
    },
  );

  test('history cursor returns the next page without duplicates', () async {
    final newest = session(
      id: 'history_3',
      startedAt: DateTime.utc(2026, 9, 25, 12),
    );

    final middle = session(
      id: 'history_2',
      startedAt: DateTime.utc(2026, 9, 25, 11),
    );

    final oldest = session(
      id: 'history_1',
      startedAt: DateTime.utc(2026, 9, 25, 10),
    );

    await playbackSessions.create(oldest);
    await playbackSessions.create(middle);
    await playbackSessions.create(newest);

    final firstPage = await playbackSessions.getHistoryPage(limit: 2);

    expect(firstPage.map((value) => value.id), ['history_3', 'history_2']);

    final secondPage = await playbackSessions.getHistoryPage(
      before: ListeningHistoryCursor(
        startedAt: firstPage.last.startedAt,
        sessionId: firstPage.last.id,
      ),
      limit: 2,
    );

    expect(secondPage.map((value) => value.id), ['history_1']);

    expect({
      ...firstPage.map((value) => value.id),
      ...secondPage.map((value) => value.id),
    }, hasLength(3));
  });

  test('history cursor handles sessions sharing the same timestamp', () async {
    final startedAt = DateTime.utc(2026, 9, 25, 12);

    for (final id in ['history_d', 'history_c', 'history_b', 'history_a']) {
      await playbackSessions.create(session(id: id, startedAt: startedAt));
    }

    final firstPage = await playbackSessions.getHistoryPage(limit: 2);

    expect(firstPage.map((value) => value.id), ['history_d', 'history_c']);

    final secondPage = await playbackSessions.getHistoryPage(
      before: ListeningHistoryCursor(
        startedAt: firstPage.last.startedAt,
        sessionId: firstPage.last.id,
      ),
      limit: 2,
    );

    expect(secondPage.map((value) => value.id), ['history_b', 'history_a']);
  });

  test('history range query uses half-open boundaries', () async {
    await playbackSessions.create(
      session(
        id: 'history_before',
        startedAt: DateTime.utc(2026, 9, 20, 23, 59),
      ),
    );

    await playbackSessions.create(
      session(id: 'history_start', startedAt: DateTime.utc(2026, 9, 21)),
    );

    await playbackSessions.create(
      session(id: 'history_inside', startedAt: DateTime.utc(2026, 9, 25, 12)),
    );

    await playbackSessions.create(
      session(id: 'history_end', startedAt: DateTime.utc(2026, 9, 28)),
    );

    final results = await playbackSessions.getHistoryPage(
      startedAtOrAfter: DateTime.utc(2026, 9, 21),
      startedBefore: DateTime.utc(2026, 9, 28),
      limit: 10,
    );

    expect(results.map((value) => value.id), [
      'history_inside',
      'history_start',
    ]);
  });

  test('batch qualified play lookup returns only requested sessions', () async {
    final firstSession = session(
      id: 'batch_session_1',
      startedAt: DateTime.utc(2026, 9, 25, 10),
    );

    final secondSession = session(
      id: 'batch_session_2',
      startedAt: DateTime.utc(2026, 9, 25, 11),
    );

    final thirdSession = session(
      id: 'batch_session_3',
      startedAt: DateTime.utc(2026, 9, 25, 12),
    );

    await playbackSessions.create(firstSession);
    await playbackSessions.create(secondSession);
    await playbackSessions.create(thirdSession);

    await qualifiedPlays.create(
      play(
        id: 'batch_play_1',
        playbackSessionId: firstSession.id,
        qualifiedAt: DateTime.utc(2026, 9, 25, 10, 0, 30),
      ),
    );

    await qualifiedPlays.create(
      play(
        id: 'batch_play_2',
        playbackSessionId: secondSession.id,
        qualifiedAt: DateTime.utc(2026, 9, 25, 11, 0, 30),
      ),
    );

    await qualifiedPlays.create(
      play(
        id: 'batch_play_3',
        playbackSessionId: thirdSession.id,
        qualifiedAt: DateTime.utc(2026, 9, 25, 12, 0, 30),
      ),
    );

    final results = await qualifiedPlays.getByPlaybackSessionIds([
      firstSession.id,
      thirdSession.id,
    ]);

    expect(results.map((value) => value.playbackSessionId).toSet(), {
      firstSession.id,
      thirdSession.id,
    });
  });
}
