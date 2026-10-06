import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/services/analytics_behavior_metrics_service.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_entity_ranking_service.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_listening_duration_service.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_summary_service.dart';
import 'package:sonus_next/features/analytics/application/services/year_in_sonus/year_in_sonus_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';

void main() {
  group('YearInSonusService', () {
    test(
      'builds annual totals, rankings, monthly leaders, and streak',
      () async {
        final plays = <QualifiedPlay>[
          _play(
            id: 'play_1',
            local: DateTime(2026, 1, 1, 10),
            songId: 'song_a',
            artistId: 'artist_a',
            albumId: 'album_a',
          ),
          _play(
            id: 'play_2',
            local: DateTime(2026, 1, 2, 10),
            songId: 'song_a',
            artistId: 'artist_a',
            albumId: 'album_a',
          ),
          _play(
            id: 'play_3',
            local: DateTime(2026, 1, 3, 10),
            songId: 'song_b',
            artistId: 'artist_b',
            albumId: 'album_b',
          ),
          _play(
            id: 'play_4',
            local: DateTime(2026, 2, 10, 10),
            songId: 'song_b',
            artistId: 'artist_b',
            albumId: 'album_b',
          ),
          _play(
            id: 'play_5',
            local: DateTime(2026, 2, 11, 10),
            songId: 'song_b',
            artistId: 'artist_b',
            albumId: 'album_b',
          ),
        ];

        final sessions = <PlaybackSession>[
          _session(
            id: 'session_1',
            local: DateTime(2026, 1, 1, 10),
            songId: 'song_a',
            artistId: 'artist_a',
            albumId: 'album_a',
            endReason: PlaybackSessionEndReason.completed,
          ),
          _session(
            id: 'session_2',
            local: DateTime(2026, 1, 2, 10),
            songId: 'song_a',
            artistId: 'artist_a',
            albumId: 'album_a',
            endReason: PlaybackSessionEndReason.completed,
          ),
          _session(
            id: 'session_3',
            local: DateTime(2026, 1, 3, 10),
            songId: 'song_b',
            artistId: 'artist_b',
            albumId: 'album_b',
            endReason: PlaybackSessionEndReason.skipped,
          ),
        ];

        final segments = <PlaybackListeningSegment>[
          _segment(
            id: 'segment_1',
            sessionId: 'session_1',
            local: DateTime(2026, 1, 1, 10),
            listenedDuration: const Duration(minutes: 20),
          ),
          _segment(
            id: 'segment_2',
            sessionId: 'session_2',
            local: DateTime(2026, 1, 2, 10),
            listenedDuration: const Duration(minutes: 30),
          ),
        ];

        final service = _service(
          plays: plays,
          sessions: sessions,
          segments: segments,
        );

        final recap = await service.load(year: 2026);

        expect(recap.year, 2026);
        expect(recap.summary.qualifiedStreamCount, 5);
        expect(recap.summary.distinctSongCount, 2);
        expect(recap.summary.distinctArtistCount, 2);
        expect(recap.summary.distinctAlbumCount, 2);

        expect(recap.audibleListeningDuration, const Duration(minutes: 50));

        expect(recap.topTracks.first.entityId, 'song_b');
        expect(recap.topTracks.first.streams, 3);

        expect(recap.topArtists.first.entityId, 'artist_b');
        expect(recap.topArtists.first.streams, 3);

        expect(recap.topAlbums.first.entityId, 'album_b');
        expect(recap.topAlbums.first.streams, 3);

        expect(recap.months, hasLength(12));

        final january = recap.months[0];
        expect(january.streams, 3);
        expect(january.topSongId, 'song_a');
        expect(january.topArtistId, 'artist_a');

        final february = recap.months[1];
        expect(february.streams, 2);
        expect(february.topSongId, 'song_b');
        expect(february.topArtistId, 'artist_b');

        expect(recap.mostActiveMonth?.month.month, DateTime.january);
        expect(recap.longestListeningStreakDays, 3);

        expect(recap.behavior.sessionCount, 3);
        expect(recap.behavior.completedSessionCount, 2);
        expect(recap.behavior.skippedSessionCount, 1);
      },
    );

    test('ignores qualified plays outside the requested year', () async {
      final service = _service(
        plays: [
          _play(
            id: 'play_2025',
            local: DateTime(2025, 12, 31, 23),
            songId: 'old_song',
            artistId: 'old_artist',
            albumId: 'old_album',
          ),
          _play(
            id: 'play_2026',
            local: DateTime(2026, 6, 1, 12),
            songId: 'current_song',
            artistId: 'current_artist',
            albumId: 'current_album',
          ),
          _play(
            id: 'play_2027',
            local: DateTime(2027, 1, 1),
            songId: 'future_song',
            artistId: 'future_artist',
            albumId: 'future_album',
          ),
        ],
      );

      final recap = await service.load(year: 2026);

      expect(recap.summary.qualifiedStreamCount, 1);
      expect(recap.topTrack?.entityId, 'current_song');
      expect(recap.months[5].streams, 1);
      expect(
        recap.months
            .where((month) => month.month.month != DateTime.june)
            .every((month) => month.streams == 0),
        isTrue,
      );
    });

    test(
      'uses deterministic entity id tie break for monthly leaders',
      () async {
        final service = _service(
          plays: [
            _play(
              id: 'play_b',
              local: DateTime(2026, 4, 1, 10),
              songId: 'song_b',
              artistId: 'artist_b',
              albumId: 'album_b',
            ),
            _play(
              id: 'play_a',
              local: DateTime(2026, 4, 2, 10),
              songId: 'song_a',
              artistId: 'artist_a',
              albumId: 'album_a',
            ),
          ],
        );

        final recap = await service.load(year: 2026);
        final april = recap.months[3];

        expect(april.topSongId, 'song_a');
        expect(april.topArtistId, 'artist_a');
      },
    );

    test('caps annual rankings at 25 tracks and 10 artists/albums', () async {
      final plays = List<QualifiedPlay>.generate(30, (index) {
        final suffix = index.toString().padLeft(2, '0');

        return _play(
          id: 'play_$suffix',
          local: DateTime(2026, 7, 1, 12, index),
          songId: 'song_$suffix',
          artistId: 'artist_$suffix',
          albumId: 'album_$suffix',
        );
      });

      final recap = await _service(plays: plays).load(year: 2026);

      expect(recap.topTracks, hasLength(25));
      expect(recap.topArtists, hasLength(10));
      expect(recap.topAlbums, hasLength(10));

      expect(
        recap.topTracks.map((entry) => entry.rank),
        orderedEquals(List<int>.generate(25, (index) => index + 1)),
      );
    });

    test(
      'counts artists and albums first discovered during the selected year',
      () async {
        final service = _service(
          plays: [
            _play(
              id: 'old',
              local: DateTime(2025, 8, 1),
              songId: 'old_song',
              artistId: 'artist_old',
              albumId: 'album_old',
            ),
            _play(
              id: 'new_1',
              local: DateTime(2026, 2, 1),
              songId: 'new_song_1',
              artistId: 'artist_new',
              albumId: 'album_new',
            ),
            _play(
              id: 'new_2',
              local: DateTime(2026, 3, 1),
              songId: 'new_song_2',
              artistId: 'artist_new',
              albumId: 'album_new_2',
            ),
          ],
        );

        final recap = await service.load(year: 2026);

        expect(recap.newArtistIds, ['artist_new']);
        expect(recap.newAlbumIds, ['album_new', 'album_new_2']);
        expect(recap.newArtistCount, 1);
        expect(recap.newAlbumCount, 2);
      },
    );

    test('returns an empty recap for a year with no listening', () async {
      final recap = await _service().load(year: 2026);

      expect(recap.hasListening, isFalse);
      expect(recap.summary.qualifiedStreamCount, 0);
      expect(recap.audibleListeningDuration, Duration.zero);
      expect(recap.topTracks, isEmpty);
      expect(recap.topArtists, isEmpty);
      expect(recap.topAlbums, isEmpty);
      expect(recap.months, hasLength(12));
      expect(recap.months.every((month) => !month.hasListening), isTrue);
      expect(recap.mostActiveMonth, isNull);
      expect(recap.longestListeningStreakDays, 0);
    });

    test('rejects invalid years', () {
      expect(() => _service().load(year: 0), throwsArgumentError);
    });
  });
}

YearInSonusService _service({
  List<QualifiedPlay> plays = const [],
  List<PlaybackSession> sessions = const [],
  List<PlaybackListeningSegment> segments = const [],
}) {
  final qualifiedPlays = _FakeQualifiedPlayRepository(plays);
  final playbackSessions = _FakePlaybackSessionRepository(sessions);
  final listeningSegments = _FakePlaybackListeningSegmentRepository(segments);

  return YearInSonusService(
    summaries: AnalyticsSummaryService(qualifiedPlays: qualifiedPlays),
    listeningDurations: AnalyticsListeningDurationService(
      listeningSegments: listeningSegments,
    ),
    behaviorMetrics: AnalyticsBehaviorMetricsService(
      playbackSessions: playbackSessions,
      qualifiedPlays: qualifiedPlays,
    ),
    rankings: AnalyticsEntityRankingService(qualifiedPlays: qualifiedPlays),
    qualifiedPlays: qualifiedPlays,
  );
}

QualifiedPlay _play({
  required String id,
  required DateTime local,
  required String songId,
  required String artistId,
  required String albumId,
}) {
  final instant = local.toUtc();

  return QualifiedPlay(
    id: id,
    playbackSessionId: 'session_$id',
    songId: songId,
    artistId: artistId,
    albumId: albumId,
    albumEditionId: '${albumId}_edition',
    qualifiedAt: instant,
    listenedDuration: const Duration(seconds: 35),
    trackDuration: const Duration(minutes: 3),
    createdAt: instant,
  );
}

PlaybackSession _session({
  required String id,
  required DateTime local,
  required String songId,
  required String artistId,
  required String albumId,
  required PlaybackSessionEndReason endReason,
}) {
  final startedAt = local.toUtc();
  final endedAt = startedAt.add(const Duration(minutes: 3));

  return PlaybackSession(
    id: id,
    songId: songId,
    artistId: artistId,
    albumId: albumId,
    albumEditionId: '${albumId}_edition',
    songTitle: songId,
    artistName: artistId,
    albumTitle: albumId,
    albumEditionTitle: albumId,
    startedAt: startedAt,
    endedAt: endedAt,
    listenedDuration: const Duration(minutes: 3),
    trackDuration: const Duration(minutes: 3),
    finalPosition: const Duration(minutes: 3),
    endReason: endReason,
    createdAt: startedAt,
    updatedAt: endedAt,
  );
}

PlaybackListeningSegment _segment({
  required String id,
  required String sessionId,
  required DateTime local,
  required Duration listenedDuration,
}) {
  final startedAt = local.toUtc();
  final endedAt = startedAt.add(listenedDuration);

  return PlaybackListeningSegment(
    id: id,
    playbackSessionId: sessionId,
    startedAt: startedAt,
    endedAt: endedAt,
    listenedDuration: listenedDuration,
    createdAt: startedAt,
    updatedAt: endedAt,
  );
}

class _FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  _FakeQualifiedPlayRepository(Iterable<QualifiedPlay> plays)
    : _plays = List<QualifiedPlay>.from(plays);

  final List<QualifiedPlay> _plays;

  @override
  Future<void> create(QualifiedPlay play) async {
    _plays.add(play);
  }

  @override
  Future<void> save(QualifiedPlay play) async {
    final index = _plays.indexWhere((candidate) => candidate.id == play.id);

    if (index == -1) {
      _plays.add(play);
    } else {
      _plays[index] = play;
    }
  }

  @override
  Future<QualifiedPlay?> getById(String id) async {
    for (final play in _plays) {
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
    for (final play in _plays) {
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

    return _plays
        .where((play) => ids.contains(play.playbackSessionId))
        .toList(growable: false);
  }

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    return _plays
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
}

class _FakePlaybackSessionRepository implements PlaybackSessionRepository {
  _FakePlaybackSessionRepository(Iterable<PlaybackSession> sessions)
    : _sessions = List<PlaybackSession>.from(sessions);

  final List<PlaybackSession> _sessions;

  @override
  Future<void> create(PlaybackSession session) async {
    _sessions.add(session);
  }

  @override
  Future<void> save(PlaybackSession session) async {
    final index = _sessions.indexWhere(
      (candidate) => candidate.id == session.id,
    );

    if (index == -1) {
      _sessions.add(session);
    } else {
      _sessions[index] = session;
    }
  }

  @override
  Future<PlaybackSession?> getById(String id) async {
    for (final session in _sessions) {
      if (session.id == id) {
        return session;
      }
    }

    return null;
  }

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) async {
    final idSet = ids.toSet();

    return _sessions
        .where((session) => idSet.contains(session.id))
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getOpen() async {
    return _sessions
        .where((session) => !session.isEnded)
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    return _sessions
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
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) async {
    final sessions = await getAll(
      startedAtOrAfter: startedAtOrAfter,
      startedBefore: startedBefore,
    );

    return sessions.take(limit).toList(growable: false);
  }
}

class _FakePlaybackListeningSegmentRepository
    implements PlaybackListeningSegmentRepository {
  _FakePlaybackListeningSegmentRepository(
    Iterable<PlaybackListeningSegment> segments,
  ) : _segments = List<PlaybackListeningSegment>.from(segments);

  final List<PlaybackListeningSegment> _segments;

  @override
  Future<void> create(PlaybackListeningSegment segment) async {
    _segments.add(segment);
  }

  @override
  Future<void> save(PlaybackListeningSegment segment) async {
    final index = _segments.indexWhere(
      (candidate) => candidate.id == segment.id,
    );

    if (index == -1) {
      _segments.add(segment);
    } else {
      _segments[index] = segment;
    }
  }

  @override
  Future<PlaybackListeningSegment?> getById(String id) async {
    for (final segment in _segments) {
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
    for (final segment in _segments) {
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
    return _segments
        .where((segment) => segment.playbackSessionId == playbackSessionId)
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackListeningSegment>> getAll({
    DateTime? startedBefore,
  }) async {
    return _segments
        .where((segment) {
          if (startedBefore == null) {
            return true;
          }

          return segment.startedAt.toUtc().isBefore(startedBefore.toUtc());
        })
        .toList(growable: false);
  }
}
