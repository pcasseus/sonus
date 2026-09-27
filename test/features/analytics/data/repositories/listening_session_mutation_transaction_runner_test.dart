import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_listening_segment_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_session_dao.dart';
import 'package:sonus_next/features/analytics/data/repositories/listening_session_mutation_transaction_runner.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';

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

  test('rolls back earlier analytics write when later write fails', () async {
    final database = await appDatabase.database;

    final sessions = SqlitePlaybackSessionRepository(
      PlaybackSessionDao(database),
    );

    final segments = SqlitePlaybackListeningSegmentRepository(
      PlaybackListeningSegmentDao(database),
    );

    final now = DateTime.utc(2026, 9, 27, 7);

    await sessions.create(
      PlaybackSession(
        id: 'session-1',
        songId: 'song-1',
        artistId: 'artist-1',
        albumId: 'album-1',
        albumEditionId: 'edition-1',
        songTitle: 'Song',
        artistName: 'Artist',
        albumTitle: 'Album',
        albumEditionTitle: 'Standard',
        startedAt: now,
        listenedDuration: Duration.zero,
        trackDuration: const Duration(minutes: 3),
        finalPosition: Duration.zero,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await segments.create(
      PlaybackListeningSegment(
        id: 'segment-1',
        playbackSessionId: 'session-1',
        startedAt: now,
        listenedDuration: Duration.zero,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final runner = ListeningSessionMutationTransactionRunner(
      appDatabase: appDatabase,
    );

    await expectLater(
      runner.run((context) async {
        await context.listeningSegments.save(
          PlaybackListeningSegment(
            id: 'segment-1',
            playbackSessionId: 'session-1',
            startedAt: now,
            listenedDuration: const Duration(seconds: 10),
            createdAt: now,
            updatedAt: now.add(const Duration(seconds: 10)),
          ),
        );

        await context.playbackSessions.save(
          PlaybackSession(
            id: 'missing-session',
            songId: 'song-1',
            artistId: 'artist-1',
            albumId: 'album-1',
            albumEditionId: 'edition-1',
            songTitle: 'Song',
            artistName: 'Artist',
            albumTitle: 'Album',
            albumEditionTitle: 'Standard',
            startedAt: now,
            listenedDuration: const Duration(seconds: 10),
            trackDuration: const Duration(minutes: 3),
            finalPosition: const Duration(seconds: 10),
            createdAt: now,
            updatedAt: now.add(const Duration(seconds: 10)),
          ),
        );
      }),
      throwsA(isA<StateError>()),
    );

    final restoredSegment = await segments.getById('segment-1');

    expect(restoredSegment, isNotNull);
    expect(restoredSegment!.listenedDuration, Duration.zero);

    final sessionRows = await database.query(DatabaseTables.playbackSessions);

    expect(sessionRows, hasLength(1));
    expect(sessionRows.single['id'], 'session-1');
  });
}
