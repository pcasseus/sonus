import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_behavior_metrics_service.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_entity_ranking_service.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_listening_duration_service.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_summary_service.dart';
import 'package:sonus_next/features/analytics/application/services/monthly_insights/monthly_entity_listening_duration_service.dart';
import 'package:sonus_next/features/analytics/application/services/monthly_insights/monthly_listening_distribution_service.dart';
import 'package:sonus_next/features/analytics/application/services/monthly_insights/monthly_listening_insights_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';

void main() {
  group('MonthlyListeningInsightsService', () {
    test(
      'assembles selected month previous month and lifetime analytics',
      () async {
        final septemberA = DateTime(2026, 9, 12, 9);
        final septemberB1 = DateTime(2026, 9, 15, 10);
        final septemberB2 = DateTime(2026, 9, 15, 11);

        final octoberA1 = DateTime(2026, 10, 10, 8);
        final octoberA2 = DateTime(2026, 10, 10, 9);
        final octoberA3 = DateTime(2026, 10, 10, 10);
        final octoberC = DateTime(2026, 10, 20, 20);

        final playbackSessions = FakePlaybackSessionRepository(
          sessions: [
            session(
              id: 'session-sep-a',
              songId: 'song-a',
              artistId: 'artist-a',
              albumId: 'album-a',
              startedAt: septemberA.toUtc(),
              endReason: PlaybackSessionEndReason.completed,
            ),
            session(
              id: 'session-sep-b-1',
              songId: 'song-b',
              artistId: 'artist-b',
              albumId: 'album-b',
              startedAt: septemberB1.toUtc(),
              endReason: PlaybackSessionEndReason.completed,
            ),
            session(
              id: 'session-sep-b-2',
              songId: 'song-b',
              artistId: 'artist-b',
              albumId: 'album-b',
              startedAt: septemberB2.toUtc(),
              endReason: PlaybackSessionEndReason.skipped,
            ),
            session(
              id: 'session-oct-a-1',
              songId: 'song-a',
              artistId: 'artist-a',
              albumId: 'album-a',
              startedAt: octoberA1.toUtc(),
              endReason: PlaybackSessionEndReason.completed,
            ),
            session(
              id: 'session-oct-a-2',
              songId: 'song-a',
              artistId: 'artist-a',
              albumId: 'album-a',
              startedAt: octoberA2.toUtc(),
              endReason: PlaybackSessionEndReason.completed,
            ),
            session(
              id: 'session-oct-a-3',
              songId: 'song-a',
              artistId: 'artist-a',
              albumId: 'album-a',
              startedAt: octoberA3.toUtc(),
              endReason: PlaybackSessionEndReason.skipped,
            ),
            session(
              id: 'session-oct-c',
              songId: 'song-c',
              artistId: 'artist-c',
              albumId: 'album-c',
              startedAt: octoberC.toUtc(),
              endReason: PlaybackSessionEndReason.completed,
            ),
          ],
        );

        final qualifiedPlays = FakeQualifiedPlayRepository(
          plays: [
            play(
              id: 'play-sep-a',
              sessionId: 'session-sep-a',
              songId: 'song-a',
              artistId: 'artist-a',
              albumId: 'album-a',
              qualifiedAt: septemberA.toUtc(),
            ),
            play(
              id: 'play-sep-b-1',
              sessionId: 'session-sep-b-1',
              songId: 'song-b',
              artistId: 'artist-b',
              albumId: 'album-b',
              qualifiedAt: septemberB1.toUtc(),
            ),
            play(
              id: 'play-sep-b-2',
              sessionId: 'session-sep-b-2',
              songId: 'song-b',
              artistId: 'artist-b',
              albumId: 'album-b',
              qualifiedAt: septemberB2.toUtc(),
            ),
            play(
              id: 'play-oct-a-1',
              sessionId: 'session-oct-a-1',
              songId: 'song-a',
              artistId: 'artist-a',
              albumId: 'album-a',
              qualifiedAt: octoberA1.toUtc(),
            ),
            play(
              id: 'play-oct-a-2',
              sessionId: 'session-oct-a-2',
              songId: 'song-a',
              artistId: 'artist-a',
              albumId: 'album-a',
              qualifiedAt: octoberA2.toUtc(),
            ),
            play(
              id: 'play-oct-a-3',
              sessionId: 'session-oct-a-3',
              songId: 'song-a',
              artistId: 'artist-a',
              albumId: 'album-a',
              qualifiedAt: octoberA3.toUtc(),
            ),
            play(
              id: 'play-oct-c',
              sessionId: 'session-oct-c',
              songId: 'song-c',
              artistId: 'artist-c',
              albumId: 'album-c',
              qualifiedAt: octoberC.toUtc(),
            ),
          ],
        );

        final listeningSegments = FakeListeningSegmentRepository(
          segments: [
            segment(
              id: 'segment-sep-a',
              sessionId: 'session-sep-a',
              startedAt: septemberA.toUtc(),
              duration: const Duration(minutes: 1),
            ),
            segment(
              id: 'segment-sep-b-1',
              sessionId: 'session-sep-b-1',
              startedAt: septemberB1.toUtc(),
              duration: const Duration(minutes: 2),
            ),
            segment(
              id: 'segment-sep-b-2',
              sessionId: 'session-sep-b-2',
              startedAt: septemberB2.toUtc(),
              duration: const Duration(minutes: 3),
            ),
            segment(
              id: 'segment-oct-a-1',
              sessionId: 'session-oct-a-1',
              startedAt: octoberA1.toUtc(),
              duration: const Duration(minutes: 2),
            ),
            segment(
              id: 'segment-oct-a-2',
              sessionId: 'session-oct-a-2',
              startedAt: octoberA2.toUtc(),
              duration: const Duration(minutes: 3),
            ),
            segment(
              id: 'segment-oct-a-3',
              sessionId: 'session-oct-a-3',
              startedAt: octoberA3.toUtc(),
              duration: const Duration(minutes: 4),
            ),
            segment(
              id: 'segment-oct-c',
              sessionId: 'session-oct-c',
              startedAt: octoberC.toUtc(),
              duration: const Duration(minutes: 5),
            ),
          ],
        );

        final service = MonthlyListeningInsightsService(
          summaries: AnalyticsSummaryService(qualifiedPlays: qualifiedPlays),
          listeningDurations: AnalyticsListeningDurationService(
            listeningSegments: listeningSegments,
          ),
          behaviorMetrics: AnalyticsBehaviorMetricsService(
            playbackSessions: playbackSessions,
            qualifiedPlays: qualifiedPlays,
          ),
          rankings: AnalyticsEntityRankingService(
            qualifiedPlays: qualifiedPlays,
          ),
          entityListeningDurations: MonthlyEntityListeningDurationService(
            playbackSessions: playbackSessions,
            listeningSegments: listeningSegments,
          ),
          distribution: MonthlyListeningDistributionService(
            qualifiedPlays: qualifiedPlays,
            listeningSegments: listeningSegments,
          ),
        );

        final result = await service.load(
          referenceLocal: DateTime(2026, 10, 25),
        );

        expect(result.selectedMonth, DateTime(2026, 10));
        expect(result.previousMonth, DateTime(2026, 9));

        expect(result.currentSummary.period, AnalyticsPeriod.month);
        expect(result.currentSummary.qualifiedStreamCount, 4);
        expect(result.previousSummary.qualifiedStreamCount, 3);

        expect(result.streamChange.absoluteChange, 1);
        expect(result.streamChange.percentChange, closeTo(1 / 3, 0.0001));

        expect(
          result.currentAudibleListeningDuration,
          const Duration(minutes: 14),
        );

        expect(
          result.previousAudibleListeningDuration,
          const Duration(minutes: 6),
        );

        expect(
          result.listeningTimeChange.absoluteChange,
          const Duration(minutes: 8),
        );

        expect(
          result.listeningTimeChange.percentChange,
          closeTo(8 / 6, 0.0001),
        );

        expect(result.currentSummary.distinctSongCount, 2);
        expect(result.currentSummary.distinctArtistCount, 2);
        expect(result.currentSummary.distinctAlbumCount, 2);

        expect(result.previousSummary.distinctSongCount, 2);
        expect(result.previousSummary.distinctArtistCount, 2);
        expect(result.previousSummary.distinctAlbumCount, 2);

        expect(result.trackCountChange.absoluteChange, 0);
        expect(result.artistCountChange.absoluteChange, 0);
        expect(result.albumCountChange.absoluteChange, 0);

        expect(result.songs, hasLength(2));

        expect(result.songs[0].entityId, 'song-a');
        expect(result.songs[0].rank, 1);
        expect(result.songs[0].previousRank, 2);
        expect(result.songs[0].rankMovement, 1);
        expect(result.songs[0].streams, 3);
        expect(result.songs[0].previousStreams, 1);
        expect(result.songs[0].lifetimeStreams, 4);

        expect(result.songs[1].entityId, 'song-c');
        expect(result.songs[1].rank, 2);
        expect(result.songs[1].previousRank, isNull);
        expect(result.songs[1].isNew, isTrue);
        expect(result.songs[1].streams, 1);
        expect(result.songs[1].previousStreams, 0);
        expect(result.songs[1].lifetimeStreams, 1);

        expect(result.artists[0].entityId, 'artist-a');
        expect(result.artists[0].streams, 3);
        expect(result.artists[0].lifetimeStreams, 4);

        expect(result.albums[0].entityId, 'album-a');
        expect(result.albums[0].streams, 3);
        expect(result.albums[0].lifetimeStreams, 4);

        expect(
          result.entityListeningDurations.song('song-a'),
          const Duration(minutes: 9),
        );

        expect(
          result.entityListeningDurations.song('song-c'),
          const Duration(minutes: 5),
        );

        expect(
          result.entityListeningDurations.artist('artist-a'),
          const Duration(minutes: 9),
        );

        expect(
          result.entityListeningDurations.album('album-a'),
          const Duration(minutes: 9),
        );

        expect(result.behavior.sessionCount, 4);
        expect(result.behavior.completedSessionCount, 3);
        expect(result.behavior.skippedSessionCount, 1);

        expect(result.behavior.activeQualifiedDayCount, 2);
        expect(result.behavior.peakDay?.qualifiedStreamCount, 3);

        expect(result.behavior.peakDay?.localDate, DateTime(2026, 10, 10));

        expect(
          result.distribution.busiestDay?.localDate,
          DateTime(2026, 10, 10),
        );

        expect(result.distribution.busiestDay?.streams, 3);

        expect(result.hasListening, isTrue);
      },
    );

    test('handles a month with no listening activity', () async {
      final playbackSessions = FakePlaybackSessionRepository(
        sessions: const [],
      );

      final qualifiedPlays = FakeQualifiedPlayRepository(plays: const []);

      final listeningSegments = FakeListeningSegmentRepository(
        segments: const [],
      );

      final service = MonthlyListeningInsightsService(
        summaries: AnalyticsSummaryService(qualifiedPlays: qualifiedPlays),
        listeningDurations: AnalyticsListeningDurationService(
          listeningSegments: listeningSegments,
        ),
        behaviorMetrics: AnalyticsBehaviorMetricsService(
          playbackSessions: playbackSessions,
          qualifiedPlays: qualifiedPlays,
        ),
        rankings: AnalyticsEntityRankingService(qualifiedPlays: qualifiedPlays),
        entityListeningDurations: MonthlyEntityListeningDurationService(
          playbackSessions: playbackSessions,
          listeningSegments: listeningSegments,
        ),
        distribution: MonthlyListeningDistributionService(
          qualifiedPlays: qualifiedPlays,
          listeningSegments: listeningSegments,
        ),
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(result.currentSummary.qualifiedStreamCount, 0);

      expect(result.currentAudibleListeningDuration, Duration.zero);

      expect(result.songs, isEmpty);
      expect(result.artists, isEmpty);
      expect(result.albums, isEmpty);

      expect(result.streamChange.percentChange, 0);
      expect(result.listeningTimeChange.percentChange, 0);

      expect(result.hasListening, isFalse);

      expect(result.distribution.days, hasLength(31));
      expect(result.distribution.hours, hasLength(24));
    });
  });
}

QualifiedPlay play({
  required String id,
  required String sessionId,
  required String songId,
  required String artistId,
  required String albumId,
  required DateTime qualifiedAt,
}) {
  return QualifiedPlay(
    id: id,
    playbackSessionId: sessionId,
    songId: songId,
    artistId: artistId,
    albumId: albumId,
    albumEditionId: 'edition-$albumId',
    qualifiedAt: qualifiedAt,
    listenedDuration: const Duration(seconds: 30),
    trackDuration: const Duration(minutes: 4),
    createdAt: qualifiedAt,
  );
}

PlaybackSession session({
  required String id,
  required String songId,
  required String artistId,
  required String albumId,
  required DateTime startedAt,
  required PlaybackSessionEndReason endReason,
}) {
  final endedAt = startedAt.add(const Duration(minutes: 4));

  return PlaybackSession(
    id: id,
    songId: songId,
    artistId: artistId,
    albumId: albumId,
    albumEditionId: 'edition-$albumId',
    songTitle: songId,
    artistName: artistId,
    albumTitle: albumId,
    albumEditionTitle: 'Standard',
    startedAt: startedAt,
    endedAt: endedAt,
    listenedDuration: const Duration(minutes: 4),
    trackDuration: const Duration(minutes: 4),
    finalPosition: const Duration(minutes: 4),
    endReason: endReason,
    createdAt: startedAt,
    updatedAt: endedAt,
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

class FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  FakeQualifiedPlayRepository({required this.plays});

  final List<QualifiedPlay> plays;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    return plays
        .where((play) {
          final qualifiedAt = play.qualifiedAt.toUtc();

          if (qualifiedAtOrAfter != null &&
              qualifiedAt.isBefore(qualifiedAtOrAfter.toUtc())) {
            return false;
          }

          if (qualifiedBefore != null &&
              !qualifiedAt.isBefore(qualifiedBefore.toUtc())) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }

  @override
  Future<void> create(QualifiedPlay play) {
    throw UnimplementedError();
  }

  @override
  Future<void> save(QualifiedPlay play) {
    throw UnimplementedError();
  }

  @override
  Future<QualifiedPlay?> getById(String id) async {
    for (final play in plays) {
      if (play.id == id) {
        return play;
      }
    }

    return null;
  }

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(
    String playbackSessionId,
  ) async {
    for (final play in plays) {
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

    return plays
        .where((play) => ids.contains(play.playbackSessionId))
        .toList(growable: false);
  }
}

class FakePlaybackSessionRepository implements PlaybackSessionRepository {
  FakePlaybackSessionRepository({required this.sessions});

  final List<PlaybackSession> sessions;

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    return sessions
        .where((session) {
          final startedAt = session.startedAt.toUtc();

          if (startedAtOrAfter != null &&
              startedAt.isBefore(startedAtOrAfter.toUtc())) {
            return false;
          }

          if (startedBefore != null &&
              !startedAt.isBefore(startedBefore.toUtc())) {
            return false;
          }

          return true;
        })
        .toList(growable: false);
  }

  @override
  Future<PlaybackSession?> getById(String id) async {
    for (final session in sessions) {
      if (session.id == id) {
        return session;
      }
    }

    return null;
  }

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) async {
    final requested = ids.toSet();

    return sessions
        .where((session) => requested.contains(session.id))
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
  Future<List<PlaybackSession>> getOpen() async {
    return sessions
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
    final filtered = await getAll(
      startedAtOrAfter: startedAtOrAfter,
      startedBefore: startedBefore,
    );

    return filtered.take(limit).toList(growable: false);
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
        .where(
          (segment) =>
              segment.startedAt.toUtc().isBefore(startedBefore.toUtc()),
        )
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
  Future<PlaybackListeningSegment?> getById(String id) async {
    for (final segment in segments) {
      if (segment.id == id) {
        return segment;
      }
    }

    return null;
  }

  @override
  Future<PlaybackListeningSegment?> getOpenForSession(
    String playbackSessionId,
  ) async {
    for (final segment in segments) {
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
    return segments
        .where((segment) => segment.playbackSessionId == playbackSessionId)
        .toList(growable: false);
  }
}
