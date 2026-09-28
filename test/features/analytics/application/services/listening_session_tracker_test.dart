import 'package:flutter_test/flutter_test.dart';

import '../../support/direct_listening_session_mutation_runner.dart';

import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';

import 'package:sonus_next/features/analytics/application/services/listening_session_start.dart';
import 'package:sonus_next/features/analytics/application/services/listening_session_tracker.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';

void main() {
  late DateTime now;
  late _MemoryPlaybackSessionRepository playbackSessions;
  late _MemoryQualifiedPlayRepository qualifiedPlays;
  late _MemoryPlaybackListeningSegmentRepository listeningSegments;
  late ListeningSessionTracker tracker;

  const start = ListeningSessionStart(
    songId: 'song_1',
    artistId: 'artist_1',
    albumId: 'album_1',
    albumEditionId: 'edition_1',
    songTitle: 'Test Song',
    artistName: 'Test Artist',
    albumTitle: 'Test Album',
    albumEditionTitle: 'Test Edition',
    trackDuration: Duration(minutes: 4),
    sourceContext: 'library',
  );

  setUp(() {
    now = DateTime.utc(2026, 9, 25, 12);

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
  });

  test('creates a session before playback begins', () async {
    final session = await tracker.start(start);

    expect(session.id, 'session_1');
    expect(session.listenedDuration, Duration.zero);
    expect(session.finalPosition, Duration.zero);
    expect(session.isEnded, isFalse);
    expect(tracker.isPlaying, isFalse);

    expect(playbackSessions.values, hasLength(1));
    expect(qualifiedPlays.values, isEmpty);
  });

  test('counts elapsed wall-clock time only while playing', () async {
    await tracker.start(start, playing: true);

    now = now.add(const Duration(seconds: 12));

    await tracker.checkpoint(position: const Duration(seconds: 12));

    now = now.add(const Duration(seconds: 8));

    await tracker.markPaused(position: const Duration(seconds: 20));

    now = now.add(const Duration(minutes: 5));

    await tracker.checkpoint(position: const Duration(seconds: 20));

    final session = tracker.currentSession!;

    expect(session.listenedDuration, const Duration(seconds: 20));
  });

  test('seek forward does not inflate listened duration', () async {
    await tracker.start(start, playing: true);

    now = now.add(const Duration(seconds: 10));

    await tracker.checkpoint(position: const Duration(minutes: 3));

    expect(
      tracker.currentSession!.listenedDuration,
      const Duration(seconds: 10),
    );
    expect(tracker.currentSession!.finalPosition, const Duration(minutes: 3));
  });

  test('seek backward can accumulate real repeated listening time', () async {
    await tracker.start(start, playing: true);

    now = now.add(const Duration(seconds: 20));

    await tracker.checkpoint(position: const Duration(seconds: 20));

    now = now.add(const Duration(seconds: 5));

    await tracker.checkpoint(position: const Duration(seconds: 5));

    now = now.add(const Duration(seconds: 10));

    await tracker.checkpoint(position: const Duration(seconds: 15));

    expect(
      tracker.currentSession!.listenedDuration,
      const Duration(seconds: 35),
    );
  });

  test('pause time does not count toward qualification', () async {
    await tracker.start(start, playing: true);

    now = now.add(const Duration(seconds: 20));

    await tracker.markPaused(position: const Duration(seconds: 20));

    now = now.add(const Duration(hours: 1));

    await tracker.markPlaying(position: const Duration(seconds: 20));

    now = now.add(const Duration(seconds: 9));

    await tracker.checkpoint(position: const Duration(seconds: 29));

    expect(qualifiedPlays.values, isEmpty);

    now = now.add(const Duration(seconds: 1));

    await tracker.checkpoint(position: const Duration(seconds: 30));

    expect(qualifiedPlays.values, hasLength(1));
  });

  test('qualifies exactly once after thirty audible seconds', () async {
    await tracker.start(start, playing: true);

    now = now.add(const Duration(seconds: 30));

    await tracker.checkpoint(position: const Duration(seconds: 30));

    expect(qualifiedPlays.values, hasLength(1));

    now = now.add(const Duration(seconds: 60));

    await tracker.checkpoint(position: const Duration(seconds: 90));

    expect(qualifiedPlays.values, hasLength(1));
    expect(qualifiedPlays.values.single.playbackSessionId, 'session_1');
  });

  test('qualification survives a later skip', () async {
    await tracker.start(start, playing: true);

    now = now.add(const Duration(seconds: 35));

    await tracker.checkpoint(position: const Duration(seconds: 35));

    now = now.add(const Duration(seconds: 2));

    final ended = await tracker.end(
      reason: PlaybackSessionEndReason.skipped,
      position: const Duration(seconds: 37),
    );

    expect(ended.endReason, PlaybackSessionEndReason.skipped);
    expect(ended.listenedDuration, const Duration(seconds: 37));
    expect(qualifiedPlays.values, hasLength(1));
  });

  test('short tracks qualify using the short-track rule', () async {
    const shortTrack = ListeningSessionStart(
      songId: 'short_song',
      artistId: 'artist_1',
      albumId: 'album_1',
      albumEditionId: 'edition_1',
      songTitle: 'Test Song',
      artistName: 'Test Artist',
      albumTitle: 'Test Album',
      albumEditionTitle: 'Test Edition',
      trackDuration: Duration(seconds: 20),
    );

    await tracker.start(shortTrack, playing: true);

    now = now.add(const Duration(seconds: 9));

    await tracker.checkpoint(position: const Duration(seconds: 9));

    expect(qualifiedPlays.values, isEmpty);

    now = now.add(const Duration(seconds: 1));

    await tracker.checkpoint(position: const Duration(seconds: 10));

    expect(qualifiedPlays.values, hasLength(1));
  });

  test(
    'ending before threshold preserves non-qualified listening history',
    () async {
      await tracker.start(start, playing: true);

      now = now.add(const Duration(seconds: 12));

      final ended = await tracker.end(
        reason: PlaybackSessionEndReason.skipped,
        position: const Duration(seconds: 12),
      );

      expect(ended.listenedDuration, const Duration(seconds: 12));
      expect(ended.isEnded, isTrue);
      expect(qualifiedPlays.values, isEmpty);
      expect(playbackSessions.values.single.isEnded, isTrue);
    },
  );

  test(
    'a new session can qualify independently after the previous one ends',
    () async {
      await tracker.start(start, playing: true);

      now = now.add(const Duration(seconds: 30));

      await tracker.end(
        reason: PlaybackSessionEndReason.completed,
        position: const Duration(minutes: 4),
      );

      await tracker.start(start, playing: true);

      now = now.add(const Duration(seconds: 30));

      await tracker.end(
        reason: PlaybackSessionEndReason.completed,
        position: const Duration(minutes: 4),
      );

      expect(playbackSessions.values, hasLength(2));
      expect(qualifiedPlays.values, hasLength(2));

      expect(qualifiedPlays.values.map((value) => value.playbackSessionId), [
        'session_1',
        'session_2',
      ]);
    },
  );

  test(
    'updated runtime duration replaces an unknown initial duration',
    () async {
      const unknownDuration = ListeningSessionStart(
        songId: 'song_unknown_duration',
        artistId: 'artist_1',
        albumId: 'album_1',
        albumEditionId: 'edition_1',
        songTitle: 'Test Song',
        artistName: 'Test Artist',
        albumTitle: 'Test Album',
        albumEditionTitle: 'Test Edition',
        trackDuration: Duration.zero,
      );

      await tracker.start(unknownDuration, playing: true);

      now = now.add(const Duration(seconds: 10));

      await tracker.checkpoint(
        position: const Duration(seconds: 10),
        trackDuration: const Duration(seconds: 20),
      );

      expect(
        tracker.currentSession!.trackDuration,
        const Duration(seconds: 20),
      );

      expect(qualifiedPlays.values, hasLength(1));
    },
  );

  test(
    'cannot start a second session before ending the current session',
    () async {
      await tracker.start(start);

      await expectLater(tracker.start(start), throwsA(isA<StateError>()));
    },
  );

  test(
    'active anonymous session attaches to user and stays owned through later writes',
    () async {
      await tracker.start(start, playing: true);

      expect(tracker.currentSession!.userId, isNull);
      expect(playbackSessions.values.single.userId, isNull);

      await tracker.attachCurrentSessionToUser(' user-1 ');

      expect(tracker.currentSession!.userId, 'user-1');
      expect(playbackSessions.values.single.userId, 'user-1');

      now = now.add(const Duration(seconds: 5));

      await tracker.checkpoint(position: const Duration(seconds: 5));

      expect(tracker.currentSession!.userId, 'user-1');
      expect(playbackSessions.values.single.userId, 'user-1');

      now = now.add(const Duration(seconds: 5));

      final ended = await tracker.end(
        reason: PlaybackSessionEndReason.skipped,
        position: const Duration(seconds: 10),
      );

      expect(ended.userId, 'user-1');
      expect(playbackSessions.values.single.userId, 'user-1');
    },
  );

  test(
    'attaching active anonymous session also attaches an existing qualified play',
    () async {
      await tracker.start(start, playing: true);

      now = now.add(const Duration(seconds: 30));

      await tracker.checkpoint(position: const Duration(seconds: 30));

      expect(qualifiedPlays.values, hasLength(1));
      expect(qualifiedPlays.values.single.userId, isNull);

      await tracker.attachCurrentSessionToUser('user-1');

      expect(tracker.currentSession!.userId, 'user-1');
      expect(playbackSessions.values.single.userId, 'user-1');
      expect(qualifiedPlays.values.single.userId, 'user-1');
    },
  );
  test('operations requiring a session fail when none is active', () async {
    await expectLater(
      tracker.checkpoint(position: Duration.zero),
      throwsA(isA<StateError>()),
    );

    await expectLater(tracker.markPlaying(), throwsA(isA<StateError>()));

    await expectLater(tracker.markPaused(), throwsA(isA<StateError>()));
  });
}

class _MemoryPlaybackSessionRepository implements PlaybackSessionRepository {
  final Map<String, PlaybackSession> _values = {};

  List<PlaybackSession> get values => _values.values.toList(growable: false);

  @override
  Future<void> create(PlaybackSession session) async {
    if (_values.containsKey(session.id)) {
      throw StateError('Duplicate playback session: ${session.id}');
    }

    _values[session.id] = session;
  }

  @override
  Future<void> save(PlaybackSession session) async {
    if (!_values.containsKey(session.id)) {
      throw StateError('Missing playback session: ${session.id}');
    }

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
    final result = _values.values.where((session) {
      if (startedAtOrAfter != null &&
          session.startedAt.isBefore(startedAtOrAfter)) {
        return false;
      }

      if (startedBefore != null && !session.startedAt.isBefore(startedBefore)) {
        return false;
      }

      return true;
    }).toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    return result;
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

  List<QualifiedPlay> get values {
    final result = _values.values.toList(growable: false)
      ..sort((a, b) => a.qualifiedAt.compareTo(b.qualifiedAt));

    return result;
  }

  @override
  Future<void> create(QualifiedPlay play) async {
    final duplicateSession = _values.values.any(
      (value) => value.playbackSessionId == play.playbackSessionId,
    );

    if (duplicateSession) {
      throw StateError(
        'Playback session already qualified: ${play.playbackSessionId}',
      );
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
    final result = _values.values.where((play) {
      if (qualifiedAtOrAfter != null &&
          play.qualifiedAt.isBefore(qualifiedAtOrAfter)) {
        return false;
      }

      if (qualifiedBefore != null &&
          !play.qualifiedAt.isBefore(qualifiedBefore)) {
        return false;
      }

      return true;
    }).toList()..sort((a, b) => a.qualifiedAt.compareTo(b.qualifiedAt));

    return result;
  }
}
