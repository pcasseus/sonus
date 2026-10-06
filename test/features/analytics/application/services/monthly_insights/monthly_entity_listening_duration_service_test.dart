import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/services/monthly_insights/monthly_entity_listening_duration_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';

void main() {
  group('MonthlyEntityListeningDurationService', () {
    test('aggregates audible duration for songs artists and albums', () async {
      final sessions = FakePlaybackSessionRepository(
        sessions: {
          'session-1': session(
            id: 'session-1',
            songId: 'song-1',
            artistId: 'artist-1',
            albumId: 'album-1',
          ),
          'session-2': session(
            id: 'session-2',
            songId: 'song-2',
            artistId: 'artist-1',
            albumId: 'album-1',
          ),
        },
      );

      final segments = FakeListeningSegmentRepository(
        segments: [
          segment(
            id: 'segment-1',
            sessionId: 'session-1',
            startedAt: DateTime.utc(2026, 10, 5, 12),
            duration: const Duration(minutes: 3),
          ),
          segment(
            id: 'segment-2',
            sessionId: 'session-2',
            startedAt: DateTime.utc(2026, 10, 6, 12),
            duration: const Duration(minutes: 4),
          ),
        ],
      );

      final service = MonthlyEntityListeningDurationService(
        playbackSessions: sessions,
        listeningSegments: segments,
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(result.song('song-1'), const Duration(minutes: 3));
      expect(result.song('song-2'), const Duration(minutes: 4));

      expect(result.artist('artist-1'), const Duration(minutes: 7));
      expect(result.album('album-1'), const Duration(minutes: 7));
    });

    test('clips listening duration to selected month boundaries', () async {
      final sessions = FakePlaybackSessionRepository(
        sessions: {
          'session-1': session(
            id: 'session-1',
            songId: 'song-1',
            artistId: 'artist-1',
            albumId: 'album-1',
          ),
        },
      );

      final segmentStartLocal = DateTime(2026, 9, 30, 23, 59);

      final segments = FakeListeningSegmentRepository(
        segments: [
          segment(
            id: 'segment-1',
            sessionId: 'session-1',
            startedAt: segmentStartLocal.toUtc(),
            duration: const Duration(minutes: 2),
          ),
        ],
      );

      final service = MonthlyEntityListeningDurationService(
        playbackSessions: sessions,
        listeningSegments: segments,
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(result.song('song-1'), const Duration(minutes: 1));
      expect(result.artist('artist-1'), const Duration(minutes: 1));
      expect(result.album('album-1'), const Duration(minutes: 1));
    });

    test('ignores segments completely outside selected month', () async {
      final sessions = FakePlaybackSessionRepository(
        sessions: {
          'session-1': session(
            id: 'session-1',
            songId: 'song-1',
            artistId: 'artist-1',
            albumId: 'album-1',
          ),
        },
      );

      final segments = FakeListeningSegmentRepository(
        segments: [
          segment(
            id: 'segment-1',
            sessionId: 'session-1',
            startedAt: DateTime.utc(2026, 9, 20, 12),
            duration: const Duration(minutes: 5),
          ),
        ],
      );

      final service = MonthlyEntityListeningDurationService(
        playbackSessions: sessions,
        listeningSegments: segments,
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(result.songs, isEmpty);
      expect(result.artists, isEmpty);
      expect(result.albums, isEmpty);
    });

    test('ignores orphaned listening segments', () async {
      final sessions = FakePlaybackSessionRepository(sessions: const {});

      final segments = FakeListeningSegmentRepository(
        segments: [
          segment(
            id: 'segment-orphan',
            sessionId: 'missing-session',
            startedAt: DateTime.utc(2026, 10, 5, 12),
            duration: const Duration(minutes: 5),
          ),
        ],
      );

      final service = MonthlyEntityListeningDurationService(
        playbackSessions: sessions,
        listeningSegments: segments,
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(result.songs, isEmpty);
      expect(result.artists, isEmpty);
      expect(result.albums, isEmpty);
    });

    test('uses listened duration for open segment endpoint', () async {
      final sessions = FakePlaybackSessionRepository(
        sessions: {
          'session-1': session(
            id: 'session-1',
            songId: 'song-1',
            artistId: 'artist-1',
            albumId: 'album-1',
          ),
        },
      );

      final startedAt = DateTime.utc(2026, 10, 5, 12);

      final segments = FakeListeningSegmentRepository(
        segments: [
          PlaybackListeningSegment(
            id: 'segment-1',
            playbackSessionId: 'session-1',
            startedAt: startedAt,
            endedAt: null,
            listenedDuration: const Duration(seconds: 42),
            createdAt: startedAt,
            updatedAt: startedAt.add(const Duration(seconds: 42)),
          ),
        ],
      );

      final service = MonthlyEntityListeningDurationService(
        playbackSessions: sessions,
        listeningSegments: segments,
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(result.song('song-1'), const Duration(seconds: 42));
    });

    test('batch loads playback sessions for overlapping segments', () async {
      final sessions = FakePlaybackSessionRepository(
        sessions: {
          'session-1': session(
            id: 'session-1',
            songId: 'song-1',
            artistId: 'artist-1',
            albumId: 'album-1',
          ),
          'session-2': session(
            id: 'session-2',
            songId: 'song-2',
            artistId: 'artist-2',
            albumId: 'album-2',
          ),
        },
      );

      final segments = FakeListeningSegmentRepository(
        segments: [
          segment(
            id: 'segment-1',
            sessionId: 'session-1',
            startedAt: DateTime.utc(2026, 10, 5, 12),
            duration: const Duration(minutes: 3),
          ),
          segment(
            id: 'segment-2',
            sessionId: 'session-1',
            startedAt: DateTime.utc(2026, 10, 5, 13),
            duration: const Duration(minutes: 2),
          ),
          segment(
            id: 'segment-3',
            sessionId: 'session-2',
            startedAt: DateTime.utc(2026, 10, 6, 12),
            duration: const Duration(minutes: 4),
          ),
        ],
      );

      final service = MonthlyEntityListeningDurationService(
        playbackSessions: sessions,
        listeningSegments: segments,
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(sessions.getByIdsCallCount, 1);
      expect(sessions.getByIdCallCount, 0);

      expect(result.song('song-1'), const Duration(minutes: 5));
      expect(result.song('song-2'), const Duration(minutes: 4));
    });
    test('missing entity lookup returns zero duration', () async {
      final service = MonthlyEntityListeningDurationService(
        playbackSessions: FakePlaybackSessionRepository(sessions: const {}),
        listeningSegments: FakeListeningSegmentRepository(segments: const []),
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(result.song('missing'), Duration.zero);
      expect(result.artist('missing'), Duration.zero);
      expect(result.album('missing'), Duration.zero);
    });
  });
}

PlaybackSession session({
  required String id,
  required String songId,
  required String artistId,
  required String albumId,
}) {
  final startedAt = DateTime.utc(2026, 10, 1);

  return PlaybackSession(
    id: id,
    songId: songId,
    artistId: artistId,
    albumId: albumId,
    albumEditionId: 'edition-1',
    songTitle: 'Song',
    artistName: 'Artist',
    albumTitle: 'Album',
    albumEditionTitle: 'Standard',
    startedAt: startedAt,
    listenedDuration: Duration.zero,
    trackDuration: const Duration(minutes: 4),
    finalPosition: Duration.zero,
    createdAt: startedAt,
    updatedAt: startedAt,
  );
}

PlaybackListeningSegment segment({
  required String id,
  required String sessionId,
  required DateTime startedAt,
  required Duration duration,
}) {
  return PlaybackListeningSegment(
    id: id,
    playbackSessionId: sessionId,
    startedAt: startedAt,
    endedAt: startedAt.add(duration),
    listenedDuration: duration,
    createdAt: startedAt,
    updatedAt: startedAt.add(duration),
  );
}

class FakePlaybackSessionRepository implements PlaybackSessionRepository {
  FakePlaybackSessionRepository({required this.sessions});

  final Map<String, PlaybackSession> sessions;

  int getByIdCallCount = 0;
  int getByIdsCallCount = 0;

  @override
  Future<PlaybackSession?> getById(String id) async {
    getByIdCallCount++;
    return sessions[id];
  }

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) async {
    getByIdsCallCount++;
    return ids
        .map((id) => sessions[id])
        .whereType<PlaybackSession>()
        .toList(growable: false);
  }

  @override
  Future<void> create(PlaybackSession session) {
    throw UnimplementedError();
  }

  @override
  Future<void> save(PlaybackSession session) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getOpen() async => const [];

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    return sessions.values.toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) async {
    return const [];
  }
}

class FakeListeningSegmentRepository
    implements PlaybackListeningSegmentRepository {
  FakeListeningSegmentRepository({required this.segments});

  final List<PlaybackListeningSegment> segments;

  @override
  Future<List<PlaybackListeningSegment>> getAll({
    DateTime? startedBefore,
  }) async {
    if (startedBefore == null) {
      return segments;
    }

    return segments
        .where((segment) => segment.startedAt.isBefore(startedBefore))
        .toList(growable: false);
  }

  @override
  Future<void> create(PlaybackListeningSegment segment) {
    throw UnimplementedError();
  }

  @override
  Future<void> save(PlaybackListeningSegment segment) {
    throw UnimplementedError();
  }

  @override
  Future<PlaybackListeningSegment?> getById(String id) async => null;

  @override
  Future<PlaybackListeningSegment?> getOpenForSession(
    String playbackSessionId,
  ) async {
    return null;
  }

  @override
  Future<List<PlaybackListeningSegment>> getForSession(
    String playbackSessionId,
  ) async {
    return segments
        .where((segment) => segment.playbackSessionId == playbackSessionId)
        .toList(growable: false);
  }
}
