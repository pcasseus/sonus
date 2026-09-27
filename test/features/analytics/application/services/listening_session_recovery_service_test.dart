import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';

import 'package:sonus_next/features/analytics/application/services/listening_session_recovery_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';

void main() {
  late _MemoryPlaybackSessionRepository playbackSessions;
  late _MemoryPlaybackListeningSegmentRepository listeningSegments;
  late ListeningSessionRecoveryService service;

  setUp(() {
    playbackSessions = _MemoryPlaybackSessionRepository();
    listeningSegments = _MemoryPlaybackListeningSegmentRepository();

    service = ListeningSessionRecoveryService(
      playbackSessions: playbackSessions,
      listeningSegments: listeningSegments,
    );
  });

  test('closes stale open sessions as interrupted', () async {
    final startedAt = DateTime.utc(2026, 9, 25, 12);
    final checkpointAt = startedAt.add(const Duration(seconds: 25));

    playbackSessions.seed(
      PlaybackSession(
        id: 'session_open',
        songId: 'song_1',
        artistId: 'artist_1',
        albumId: 'album_1',
        albumEditionId: 'edition_1',
        songTitle: 'Recovery Song',
        artistName: 'Recovery Artist',
        albumTitle: 'Recovery Album',
        albumEditionTitle: 'Recovery Edition',
        startedAt: startedAt,
        listenedDuration: const Duration(seconds: 25),
        trackDuration: const Duration(minutes: 4),
        finalPosition: const Duration(seconds: 25),
        createdAt: startedAt,
        updatedAt: checkpointAt,
      ),
    );

    listeningSegments.seed(
      PlaybackListeningSegment(
        id: 'segment_open',
        playbackSessionId: 'session_open',
        startedAt: startedAt,
        listenedDuration: const Duration(seconds: 25),
        createdAt: startedAt,
        updatedAt: checkpointAt,
      ),
    );

    final recovered = await service.recoverInterruptedSessions();

    expect(recovered, 1);

    final session = await playbackSessions.getById('session_open');
    final segment = await listeningSegments.getById('segment_open');

    expect(session, isNotNull);
    expect(session!.isEnded, isTrue);
    expect(session.endReason, PlaybackSessionEndReason.interrupted);
    expect(session.endedAt, checkpointAt);
    expect(session.updatedAt, checkpointAt);
    expect(session.listenedDuration, const Duration(seconds: 25));

    expect(segment, isNotNull);
    expect(segment!.endedAt, checkpointAt);
    expect(segment.listenedDuration, const Duration(seconds: 25));
  });

  test(
    'repairs stale session aggregate from newer persisted segment',
    () async {
      final startedAt = DateTime.utc(2026, 9, 25, 12);
      final sessionCheckpoint = startedAt.add(const Duration(seconds: 20));
      final segmentCheckpoint = startedAt.add(const Duration(seconds: 25));

      playbackSessions.seed(
        PlaybackSession(
          id: 'session_partial_write',
          songId: 'song_1',
          artistId: 'artist_1',
          albumId: 'album_1',
          albumEditionId: 'edition_1',
          songTitle: 'Recovery Song',
          artistName: 'Recovery Artist',
          albumTitle: 'Recovery Album',
          albumEditionTitle: 'Recovery Edition',
          startedAt: startedAt,
          listenedDuration: const Duration(seconds: 20),
          trackDuration: const Duration(minutes: 4),
          finalPosition: const Duration(seconds: 20),
          createdAt: startedAt,
          updatedAt: sessionCheckpoint,
        ),
      );

      listeningSegments.seed(
        PlaybackListeningSegment(
          id: 'segment_partial_write',
          playbackSessionId: 'session_partial_write',
          startedAt: startedAt,
          listenedDuration: const Duration(seconds: 25),
          createdAt: startedAt,
          updatedAt: segmentCheckpoint,
        ),
      );

      final recovered = await service.recoverInterruptedSessions();

      expect(recovered, 1);

      final session = await playbackSessions.getById('session_partial_write');

      final segment = await listeningSegments.getById('segment_partial_write');

      expect(session!.listenedDuration, const Duration(seconds: 25));
      expect(session.endedAt, segmentCheckpoint);
      expect(session.updatedAt, segmentCheckpoint);
      expect(session.endReason, PlaybackSessionEndReason.interrupted);

      expect(segment!.endedAt, segmentCheckpoint);
      expect(segment.listenedDuration, const Duration(seconds: 25));
    },
  );

  test(
    'open segment recovery uses persisted listened duration instead of updatedAt',
    () async {
      final startedAt = DateTime.utc(2026, 9, 25, 12);
      final sessionCheckpoint = startedAt.add(const Duration(seconds: 20));
      final truthfulSegmentEndpoint = startedAt.add(
        const Duration(seconds: 25),
      );
      final misleadingUpdatedAt = startedAt.add(const Duration(minutes: 5));

      playbackSessions.seed(
        PlaybackSession(
          id: 'session_misleading_segment_metadata',
          songId: 'song_1',
          artistId: 'artist_1',
          albumId: 'album_1',
          albumEditionId: 'edition_1',
          songTitle: 'Recovery Song',
          artistName: 'Recovery Artist',
          albumTitle: 'Recovery Album',
          albumEditionTitle: 'Recovery Edition',
          startedAt: startedAt,
          listenedDuration: const Duration(seconds: 20),
          trackDuration: const Duration(minutes: 4),
          finalPosition: const Duration(seconds: 20),
          createdAt: startedAt,
          updatedAt: sessionCheckpoint,
        ),
      );

      listeningSegments.seed(
        PlaybackListeningSegment(
          id: 'segment_misleading_metadata',
          playbackSessionId: 'session_misleading_segment_metadata',
          startedAt: startedAt,
          listenedDuration: const Duration(seconds: 25),
          createdAt: startedAt,
          updatedAt: misleadingUpdatedAt,
        ),
      );

      final recovered = await service.recoverInterruptedSessions();

      expect(recovered, 1);

      final session = await playbackSessions.getById(
        'session_misleading_segment_metadata',
      );

      final segment = await listeningSegments.getById(
        'segment_misleading_metadata',
      );

      expect(session, isNotNull);
      expect(segment, isNotNull);

      expect(segment!.endedAt, truthfulSegmentEndpoint);
      expect(segment.listenedDuration, const Duration(seconds: 25));

      expect(session!.listenedDuration, const Duration(seconds: 25));
      expect(session.endedAt, truthfulSegmentEndpoint);
      expect(session.updatedAt, truthfulSegmentEndpoint);
      expect(session.endReason, PlaybackSessionEndReason.interrupted);

      expect(session.endedAt, isNot(misleadingUpdatedAt));
    },
  );
  test('sums multiple persisted segments during recovery', () async {
    final startedAt = DateTime.utc(2026, 9, 25, 12);
    final firstEndedAt = startedAt.add(const Duration(seconds: 10));
    final resumedAt = startedAt.add(const Duration(minutes: 1));
    final secondCheckpoint = resumedAt.add(const Duration(seconds: 15));

    playbackSessions.seed(
      PlaybackSession(
        id: 'session_multiple_segments',
        songId: 'song_1',
        artistId: 'artist_1',
        albumId: 'album_1',
        albumEditionId: 'edition_1',
        songTitle: 'Recovery Song',
        artistName: 'Recovery Artist',
        albumTitle: 'Recovery Album',
        albumEditionTitle: 'Recovery Edition',
        startedAt: startedAt,
        listenedDuration: const Duration(seconds: 10),
        trackDuration: const Duration(minutes: 4),
        finalPosition: const Duration(seconds: 25),
        createdAt: startedAt,
        updatedAt: firstEndedAt,
      ),
    );

    listeningSegments.seed(
      PlaybackListeningSegment(
        id: 'segment_1',
        playbackSessionId: 'session_multiple_segments',
        startedAt: startedAt,
        endedAt: firstEndedAt,
        listenedDuration: const Duration(seconds: 10),
        createdAt: startedAt,
        updatedAt: firstEndedAt,
      ),
    );

    listeningSegments.seed(
      PlaybackListeningSegment(
        id: 'segment_2',
        playbackSessionId: 'session_multiple_segments',
        startedAt: resumedAt,
        listenedDuration: const Duration(seconds: 15),
        createdAt: resumedAt,
        updatedAt: secondCheckpoint,
      ),
    );

    await service.recoverInterruptedSessions();

    final session = await playbackSessions.getById('session_multiple_segments');

    expect(session!.listenedDuration, const Duration(seconds: 25));
    expect(session.endedAt, secondCheckpoint);

    final second = await listeningSegments.getById('segment_2');

    expect(second!.endedAt, secondCheckpoint);
  });

  test('does not change sessions that already ended', () async {
    final startedAt = DateTime.utc(2026, 9, 25, 12);
    final endedAt = startedAt.add(const Duration(seconds: 40));

    playbackSessions.seed(
      PlaybackSession(
        id: 'session_closed',
        songId: 'song_1',
        artistId: 'artist_1',
        albumId: 'album_1',
        albumEditionId: 'edition_1',
        songTitle: 'Recovery Song',
        artistName: 'Recovery Artist',
        albumTitle: 'Recovery Album',
        albumEditionTitle: 'Recovery Edition',
        startedAt: startedAt,
        endedAt: endedAt,
        listenedDuration: const Duration(seconds: 40),
        trackDuration: const Duration(minutes: 4),
        finalPosition: const Duration(seconds: 40),
        endReason: PlaybackSessionEndReason.skipped,
        createdAt: startedAt,
        updatedAt: endedAt,
      ),
    );

    final recovered = await service.recoverInterruptedSessions();

    expect(recovered, 0);

    final session = await playbackSessions.getById('session_closed');

    expect(session!.endReason, PlaybackSessionEndReason.skipped);
  });

  test('recovers every open session independently', () async {
    final firstStart = DateTime.utc(2026, 9, 25, 10);
    final secondStart = DateTime.utc(2026, 9, 25, 11);

    playbackSessions.seed(
      _session(id: 'session_1', startedAt: firstStart, updatedAt: firstStart),
    );

    playbackSessions.seed(
      _session(id: 'session_2', startedAt: secondStart, updatedAt: secondStart),
    );

    listeningSegments.seed(
      _segment(
        id: 'segment_1',
        playbackSessionId: 'session_1',
        startedAt: firstStart,
        updatedAt: firstStart.add(const Duration(seconds: 10)),
      ),
    );

    listeningSegments.seed(
      _segment(
        id: 'segment_2',
        playbackSessionId: 'session_2',
        startedAt: secondStart,
        updatedAt: secondStart.add(const Duration(seconds: 20)),
      ),
    );

    final recovered = await service.recoverInterruptedSessions();

    expect(recovered, 2);

    expect((await playbackSessions.getById('session_1'))!.isEnded, isTrue);
    expect((await playbackSessions.getById('session_2'))!.isEnded, isTrue);

    expect(
      (await playbackSessions.getById('session_1'))!.listenedDuration,
      const Duration(seconds: 10),
    );

    expect(
      (await playbackSessions.getById('session_2'))!.listenedDuration,
      const Duration(seconds: 20),
    );
  });
}

PlaybackSession _session({
  required String id,
  required DateTime startedAt,
  required DateTime updatedAt,
}) {
  return PlaybackSession(
    id: id,
    songId: 'song_1',
    artistId: 'artist_1',
    albumId: 'album_1',
    albumEditionId: 'edition_1',
    songTitle: 'Recovery Song',
    artistName: 'Recovery Artist',
    albumTitle: 'Recovery Album',
    albumEditionTitle: 'Recovery Edition',
    startedAt: startedAt,
    listenedDuration: Duration.zero,
    trackDuration: const Duration(minutes: 4),
    finalPosition: Duration.zero,
    createdAt: startedAt,
    updatedAt: updatedAt,
  );
}

PlaybackListeningSegment _segment({
  required String id,
  required String playbackSessionId,
  required DateTime startedAt,
  required DateTime updatedAt,
}) {
  return PlaybackListeningSegment(
    id: id,
    playbackSessionId: playbackSessionId,
    startedAt: startedAt,
    listenedDuration: updatedAt.isAfter(startedAt)
        ? updatedAt.difference(startedAt)
        : Duration.zero,
    createdAt: startedAt,
    updatedAt: updatedAt,
  );
}

class _MemoryPlaybackSessionRepository implements PlaybackSessionRepository {
  final Map<String, PlaybackSession> _values = {};

  void seed(PlaybackSession session) {
    _values[session.id] = session;
  }

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

class _MemoryPlaybackListeningSegmentRepository
    implements PlaybackListeningSegmentRepository {
  final Map<String, PlaybackListeningSegment> _values = {};

  void seed(PlaybackListeningSegment segment) {
    _values[segment.id] = segment;
  }

  List<PlaybackListeningSegment> get values {
    final result = _values.values.toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    return result;
  }

  @override
  Future<void> create(PlaybackListeningSegment segment) async {
    _values[segment.id] = segment;
  }

  @override
  Future<void> save(PlaybackListeningSegment segment) async {
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
