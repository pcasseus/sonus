import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../support/direct_listening_session_mutation_runner.dart';

import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';

import 'package:sonus_next/features/analytics/application/controllers/playback_analytics_controller.dart';
import 'package:sonus_next/features/analytics/application/services/listening_session_tracker.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_transition_cause.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

void main() {
  late DateTime now;
  late _FakePlaybackEngine engine;
  late _MemoryPlaybackSessionRepository playbackSessions;
  late _MemoryQualifiedPlayRepository qualifiedPlays;
  late _MemoryPlaybackListeningSegmentRepository listeningSegments;
  late ListeningSessionTracker tracker;
  late PlaybackAnalyticsController controller;
  late PlaybackCoordinator playbackCoordinator;
  String? currentUserId;

  setUp(() {
    now = DateTime.utc(2026, 9, 25, 12);
    currentUserId = null;

    engine = _FakePlaybackEngine();
    playbackSessions = _MemoryPlaybackSessionRepository();
    qualifiedPlays = _MemoryQualifiedPlayRepository();
    listeningSegments = _MemoryPlaybackListeningSegmentRepository();

    var sessionNumber = 0;
    var playNumber = 0;

    tracker = ListeningSessionTracker(
      playbackSessions: playbackSessions,
      qualifiedPlays: qualifiedPlays,
      listeningSegments: listeningSegments,
      mutationRunner: DirectListeningSessionMutationRunner(
        playbackSessions: playbackSessions,
        listeningSegments: listeningSegments,
        qualifiedPlays: qualifiedPlays,
      ),
      now: () => now,
      playbackSessionIdGenerator: () => 'session_${++sessionNumber}',
      qualifiedPlayIdGenerator: () => 'play_${++playNumber}',
    );

    playbackCoordinator = PlaybackCoordinator(engine: engine);

    controller = PlaybackAnalyticsController(
      playbackCoordinator: playbackCoordinator,
      tracker: tracker,
      now: () => now,
      userIdProvider: () => currentUserId,
      checkpointInterval: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    await controller.dispose();
    await engine.dispose();
  });

  test(
    'blacklisted song is rejected before analytics can create listening history',
    () async {
      final blacklistedTrack = LibraryTrack(
        songId: 'song_blacklisted',
        title: 'Blacklisted Track',
        artistId: 'artist_1',
        artistName: 'Artist',
        albumId: 'album_1',
        albumTitle: 'Album',
        albumEditionId: 'edition_1',
        albumEditionTitle: 'Standard',
        albumEditionType: AlbumEditionType.standard,
        trackNumber: 1,
        durationSeconds: 180,
        isSingle: false,
        featuredArtists: const [],
        dateAdded: now,
        isAvailable: true,
        isSongBlocked: true,
        filePath: 'C:/Music/blacklisted.mp3',
      );

      await expectLater(
        playbackCoordinator.playTrack(blacklistedTrack),
        throwsStateError,
      );

      await controller.settled;

      expect(playbackSessions.values, isEmpty);
      expect(qualifiedPlays.values, isEmpty);
    },
  );
  test('does not create a session until playback actually starts', () async {
    engine.emit(state(status: PlaybackStatus.ready));
    await controller.settled;

    expect(playbackSessions.values, isEmpty);

    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    expect(playbackSessions.values, hasLength(1));

    final createdSession = playbackSessions.values.single;

    expect(createdSession.songTitle, track1.title);
    expect(createdSession.artistName, track1.artistName);
    expect(createdSession.albumTitle, track1.albumTitle);
    expect(createdSession.albumEditionTitle, track1.albumEditionTitle);
  });

  test('falls back to album title when edition title is unavailable', () async {
    const trackWithoutEditionTitle = PlaybackTrack(
      songId: 'song_no_edition_title',
      title: 'Snapshot Song',
      artistId: 'artist_snapshot',
      artistName: 'Snapshot Artist',
      albumId: 'album_snapshot',
      albumTitle: 'Snapshot Album',
      albumEditionId: 'edition_snapshot',
      filePath: 'C:/Music/snapshot.mp3',
      duration: Duration(minutes: 3),
    );

    engine.emit(
      state(status: PlaybackStatus.playing, track: trackWithoutEditionTitle),
    );

    await controller.settled;

    final session = playbackSessions.values.single;

    expect(session.songTitle, 'Snapshot Song');
    expect(session.artistName, 'Snapshot Artist');
    expect(session.albumTitle, 'Snapshot Album');
    expect(session.albumEditionTitle, 'Snapshot Album');
  });
  test('new session uses the current user id at start time', () async {
    currentUserId = ' user-1 ';

    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    expect(playbackSessions.values, hasLength(1));
    expect(playbackSessions.values.single.userId, 'user-1');
  });

  test(
    'checkpoints playing time without writing every position event',
    () async {
      engine.emit(state(status: PlaybackStatus.playing));
      await controller.settled;

      now = now.add(const Duration(seconds: 2));

      engine.emit(
        state(
          status: PlaybackStatus.playing,
          position: const Duration(seconds: 2),
        ),
      );

      await controller.settled;

      expect(tracker.currentSession!.listenedDuration, Duration.zero);

      now = now.add(const Duration(seconds: 3));

      engine.emit(
        state(
          status: PlaybackStatus.playing,
          position: const Duration(seconds: 5),
        ),
      );

      await controller.settled;

      expect(
        tracker.currentSession!.listenedDuration,
        const Duration(seconds: 5),
      );
    },
  );

  test('buffering does not count as audible listening time', () async {
    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    now = now.add(const Duration(seconds: 10));

    engine.emit(
      state(
        status: PlaybackStatus.loading,
        position: const Duration(seconds: 10),
      ),
    );

    await controller.settled;

    now = now.add(const Duration(minutes: 2));

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        position: const Duration(seconds: 10),
      ),
    );

    await controller.settled;

    now = now.add(const Duration(seconds: 5));

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        position: const Duration(seconds: 15),
      ),
    );

    await controller.settled;

    expect(
      tracker.currentSession!.listenedDuration,
      const Duration(seconds: 15),
    );
  });

  test('skipping to another track closes the previous session', () async {
    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    now = now.add(const Duration(seconds: 12));

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        position: const Duration(seconds: 12),
      ),
    );

    await controller.settled;

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        track: track2,
        position: Duration.zero,
      ),
    );

    await controller.settled;

    final first = playbackSessions.values.firstWhere(
      (value) => value.songId == track1.songId,
    );

    expect(first.isEnded, isTrue);
    expect(first.endReason, PlaybackSessionEndReason.skipped);

    expect(tracker.currentSession!.songId, track2.songId);
  });

  test('natural queue transition records completion', () async {
    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    now = now.add(const Duration(minutes: 3));

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        position: const Duration(minutes: 3),
      ),
    );

    await controller.settled;

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        track: track2,
        position: Duration.zero,
      ),
    );

    await controller.settled;

    final first = playbackSessions.values.firstWhere(
      (value) => value.songId == track1.songId,
    );

    expect(first.endReason, PlaybackSessionEndReason.completed);
  });

  test('automatic transition closes previous session as completed', () async {
    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    now = now.add(const Duration(seconds: 20));

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        position: const Duration(seconds: 20),
      ),
    );

    await controller.settled;

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        track: track2,
        transitionCause: PlaybackTransitionCause.automatic,
      ),
    );

    await controller.settled;

    final first = playbackSessions.values.firstWhere(
      (value) => value.songId == track1.songId,
    );

    expect(first.endReason, PlaybackSessionEndReason.completed);
    expect(tracker.currentSession!.songId, track2.songId);
  });

  test('explicit next near track end is still recorded as skipped', () async {
    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    now = now.add(const Duration(minutes: 2, seconds: 59));

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        position: const Duration(minutes: 2, seconds: 59),
      ),
    );

    await controller.settled;

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        track: track2,
        transitionCause: PlaybackTransitionCause.skipNext,
      ),
    );

    await controller.settled;

    final first = playbackSessions.values.firstWhere(
      (value) => value.songId == track1.songId,
    );

    expect(first.endReason, PlaybackSessionEndReason.skipped);
  });

  test('explicit previous transition is recorded as skipped', () async {
    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    now = now.add(const Duration(seconds: 15));

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        position: const Duration(seconds: 15),
      ),
    );

    await controller.settled;

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        track: track2,
        transitionCause: PlaybackTransitionCause.skipPrevious,
      ),
    );

    await controller.settled;

    final first = playbackSessions.values.firstWhere(
      (value) => value.songId == track1.songId,
    );

    expect(first.endReason, PlaybackSessionEndReason.skipped);
  });

  test('explicit indexed transition is recorded as skipped', () async {
    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    now = now.add(const Duration(seconds: 15));

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        position: const Duration(seconds: 15),
      ),
    );

    await controller.settled;

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        track: track2,
        transitionCause: PlaybackTransitionCause.skipToIndex,
      ),
    );

    await controller.settled;

    final first = playbackSessions.values.firstWhere(
      (value) => value.songId == track1.songId,
    );

    expect(first.endReason, PlaybackSessionEndReason.skipped);
  });
  test('repeat restart creates a new session for the same song', () async {
    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    now = now.add(const Duration(minutes: 3));

    engine.emit(
      state(
        status: PlaybackStatus.playing,
        position: const Duration(minutes: 3),
      ),
    );

    await controller.settled;

    engine.emit(state(status: PlaybackStatus.playing, position: Duration.zero));

    await controller.settled;

    expect(playbackSessions.values, hasLength(2));
    expect(playbackSessions.values.map((value) => value.songId), [
      track1.songId,
      track1.songId,
    ]);
  });

  test('completed playback closes the session as completed', () async {
    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    now = now.add(const Duration(seconds: 40));

    engine.emit(
      state(
        status: PlaybackStatus.completed,
        position: const Duration(minutes: 3),
      ),
    );

    await controller.settled;

    expect(tracker.hasActiveSession, isFalse);

    expect(
      playbackSessions.values.single.endReason,
      PlaybackSessionEndReason.completed,
    );

    expect(qualifiedPlays.values, hasLength(1));
  });

  test('failed playback closes the session as failed', () async {
    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    now = now.add(const Duration(seconds: 7));

    engine.emit(
      state(
        status: PlaybackStatus.failed,
        position: const Duration(seconds: 7),
      ),
    );

    await controller.settled;

    expect(
      playbackSessions.values.single.endReason,
      PlaybackSessionEndReason.failed,
    );
  });

  test('stop closes the session as stopped', () async {
    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    now = now.add(const Duration(seconds: 6));

    engine.emit(
      state(status: PlaybackStatus.idle, position: const Duration(seconds: 6)),
    );

    await controller.settled;

    expect(
      playbackSessions.values.single.endReason,
      PlaybackSessionEndReason.stopped,
    );
  });

  test(
    'active-session account attachment is serialized before later playback state writes',
    () async {
      engine.emit(state(status: PlaybackStatus.playing));
      await controller.settled;

      expect(playbackSessions.values.single.userId, isNull);

      final attachment = controller.attachActiveSessionToUser(' user-1 ');

      now = now.add(const Duration(seconds: 5));

      engine.emit(
        state(
          status: PlaybackStatus.paused,
          position: const Duration(seconds: 5),
        ),
      );

      await attachment;
      await controller.settled;

      expect(tracker.currentSession!.userId, 'user-1');
      expect(playbackSessions.values.single.userId, 'user-1');
      expect(
        tracker.currentSession!.listenedDuration,
        const Duration(seconds: 5),
      );
    },
  );
  test('controller disposal closes active session as interrupted', () async {
    engine.emit(state(status: PlaybackStatus.playing));
    await controller.settled;

    now = now.add(const Duration(seconds: 9));

    await controller.dispose();

    expect(
      playbackSessions.values.single.endReason,
      PlaybackSessionEndReason.interrupted,
    );
  });
}

const track1 = PlaybackTrack(
  songId: 'song_1',
  title: 'Track 1',
  artistId: 'artist_1',
  artistName: 'Artist',
  albumId: 'album_1',
  albumTitle: 'Album',
  albumEditionId: 'edition_1',
  albumEditionTitle: 'Standard',
  filePath: 'C:/Music/track_1.mp3',
  duration: Duration(minutes: 3),
);

const track2 = PlaybackTrack(
  songId: 'song_2',
  title: 'Track 2',
  artistId: 'artist_1',
  artistName: 'Artist',
  albumId: 'album_1',
  albumTitle: 'Album',
  albumEditionId: 'edition_1',
  albumEditionTitle: 'Standard',
  filePath: 'C:/Music/track_2.mp3',
  duration: Duration(minutes: 3),
);

PlaybackState state({
  required PlaybackStatus status,
  PlaybackTrack track = track1,
  Duration position = Duration.zero,
  PlaybackTransitionCause? transitionCause,
}) {
  return PlaybackState(
    queue: PlaybackQueue(tracks: [track], currentIndex: 0),
    status: status,
    position: position,
    duration: track.duration,
    transitionCause: transitionCause,
  );
}

class _FakePlaybackEngine implements PlaybackEngine {
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
    await _states.close();
  }
}

class _MemoryPlaybackSessionRepository implements PlaybackSessionRepository {
  final Map<String, PlaybackSession> _values = {};

  List<PlaybackSession> get values => _values.values.toList(growable: false);

  @override
  Future<void> create(PlaybackSession session) async {
    _values[session.id] = session;
  }

  @override
  Future<void> save(PlaybackSession session) async {
    _values[session.id] = session;
  }

  @override
  Future<PlaybackSession?> getById(String id) async => _values[id];

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getOpen() async {
    return _values.values
        .where((session) => !session.isEnded)
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) async {
    final result =
        _values.values.where((session) {
          final startedAt = session.startedAt.toUtc();

          if (startedAtOrAfter != null &&
              startedAt.isBefore(startedAtOrAfter.toUtc())) {
            return false;
          }

          if (startedBefore != null &&
              !startedAt.isBefore(startedBefore.toUtc())) {
            return false;
          }

          if (before != null) {
            final cursorStartedAt = before.startedAt.toUtc();

            if (startedAt.isAfter(cursorStartedAt)) {
              return false;
            }

            if (startedAt == cursorStartedAt &&
                session.id.compareTo(before.sessionId) >= 0) {
              return false;
            }
          }

          return true;
        }).toList()..sort((a, b) {
          final byStartedAt = b.startedAt.compareTo(a.startedAt);

          if (byStartedAt != 0) {
            return byStartedAt;
          }

          return b.id.compareTo(a.id);
        });

    return result.take(limit).toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    return values;
  }
}

class _MemoryPlaybackListeningSegmentRepository
    implements PlaybackListeningSegmentRepository {
  final Map<String, PlaybackListeningSegment> _values = {};

  @override
  Future<void> create(PlaybackListeningSegment segment) async {
    if (_values.containsKey(segment.id)) {
      throw StateError('Duplicate listening segment: ${segment.id}');
    }

    _values[segment.id] = segment;
  }

  @override
  Future<void> save(PlaybackListeningSegment segment) async {
    if (!_values.containsKey(segment.id)) {
      throw StateError('Missing listening segment: ${segment.id}');
    }

    _values[segment.id] = segment;
  }

  @override
  Future<PlaybackListeningSegment?> getById(String id) async => _values[id];

  @override
  Future<PlaybackListeningSegment?> getOpenForSession(
    String playbackSessionId,
  ) async {
    final matches =
        _values.values
            .where(
              (segment) =>
                  segment.playbackSessionId == playbackSessionId &&
                  !segment.isEnded,
            )
            .toList()
          ..sort((a, b) {
            final byStartedAt = b.startedAt.compareTo(a.startedAt);

            if (byStartedAt != 0) {
              return byStartedAt;
            }

            return b.id.compareTo(a.id);
          });

    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<PlaybackListeningSegment>> getForSession(
    String playbackSessionId,
  ) async {
    final matches =
        _values.values
            .where((segment) => segment.playbackSessionId == playbackSessionId)
            .toList()
          ..sort((a, b) {
            final byStartedAt = a.startedAt.compareTo(b.startedAt);

            if (byStartedAt != 0) {
              return byStartedAt;
            }

            return a.id.compareTo(b.id);
          });

    return matches;
  }

  @override
  Future<List<PlaybackListeningSegment>> getAll({
    DateTime? startedBefore,
  }) async {
    final matches =
        _values.values
            .where(
              (segment) =>
                  startedBefore == null ||
                  segment.startedAt.isBefore(startedBefore),
            )
            .toList()
          ..sort((a, b) {
            final byStartedAt = a.startedAt.compareTo(b.startedAt);

            if (byStartedAt != 0) {
              return byStartedAt;
            }

            return a.id.compareTo(b.id);
          });

    return matches;
  }
}

class _MemoryQualifiedPlayRepository implements QualifiedPlayRepository {
  final Map<String, QualifiedPlay> _values = {};

  List<QualifiedPlay> get values => _values.values.toList(growable: false);

  @override
  Future<void> create(QualifiedPlay play) async {
    final duplicate = _values.values.any(
      (value) => value.playbackSessionId == play.playbackSessionId,
    );

    if (duplicate) {
      throw StateError('Session already qualified.');
    }

    _values[play.id] = play;
  }

  @override
  Future<void> save(QualifiedPlay play) async {
    if (!_values.containsKey(play.id)) {
      throw StateError('Qualified play not found: ${play.id}');
    }

    _values[play.id] = play;
  }

  @override
  Future<QualifiedPlay?> getById(String id) async => _values[id];

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(
    String playbackSessionId,
  ) async {
    for (final value in _values.values) {
      if (value.playbackSessionId == playbackSessionId) {
        return value;
      }
    }

    return null;
  }

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) async {
    final ids = playbackSessionIds.toSet();

    return _values.values
        .where((play) => ids.contains(play.playbackSessionId))
        .toList(growable: false);
  }

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    return values;
  }
}
