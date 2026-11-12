// App Update 1.2, BUG-11 hardening: listening and chart accounting over the
// real stack (disposable database, repositories, tracker, analytics
// controller, playback engine and a simulated just_audio player whose
// play() stays pending while playback goes on). Fictional songs only.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/analytics/application/controllers/playback_analytics_controller.dart';
import 'package:sonus_next/features/analytics/application/services/listening_session_tracker.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_listening_segment_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_session_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/qualified_play_dao.dart';
import 'package:sonus_next/features/analytics/data/repositories/listening_session_mutation_transaction_runner.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_session_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_qualified_play_repository.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/data/engines/just_audio_playback_engine.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';

import '../player/data/engines/simulated_just_audio_player.dart';

LibraryTrack _song(String id) => LibraryTrack(
  songId: id,
  title: 'Song $id',
  artistId: 'artist',
  artistName: 'Artist',
  albumId: 'album',
  albumTitle: 'Album',
  albumEditionId: 'edition',
  albumEditionTitle: 'Album',
  albumEditionType: AlbumEditionType.standard,
  trackNumber: 1,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: const [],
  dateAdded: DateTime.utc(2026, 9, 11),
  isAvailable: true,
  filePath: '/music/$id.mp3',
);

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late AppDatabase database;
  late Database db;
  late SimulatedJustAudioPlayer player;
  late JustAudioPlaybackEngine engine;
  late PlaybackCoordinator coordinator;
  late PlaybackAnalyticsController controller;
  late DateTime now;
  final errors = <Object>[];

  setUp(() async {
    errors.clear();
    dir = await Directory.systemTemp.createTemp('sonus_listening_');
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(dir.path, 'listening.db'),
    );
    db = await database.database;
    now = DateTime.utc(2026, 11, 11, 12);

    player = SimulatedJustAudioPlayer();
    engine = JustAudioPlaybackEngine(
      audioPlayer: player,
      configureAudioSession: () async {},
    );
    coordinator = PlaybackCoordinator(engine: engine);

    var sessions = 0;
    var plays = 0;
    final tracker = ListeningSessionTracker(
      playbackSessions: SqlitePlaybackSessionRepository(PlaybackSessionDao(db)),
      listeningSegments: SqlitePlaybackListeningSegmentRepository(
        PlaybackListeningSegmentDao(db),
      ),
      qualifiedPlays: SqliteQualifiedPlayRepository(QualifiedPlayDao(db)),
      mutationRunner: ListeningSessionMutationTransactionRunner(
        appDatabase: database,
      ),
      now: () => now,
      playbackSessionIdGenerator: () => 'session_${++sessions}',
      qualifiedPlayIdGenerator: () => 'play_${++plays}',
    );
    controller = PlaybackAnalyticsController(
      playbackCoordinator: coordinator,
      tracker: tracker,
      now: () => now,
      onError: (error, _) => errors.add(error),
    );
  });

  tearDown(() async {
    await controller.dispose();
    await engine.dispose();
    await database.close();
    await dir.delete(recursive: true);
  });

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await controller.settled;
  }

  /// [seconds] of listening go by, with the player's position following.
  Future<void> listen(int seconds) async {
    final start = engine.currentState.position;
    for (var s = 1; s <= seconds; s++) {
      now = now.add(const Duration(seconds: 1));
      player.advanceTo(start + Duration(seconds: s));
      await settle();
    }
  }

  Future<List<Map<String, Object?>>> sessionsOf(String songId) => db.query(
    DatabaseTables.playbackSessions,
    where: 'song_id = ?',
    whereArgs: [songId],
    orderBy: 'started_at',
  );

  Future<int> playsOf(String songId) async => (await db.query(
    DatabaseTables.qualifiedPlays,
    where: 'song_id = ?',
    whereArgs: [songId],
  )).length;

  group('A1: the playing song is deleted', () {
    test(
      'its open session is let go, and the next song is still recorded',
      () async {
        await coordinator.playTracks([_song('a'), _song('b')]);
        await settle();
        await listen(5);
        final session = (await sessionsOf('a')).single['id']! as String;

        // Permanent deletion of "a" erases its listening, including the
        // session that is open (PermanentDeletionService, step 4).
        await db.delete(
          DatabaseTables.playbackListeningSegments,
          where: 'playback_session_id = ?',
          whereArgs: [session],
        );
        await db.delete(
          DatabaseTables.playbackSessions,
          where: 'id = ?',
          whereArgs: [session],
        );

        await listen(6); // a checkpoint finds the session gone
        await coordinator.skipNext();
        await settle();
        await listen(40);

        expect(await sessionsOf('a'), isEmpty, reason: 'stays deleted');
        expect(await sessionsOf('b'), hasLength(1));
        expect(await playsOf('b'), 1);
        expect(errors, isNotEmpty, reason: 'the failure is reported once');
      },
    );
  });

  group('A2: the same song queued twice is two listens', () {
    test(
      '20 s, Next to its second copy, 15 s: two sessions, no stream',
      () async {
        await coordinator.playTracks([_song('a'), _song('a')]);
        await settle();
        await listen(20);
        await coordinator.skipNext();
        await settle();
        await listen(15);
        await coordinator.pause();
        await settle();

        final sessions = await sessionsOf('a');
        expect(sessions, hasLength(2));
        expect(sessions.first['end_reason'], 'skipped');
        expect(await playsOf('a'), 0, reason: 'neither listen reached 30 s');
      },
    );

    test('40 s, then on into its second copy, 40 s: two streams', () async {
      await coordinator.playTracks([_song('a'), _song('a')]);
      await settle();
      await listen(40);
      // The first copy ends and the player moves on by itself.
      await player.seek(Duration.zero, index: 1);
      await settle();
      await listen(40);
      await coordinator.pause();
      await settle();

      final sessions = await sessionsOf('a');
      expect(sessions, hasLength(2));
      expect(sessions.first['end_reason'], 'completed');
      expect(await playsOf('a'), 2);
    });

    test(
      'a queue edit that only shifts the playing entry stays one listen',
      () async {
        await coordinator.playTracks([_song('x'), _song('a'), _song('y')]);
        await coordinator.skipNext();
        await settle();
        await listen(10);
        await coordinator.removeFromQueue(0); // "a" moves from 1 to 0
        await settle();
        await listen(25);
        await coordinator.pause();
        await settle();

        expect(await sessionsOf('a'), hasLength(1));
        expect(await playsOf('a'), 1);
      },
    );
  });

  group('A3: a duplicate merge while the duplicate is playing', () {
    test('the session and its stream follow the kept recording', () async {
      await coordinator.playTracks([_song('dup')]);
      await settle();
      await listen(10);

      // DuplicateAlbumReconciliationService: listening history follows
      // the kept recording (the same update it runs).
      for (final table in [
        DatabaseTables.playbackSessions,
        DatabaseTables.qualifiedPlays,
      ]) {
        await db.update(
          table,
          {
            'song_id': 'kept',
            'album_id': 'kept_album',
            'album_edition_id': 'kept_edition',
          },
          where: 'song_id = ?',
          whereArgs: ['dup'],
        );
      }

      await listen(30); // checkpoints, then the stream qualifies
      await coordinator.pause();
      await settle();

      expect(await sessionsOf('dup'), isEmpty, reason: 'not written back');
      final kept = (await sessionsOf('kept')).single;
      expect(kept['album_id'], 'kept_album');
      expect(kept['album_edition_id'], 'kept_edition');
      expect(kept['listened_duration_ms'], greaterThanOrEqualTo(39000));
      expect(await playsOf('dup'), 0);
      expect(await playsOf('kept'), 1);
    });
  });

  group('A4: removing the playing song', () {
    test('the next song starts its own listen from 0:00, not as a finished '
        'restart', () async {
      await coordinator.playTracks([_song('a'), _song('b'), _song('c')]);
      await settle();
      await listen(178); // "a" is near its end (3:00)
      await coordinator.removeFromQueue(0);
      await settle();
      expect(engine.currentState.queue.currentTrack?.songId, 'b');
      expect(engine.currentState.position, Duration.zero);
      await listen(40);
      await coordinator.pause();
      await settle();

      final sessions = await sessionsOf('b');
      expect(sessions, hasLength(1), reason: 'no phantom finished session');
      expect(sessions.single['end_reason'], isNot('completed'));
      expect(await playsOf('b'), 1);
    });
  });

  group('one stream per listen', () {
    test('Shuffle and Repeat changes mid-song keep one session', () async {
      await coordinator.playTracks([_song('a'), _song('b'), _song('c')]);
      await settle();
      await listen(10);
      await coordinator.setShuffleEnabled(true);
      await coordinator.setRepeatMode(PlaybackRepeatMode.all);
      await settle();
      await listen(10);
      await coordinator.setShuffleEnabled(false);
      await settle();
      await listen(15);
      await coordinator.pause();
      await settle();

      expect(await sessionsOf('a'), hasLength(1));
      expect(await playsOf('a'), 1);
    });

    test('seeking back and forth within a song is still one stream', () async {
      await coordinator.playTracks([_song('a')]);
      await settle();
      await listen(20);
      await coordinator.seek(const Duration(seconds: 5));
      await settle();
      await listen(20);
      await coordinator.seek(const Duration(minutes: 2));
      await settle();
      await listen(5);
      await coordinator.pause();
      await settle();

      expect(await sessionsOf('a'), hasLength(1));
      expect(await playsOf('a'), 1);
    });

    test('a start that fails records no stream', () async {
      await coordinator.playTracks([_song('a')]);
      player.failSource();
      await settle();
      await listen(1);

      expect(await playsOf('a'), 0);
    });
  });
}
