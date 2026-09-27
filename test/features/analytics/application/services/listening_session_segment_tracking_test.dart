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
  late DirectListeningSessionMutationRunner mutationRunner;
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
    var segmentNumber = 0;
    var playNumber = 0;
    mutationRunner = DirectListeningSessionMutationRunner(
      playbackSessions: playbackSessions,
      listeningSegments: listeningSegments,
      qualifiedPlays: qualifiedPlays,
    );

    tracker = ListeningSessionTracker(
      playbackSessions: playbackSessions,
      qualifiedPlays: qualifiedPlays,
      listeningSegments: listeningSegments,
      mutationRunner: mutationRunner,
      now: () => now,
      playbackSessionIdGenerator: () => 'session_${++sessionNumber}',
      listeningSegmentIdGenerator: () => 'segment_${++segmentNumber}',
      qualifiedPlayIdGenerator: () => 'play_${++playNumber}',
    );
  });

  test('starting paused creates no listening segment', () async {
    await tracker.start(start);

    expect(listeningSegments.values, isEmpty);
    expect(tracker.currentListeningSegment, isNull);
  });

  test('starting while playing creates one open segment', () async {
    await tracker.start(start, playing: true);

    expect(listeningSegments.values, hasLength(1));

    final segment = listeningSegments.values.single;

    expect(segment.id, 'segment_1');
    expect(segment.playbackSessionId, 'session_1');
    expect(segment.startedAt, now);
    expect(segment.endedAt, isNull);
    expect(segment.listenedDuration, Duration.zero);
  });

  test('checkpoints update the same continuous segment', () async {
    final startedAt = now;

    await tracker.start(start, playing: true);

    now = now.add(const Duration(seconds: 12));

    await tracker.checkpoint(position: const Duration(seconds: 12));

    now = now.add(const Duration(seconds: 8));

    await tracker.checkpoint(position: const Duration(seconds: 20));

    expect(listeningSegments.values, hasLength(1));

    final segment = listeningSegments.values.single;

    expect(segment.startedAt, startedAt);
    expect(segment.endedAt, isNull);
    expect(segment.listenedDuration, const Duration(seconds: 20));

    expect(
      tracker.currentSession!.listenedDuration,
      const Duration(seconds: 20),
    );
  });

  test('seek checkpoints do not split the segment', () async {
    await tracker.start(start, playing: true);

    now = now.add(const Duration(seconds: 10));

    await tracker.checkpoint(position: const Duration(minutes: 3));

    now = now.add(const Duration(seconds: 5));

    await tracker.checkpoint(position: const Duration(seconds: 30));

    expect(listeningSegments.values, hasLength(1));
    expect(
      listeningSegments.values.single.listenedDuration,
      const Duration(seconds: 15),
    );
    expect(
      tracker.currentSession!.listenedDuration,
      const Duration(seconds: 15),
    );
  });

  test('pause closes segment and resume creates a new one', () async {
    final firstStartedAt = now;

    await tracker.start(start, playing: true);

    now = now.add(const Duration(seconds: 20));

    await tracker.markPaused(position: const Duration(seconds: 20));

    expect(listeningSegments.values, hasLength(1));

    final first = listeningSegments.values.first;

    expect(first.startedAt, firstStartedAt);
    expect(first.endedAt, now);
    expect(first.listenedDuration, const Duration(seconds: 20));

    now = now.add(const Duration(minutes: 5));

    final resumedAt = now;

    await tracker.markPlaying(position: const Duration(seconds: 20));

    expect(listeningSegments.values, hasLength(2));

    final second = listeningSegments.values.last;

    expect(second.startedAt, resumedAt);
    expect(second.endedAt, isNull);
    expect(second.listenedDuration, Duration.zero);
  });

  test(
    'ending closes active segment and segment totals match session',
    () async {
      await tracker.start(start, playing: true);

      now = now.add(const Duration(seconds: 20));

      await tracker.markPaused(position: const Duration(seconds: 20));

      now = now.add(const Duration(minutes: 2));

      await tracker.markPlaying(position: const Duration(seconds: 20));

      now = now.add(const Duration(seconds: 15));

      final ended = await tracker.end(
        reason: PlaybackSessionEndReason.skipped,
        position: const Duration(seconds: 35),
      );

      expect(listeningSegments.values, hasLength(2));
      expect(
        listeningSegments.values.every((segment) => segment.isEnded),
        isTrue,
      );

      final segmentTotal = listeningSegments.values.fold<Duration>(
        Duration.zero,
        (total, segment) => total + segment.listenedDuration,
      );

      expect(segmentTotal, const Duration(seconds: 35));
      expect(ended.listenedDuration, segmentTotal);
    },
  );
  test('failed pause mutation leaves tracker state retryable', () async {
    await tracker.start(start, playing: true);

    final originalSegment = tracker.currentListeningSegment;

    now = now.add(const Duration(seconds: 12));
    mutationRunner.failNextMutation = true;

    await expectLater(
      tracker.markPaused(position: const Duration(seconds: 12)),
      throwsA(isA<StateError>()),
    );

    expect(tracker.isPlaying, isTrue);
    expect(tracker.currentSession!.listenedDuration, Duration.zero);
    expect(tracker.currentListeningSegment, same(originalSegment));
    expect(tracker.currentListeningSegment!.isEnded, isFalse);

    await tracker.markPaused(position: const Duration(seconds: 12));

    expect(tracker.isPlaying, isFalse);
    expect(
      tracker.currentSession!.listenedDuration,
      const Duration(seconds: 12),
    );
    expect(tracker.currentListeningSegment!.isEnded, isTrue);
    expect(
      tracker.currentListeningSegment!.listenedDuration,
      const Duration(seconds: 12),
    );
  });

  test('failed end mutation leaves tracker state retryable', () async {
    await tracker.start(start, playing: true);

    final originalSegment = tracker.currentListeningSegment;

    now = now.add(const Duration(seconds: 15));
    mutationRunner.failNextMutation = true;

    await expectLater(
      tracker.end(
        reason: PlaybackSessionEndReason.skipped,
        position: const Duration(seconds: 15),
      ),
      throwsA(isA<StateError>()),
    );

    expect(tracker.hasActiveSession, isTrue);
    expect(tracker.isPlaying, isTrue);
    expect(tracker.currentSession!.isEnded, isFalse);
    expect(tracker.currentSession!.listenedDuration, Duration.zero);
    expect(tracker.currentListeningSegment, same(originalSegment));
    expect(tracker.currentListeningSegment!.isEnded, isFalse);

    final ended = await tracker.end(
      reason: PlaybackSessionEndReason.skipped,
      position: const Duration(seconds: 15),
    );

    expect(ended.isEnded, isTrue);
    expect(ended.listenedDuration, const Duration(seconds: 15));
    expect(ended.endReason, PlaybackSessionEndReason.skipped);
    expect(tracker.hasActiveSession, isFalse);

    expect(listeningSegments.values, hasLength(1));
    expect(listeningSegments.values.single.isEnded, isTrue);
    expect(
      listeningSegments.values.single.listenedDuration,
      const Duration(seconds: 15),
    );
  });

  test(
    'markPlaying while already playing does not create another segment',
    () async {
      await tracker.start(start, playing: true);

      now = now.add(const Duration(seconds: 5));

      await tracker.markPlaying(position: const Duration(seconds: 5));

      expect(listeningSegments.values, hasLength(1));
      expect(
        listeningSegments.values.single.listenedDuration,
        const Duration(seconds: 5),
      );
    },
  );
}

class _MemoryPlaybackListeningSegmentRepository
    implements PlaybackListeningSegmentRepository {
  final Map<String, PlaybackListeningSegment> _values = {};

  List<PlaybackListeningSegment> get values {
    final result = _values.values.toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    return result;
  }

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
    for (final segment in values.reversed) {
      if (segment.playbackSessionId == playbackSessionId && !segment.isEnded) {
        return segment;
      }
    }

    return null;
  }

  @override
  Future<List<PlaybackListeningSegment>> getForSession(
    String playbackSessionId,
  ) async {
    return values
        .where((segment) => segment.playbackSessionId == playbackSessionId)
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackListeningSegment>> getAll({
    DateTime? startedBefore,
  }) async {
    return values
        .where((segment) {
          return startedBefore == null ||
              segment.startedAt.isBefore(startedBefore);
        })
        .toList(growable: false);
  }
}

class _MemoryPlaybackSessionRepository implements PlaybackSessionRepository {
  final Map<String, PlaybackSession> _values = {};

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
    return _values.values.toList(growable: false);
  }
}

class _MemoryQualifiedPlayRepository implements QualifiedPlayRepository {
  final Map<String, QualifiedPlay> _values = {};

  @override
  Future<void> create(QualifiedPlay play) async {
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
    for (final play in _values.values) {
      if (play.playbackSessionId == playbackSessionId) {
        return play;
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
    return _values.values.toList(growable: false);
  }
}
