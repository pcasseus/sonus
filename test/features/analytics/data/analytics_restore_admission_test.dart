import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_account_attachment_service.dart';
import 'package:sonus_next/features/analytics/application/services/listening_session_recovery_service.dart';
import 'package:sonus_next/features/analytics/application/services/listening_session_start.dart';
import 'package:sonus_next/features/analytics/application/services/listening_session_tracker.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_listening_segment_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/playback_session_dao.dart';
import 'package:sonus_next/features/analytics/data/daos/qualified_play_dao.dart';
import 'package:sonus_next/features/analytics/data/repositories/listening_session_mutation_transaction_runner.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_playback_session_repository.dart';
import 'package:sonus_next/features/analytics/data/repositories/sqlite_qualified_play_repository.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/presentation/scopes/analytics_scope.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

import '../../../support/library_seed.dart';

void main() {
  sqfliteFfiInit();

  late Directory directory;
  late _ObservedAppDatabase appDatabase;
  late Database db;
  late SqlitePlaybackSessionRepository sessions;
  late SqlitePlaybackListeningSegmentRepository segments;
  late SqliteQualifiedPlayRepository plays;
  late DateTime now;

  final startedAt = DateTime.utc(2026, 10, 1, 12);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sonus_analytics_');
    appDatabase = _ObservedAppDatabase(
      '${directory.path}${Platform.pathSeparator}analytics.db',
    );
    db = await appDatabase.database;
    now = startedAt;

    // song-a with one ended session, segment and qualified play.
    await seedConnectedLibrary(db, key: 'a');

    // The composition AnalyticsScope uses for its provided repositories.
    sessions = SqlitePlaybackSessionRepository(
      PlaybackSessionDao(db),
      appDatabase: appDatabase,
    );
    segments = SqlitePlaybackListeningSegmentRepository(
      PlaybackListeningSegmentDao(db),
      appDatabase: appDatabase,
    );
    plays = SqliteQualifiedPlayRepository(
      QualifiedPlayDao(db),
      appDatabase: appDatabase,
    );
  });

  tearDown(() async {
    await appDatabase.close();
    await directory.delete(recursive: true);
  });

  Future<T> whileRestoring<T>(Future<T> Function() body) async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final restore = appDatabase.mutationCoordinator.runExclusiveRestore(
      () async {
        entered.complete();
        await release.future;
      },
    );
    await entered.future;

    try {
      return await body();
    } finally {
      release.complete();
      await restore;
    }
  }

  Future<void> expectRejected(Future<Object?> Function() write) async {
    final before = await snapshotDatabase(db);

    await whileRestoring(() async {
      await expectLater(write(), throwsA(isA<LibraryMutationUnavailable>()));
    });

    expect(await snapshotDatabase(db), before);
    expect(appDatabase.mutationCoordinator.activeMutations, 0);
  }

  PlaybackSession session(String id, {DateTime? endedAt, String? userId}) {
    return PlaybackSession(
      id: id,
      userId: userId,
      songId: 'song-a',
      artistId: 'artist-a',
      albumId: 'album-a',
      albumEditionId: 'edition-a',
      songTitle: 'Song',
      artistName: 'Artist a',
      albumTitle: 'Album a',
      albumEditionTitle: 'Standard',
      startedAt: startedAt,
      endedAt: endedAt,
      listenedDuration: Duration.zero,
      trackDuration: const Duration(minutes: 3),
      finalPosition: Duration.zero,
      createdAt: startedAt,
      updatedAt: startedAt,
    );
  }

  PlaybackListeningSegment segment(String id, String sessionId) {
    return PlaybackListeningSegment(
      id: id,
      playbackSessionId: sessionId,
      startedAt: startedAt,
      listenedDuration: Duration.zero,
      createdAt: startedAt,
      updatedAt: startedAt,
    );
  }

  QualifiedPlay play(String id, String sessionId) {
    return QualifiedPlay(
      id: id,
      playbackSessionId: sessionId,
      songId: 'song-a',
      artistId: 'artist-a',
      albumId: 'album-a',
      albumEditionId: 'edition-a',
      qualifiedAt: startedAt,
      listenedDuration: const Duration(seconds: 30),
      trackDuration: const Duration(minutes: 3),
      createdAt: startedAt,
    );
  }

  group('repositories', () {
    test('every create and save is refused during a restore', () async {
      await sessions.create(session('session-b'));
      await segments.create(segment('segment-b', 'session-b'));

      await expectRejected(() => sessions.create(session('session-c')));
      await expectRejected(
        () => sessions.save(session('session-b', endedAt: startedAt)),
      );
      await expectRejected(
        () => segments.create(segment('segment-c', 'session-b')),
      );
      await expectRejected(
        () => segments.save(
          segment('segment-b', 'session-b').copyWith(endedAt: startedAt),
        ),
      );
      await expectRejected(() => plays.create(play('play-b', 'session-b')));

      final existing = (await plays.getByPlaybackSessionId('session-a'))!;
      await expectRejected(
        () => plays.save(existing.copyWith(userId: 'user-1')),
      );
    });

    test('writes work when no restore is active', () async {
      await sessions.create(session('session-b'));
      await sessions.save(session('session-b', endedAt: startedAt));
      await segments.create(segment('segment-b', 'session-b'));
      await plays.create(play('play-b', 'session-b'));

      expect((await sessions.getById('session-b'))!.endedAt, startedAt);
      expect(await segments.getForSession('session-b'), hasLength(1));
      expect(await plays.getByPlaybackSessionId('session-b'), isNotNull);
      expect(appDatabase.mutationCoordinator.activeMutations, 0);
    });

    test('one session can never hold two qualified plays', () async {
      await expectLater(
        plays.create(play('play-duplicate', 'session-a')),
        throwsA(isA<DatabaseException>()),
      );

      expect(
        await db.query(
          DatabaseTables.qualifiedPlays,
          where: 'playback_session_id = ?',
          whereArgs: ['session-a'],
        ),
        hasLength(1),
      );
    });
  });

  group('tracker composed as in AnalyticsScope', () {
    late ListeningSessionTracker tracker;

    const start = ListeningSessionStart(
      songId: 'song-a',
      artistId: 'artist-a',
      albumId: 'album-a',
      albumEditionId: 'edition-a',
      songTitle: 'Song',
      artistName: 'Artist a',
      albumTitle: 'Album a',
      albumEditionTitle: 'Standard',
      trackDuration: Duration(minutes: 3),
    );

    setUp(() {
      var sessionNumber = 0;
      var playNumber = 0;

      tracker = ListeningSessionTracker(
        playbackSessions: sessions,
        listeningSegments: segments,
        qualifiedPlays: plays,
        mutationRunner: ListeningSessionMutationTransactionRunner(
          appDatabase: appDatabase,
        ),
        now: () => now,
        playbackSessionIdGenerator: () => 'session-t${++sessionNumber}',
        listeningSegmentIdGenerator: () => 'segment-t${++sessionNumber}',
        qualifiedPlayIdGenerator: () => 'play-t${++playNumber}',
      );
    });

    Future<void> expectAbandoned(Future<Object?> Function() operation) async {
      await expectRejected(operation);

      expect(tracker.hasActiveSession, isFalse);
      expect(tracker.currentListeningSegment, isNull);
      expect(tracker.isPlaying, isFalse);
      expect(tracker.hasQualified, isFalse);
    }

    test(
      'records normal listening with short, non-nested transactions',
      () async {
        final session = await tracker
            .start(start, playing: true)
            .timeout(const Duration(seconds: 10));

        now = now.add(const Duration(seconds: 31));
        await tracker.checkpoint(position: const Duration(seconds: 31));
        await tracker.markPaused(position: const Duration(seconds: 31));
        now = now.add(const Duration(seconds: 5));
        await tracker.markPlaying(position: const Duration(seconds: 31));
        now = now.add(const Duration(seconds: 4));
        await tracker.checkpoint(position: const Duration(seconds: 35));
        final ended = await tracker.end(
          reason: PlaybackSessionEndReason.completed,
          position: const Duration(seconds: 35),
        );

        expect(ended.listenedDuration, const Duration(seconds: 35));
        expect(ended.endReason, PlaybackSessionEndReason.completed);
        expect((await sessions.getById(session.id))!.isEnded, isTrue);

        final recorded = await segments.getForSession(session.id);
        expect(recorded, hasLength(2));
        expect(recorded.every((segment) => segment.isEnded), isTrue);

        final qualified = await db.query(
          DatabaseTables.qualifiedPlays,
          where: 'playback_session_id = ?',
          whereArgs: [session.id],
        );
        expect(qualified, hasLength(1));

        expect(appDatabase.maxDepth, 1);
        expect(appDatabase.mutationCoordinator.activeMutations, 0);
      },
    );

    test('session start is refused (W3, W5)', () async {
      await expectAbandoned(() => tracker.start(start, playing: true));
    });

    test('mark playing is refused (W4)', () async {
      await tracker.start(start);

      await expectAbandoned(() => tracker.markPlaying());
    });

    test('pause is refused with and without a segment (W6, W7)', () async {
      await tracker.start(start, playing: true);
      now = now.add(const Duration(seconds: 3));
      await expectAbandoned(() => tracker.markPaused());

      await tracker.start(start);
      await expectAbandoned(() => tracker.markPaused());
    });

    test('checkpoint is refused with and without a segment (W8)', () async {
      await tracker.start(start, playing: true);
      now = now.add(const Duration(seconds: 3));
      await expectAbandoned(
        () => tracker.checkpoint(position: const Duration(seconds: 3)),
      );

      await tracker.start(start);
      await expectAbandoned(() => tracker.checkpoint(position: Duration.zero));
    });

    test('end is refused with and without a segment (W9)', () async {
      await tracker.start(start, playing: true);
      now = now.add(const Duration(seconds: 40));
      await expectAbandoned(
        () => tracker.end(
          reason: PlaybackSessionEndReason.stopped,
          position: const Duration(seconds: 40),
        ),
      );

      await tracker.start(start);
      await expectAbandoned(
        () => tracker.end(
          reason: PlaybackSessionEndReason.stopped,
          position: Duration.zero,
        ),
      );
    });

    test('active session attachment is refused (W1, W2)', () async {
      await tracker.start(start, playing: true);
      now = now.add(const Duration(seconds: 31));
      await tracker.checkpoint(position: const Duration(seconds: 31));

      await expectAbandoned(() => tracker.attachCurrentSessionToUser('user-1'));
    });

    test('stale state is never written after the restore ends', () async {
      final first = await tracker.start(start, playing: true);
      now = now.add(const Duration(seconds: 10));
      await expectAbandoned(
        () => tracker.checkpoint(position: const Duration(seconds: 10)),
      );
      final afterRejection = await snapshotDatabase(db);

      final second = await tracker.start(start, playing: true);

      expect(second.id, isNot(first.id));
      final current = await snapshotDatabase(db);
      final firstRow = (await sessions.getById(first.id))!;
      expect(firstRow.isEnded, isFalse);
      expect(firstRow.listenedDuration, Duration.zero);
      for (final table in afterRejection.keys) {
        if (table == DatabaseTables.playbackSessions ||
            table == DatabaseTables.playbackListeningSegments) {
          continue;
        }
        expect(current[table], afterRejection[table], reason: table);
      }
    });
  });

  group('startup recovery and attachment', () {
    Future<void> seedOpenSession() async {
      await sessions.create(session('session-open'));
      await segments.create(segment('segment-open', 'session-open'));
    }

    test('startup recovery is refused without partial writes (W11)', () async {
      await seedOpenSession();

      await expectRejected(
        () => ListeningSessionRecoveryService(
          playbackSessions: sessions,
          listeningSegments: segments,
        ).recoverInterruptedSessions(),
      );
    });

    test('the runtime still starts, logging the refused recovery', () async {
      await seedOpenSession();
      final before = await snapshotDatabase(db);
      final messages = <String>[];
      final engine = _IdleEngine();
      addTearDown(engine.dispose);

      final runtime = await whileRestoring(
        () => AnalyticsRuntime.create(
          appDatabase: appDatabase,
          playbackCoordinator: PlaybackCoordinator(engine: engine),
          log: (message, {required level, stackTrace}) => messages.add(message),
        ),
      );
      addTearDown(runtime.dispose);

      expect(messages, [
        'Startup listening recovery stopped: library restoration is active.',
      ]);
      expect(await snapshotDatabase(db), before);

      // Recovered at the next start, once the restore has ended.
      final next = await AnalyticsRuntime.create(
        appDatabase: appDatabase,
        playbackCoordinator: PlaybackCoordinator(engine: engine),
        log: (message, {required level, stackTrace}) => messages.add(message),
      );
      addTearDown(next.dispose);

      final recovered = (await sessions.getById('session-open'))!;
      expect(recovered.endReason, PlaybackSessionEndReason.interrupted);
      expect(messages, hasLength(1));
    });

    test('historical account attachment is refused (W12)', () async {
      final attachment = AnalyticsAccountAttachmentService(
        playbackSessions: sessions,
        qualifiedPlays: plays,
      );

      await expectRejected(() => attachment.attachUnownedToUser('user-1'));

      final result = await attachment.attachUnownedToUser('user-1');
      expect(result.sessionsAttached, 1);
      expect((await sessions.getById('session-a'))!.userId, 'user-1');
    });

    test(
      'disposal writes are refused, and none happen once suspended (W13)',
      () async {
        final engine = _IdleEngine();
        addTearDown(engine.dispose);

        Future<AnalyticsRuntime> playingRuntime() async {
          final runtime = await AnalyticsRuntime.create(
            appDatabase: appDatabase,
            playbackCoordinator: PlaybackCoordinator(engine: engine),
            now: () => now,
            log: (message, {required level, stackTrace}) {},
          );
          engine.emit(_playing);
          await runtime.controller.settled;
          return runtime;
        }

        final unsuspended = await playingRuntime();
        await expectRejected(unsuspended.dispose);

        // Playback never stopped, so the barrier cannot end the session; it
        // abandons it, and the suspended disposal must not write it either.
        engine.emit(const PlaybackState());
        final suspended = await playingRuntime();
        await suspended.controller.suspendForRestore();
        final before = await snapshotDatabase(db);

        await whileRestoring(suspended.dispose);

        expect(await snapshotDatabase(db), before);
        expect(appDatabase.mutationCoordinator.activeMutations, 0);
      },
    );
  });
}

const _track = PlaybackTrack(
  songId: 'song-a',
  title: 'Song',
  artistId: 'artist-a',
  artistName: 'Artist a',
  albumId: 'album-a',
  albumTitle: 'Album a',
  albumEditionId: 'edition-a',
  albumEditionTitle: 'Standard',
  filePath: '/device/music/a.mp3',
  duration: Duration(minutes: 3),
);

final _playing = PlaybackState(
  queue: PlaybackQueue(tracks: const [_track], currentIndex: 0),
  status: PlaybackStatus.playing,
  duration: _track.duration,
);

/// Counts the nesting depth of admitted transactions.
class _ObservedAppDatabase extends AppDatabase {
  _ObservedAppDatabase(String path)
    : super(databaseFactory: databaseFactoryFfi, databasePath: path);

  int maxDepth = 0;
  int _depth = 0;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction transaction) action,
  ) async {
    maxDepth = max(maxDepth, ++_depth);

    try {
      return await super.transaction(action);
    } finally {
      _depth--;
    }
  }
}

class _IdleEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast(sync: true);

  PlaybackState _state = const PlaybackState();

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get states => _states.stream;

  void emit(PlaybackState state) {
    _state = state;
    _states.add(state);
  }

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {}

  @override
  Future<void> appendTrack(PlaybackTrack track) async {}

  @override
  Future<void> removeTrackAt(int index) async {}

  @override
  Future<void> moveTrack({
    required int oldIndex,
    required int newIndex,
  }) async {}

  @override
  Future<void> setShuffleEnabled(bool enabled) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    if (!_states.isClosed) await _states.close();
  }
}
