import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/domain/models/listening_history_cursor.dart';

import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/services/analytics_behavior_metrics_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';

class FakePlaybackSessionRepository implements PlaybackSessionRepository {
  FakePlaybackSessionRepository([List<PlaybackSession> sessions = const []])
    : _sessions = List<PlaybackSession>.from(sessions);

  final List<PlaybackSession> _sessions;

  @override
  Future<void> create(PlaybackSession session) async {
    _sessions.add(session);
  }

  @override
  Future<void> save(PlaybackSession session) async {
    final index = _sessions.indexWhere((item) => item.id == session.id);

    if (index < 0) {
      throw StateError('Playback session not found: ${session.id}');
    }

    _sessions[index] = session;
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
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) {
    throw UnimplementedError();
  }

  @override
  Future<List<PlaybackSession>> getOpen() async {
    return _sessions.where((session) => !session.isEnded).toList();
  }

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) async {
    final result =
        _sessions.where((session) {
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
    return _sessions.where((session) {
      final startedAt = session.startedAt.toUtc();

      if (startedAtOrAfter != null &&
          startedAt.isBefore(startedAtOrAfter.toUtc())) {
        return false;
      }

      if (startedBefore != null && !startedAt.isBefore(startedBefore.toUtc())) {
        return false;
      }

      return true;
    }).toList();
  }
}

class FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  FakeQualifiedPlayRepository([List<QualifiedPlay> plays = const []])
    : _plays = List<QualifiedPlay>.from(plays);

  final List<QualifiedPlay> _plays;

  @override
  Future<void> create(QualifiedPlay play) async {
    _plays.add(play);
  }

  @override
  Future<void> save(QualifiedPlay play) async {
    final index = _plays.indexWhere((value) => value.id == play.id);

    if (index == -1) {
      throw StateError('Qualified play not found: ${play.id}');
    }

    _plays[index] = play;
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
    return _plays.where((play) {
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
    }).toList();
  }
}

PlaybackSession session({
  required String id,
  required DateTime startedAt,
  PlaybackSessionEndReason? endReason,
  bool ended = true,
}) {
  return PlaybackSession(
    id: id,
    songId: 'song_$id',
    artistId: 'artist_$id',
    albumId: 'album_$id',
    albumEditionId: 'edition_$id',
    songTitle: 'Song $id',
    artistName: 'Artist $id',
    albumTitle: 'Album $id',
    albumEditionTitle: 'Edition $id',
    startedAt: startedAt,
    endedAt: ended ? startedAt.add(const Duration(minutes: 2)) : null,
    listenedDuration: const Duration(minutes: 1),
    trackDuration: const Duration(minutes: 3),
    finalPosition: const Duration(minutes: 1),
    endReason: ended ? endReason : null,
    createdAt: startedAt,
    updatedAt: startedAt,
  );
}

QualifiedPlay play({required String id, required DateTime qualifiedAt}) {
  return QualifiedPlay(
    id: id,
    playbackSessionId: 'session_$id',
    songId: 'song_$id',
    artistId: 'artist_$id',
    albumId: 'album_$id',
    albumEditionId: 'edition_$id',
    qualifiedAt: qualifiedAt,
    listenedDuration: const Duration(seconds: 30),
    trackDuration: const Duration(minutes: 3),
    createdAt: qualifiedAt,
  );
}

void main() {
  group('AnalyticsBehaviorMetricsService', () {
    test('returns zero metrics when there is no activity', () async {
      final service = AnalyticsBehaviorMetricsService(
        playbackSessions: FakePlaybackSessionRepository(),
        qualifiedPlays: FakeQualifiedPlayRepository(),
      );

      final metrics = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25),
      );

      expect(metrics.sessionCount, 0);
      expect(metrics.endedSessionCount, 0);
      expect(metrics.completedSessionCount, 0);
      expect(metrics.skippedSessionCount, 0);
      expect(metrics.completionRate, 0);
      expect(metrics.skipRate, 0);
      expect(metrics.firstSessionStartedAt, isNull);
      expect(metrics.lastSessionStartedAt, isNull);
      expect(metrics.activeQualifiedDayCount, 0);
      expect(metrics.averageQualifiedStreamsPerActiveDay, 0);
      expect(metrics.averageQualifiedStreamsPerCalendarDay, 0);
      expect(metrics.peakDay, isNull);
    });

    test('counts every session end reason independently', () async {
      final sessions = [
        session(
          id: 'completed',
          startedAt: DateTime(2026, 9, 25, 8).toUtc(),
          endReason: PlaybackSessionEndReason.completed,
        ),
        session(
          id: 'skipped',
          startedAt: DateTime(2026, 9, 25, 9).toUtc(),
          endReason: PlaybackSessionEndReason.skipped,
        ),
        session(
          id: 'stopped',
          startedAt: DateTime(2026, 9, 25, 10).toUtc(),
          endReason: PlaybackSessionEndReason.stopped,
        ),
        session(
          id: 'replaced',
          startedAt: DateTime(2026, 9, 25, 11).toUtc(),
          endReason: PlaybackSessionEndReason.replaced,
        ),
        session(
          id: 'interrupted',
          startedAt: DateTime(2026, 9, 25, 12).toUtc(),
          endReason: PlaybackSessionEndReason.interrupted,
        ),
        session(
          id: 'failed',
          startedAt: DateTime(2026, 9, 25, 13).toUtc(),
          endReason: PlaybackSessionEndReason.failed,
        ),
      ];

      final service = AnalyticsBehaviorMetricsService(
        playbackSessions: FakePlaybackSessionRepository(sessions),
        qualifiedPlays: FakeQualifiedPlayRepository(),
      );

      final metrics = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25),
      );

      expect(metrics.sessionCount, 6);
      expect(metrics.endedSessionCount, 6);
      expect(metrics.completedSessionCount, 1);
      expect(metrics.skippedSessionCount, 1);
      expect(metrics.stoppedSessionCount, 1);
      expect(metrics.replacedSessionCount, 1);
      expect(metrics.interruptedSessionCount, 1);
      expect(metrics.failedSessionCount, 1);
    });

    test('completion and skip rates use ended sessions only', () async {
      final sessions = [
        session(
          id: 'completed_1',
          startedAt: DateTime(2026, 9, 25, 8).toUtc(),
          endReason: PlaybackSessionEndReason.completed,
        ),
        session(
          id: 'completed_2',
          startedAt: DateTime(2026, 9, 25, 9).toUtc(),
          endReason: PlaybackSessionEndReason.completed,
        ),
        session(
          id: 'skipped',
          startedAt: DateTime(2026, 9, 25, 10).toUtc(),
          endReason: PlaybackSessionEndReason.skipped,
        ),
        session(
          id: 'active',
          startedAt: DateTime(2026, 9, 25, 11).toUtc(),
          ended: false,
        ),
      ];

      final service = AnalyticsBehaviorMetricsService(
        playbackSessions: FakePlaybackSessionRepository(sessions),
        qualifiedPlays: FakeQualifiedPlayRepository(),
      );

      final metrics = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25),
      );

      expect(metrics.sessionCount, 4);
      expect(metrics.endedSessionCount, 3);
      expect(metrics.completionRate, closeTo(2 / 3, 0.000001));
      expect(metrics.skipRate, closeTo(1 / 3, 0.000001));
    });

    test('tracks first and last session activity', () async {
      final service = AnalyticsBehaviorMetricsService(
        playbackSessions: FakePlaybackSessionRepository([
          session(
            id: 'middle',
            startedAt: DateTime.utc(2026, 9, 25, 12),
            endReason: PlaybackSessionEndReason.completed,
          ),
          session(
            id: 'latest',
            startedAt: DateTime.utc(2026, 9, 25, 20),
            endReason: PlaybackSessionEndReason.completed,
          ),
          session(
            id: 'earliest',
            startedAt: DateTime.utc(2026, 9, 25, 8),
            endReason: PlaybackSessionEndReason.skipped,
          ),
        ]),
        qualifiedPlays: FakeQualifiedPlayRepository(),
      );

      final metrics = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25),
      );

      expect(metrics.firstSessionStartedAt, DateTime.utc(2026, 9, 25, 8));

      expect(metrics.lastSessionStartedAt, DateTime.utc(2026, 9, 25, 20));
    });

    test(
      'counts active qualified days and average streams per active day',
      () async {
        final dayOne = DateTime(2026, 9, 21);
        final dayTwo = DateTime(2026, 9, 23);

        final service = AnalyticsBehaviorMetricsService(
          playbackSessions: FakePlaybackSessionRepository(),
          qualifiedPlays: FakeQualifiedPlayRepository([
            play(
              id: '1',
              qualifiedAt: DateTime(
                dayOne.year,
                dayOne.month,
                dayOne.day,
                8,
              ).toUtc(),
            ),
            play(
              id: '2',
              qualifiedAt: DateTime(
                dayOne.year,
                dayOne.month,
                dayOne.day,
                12,
              ).toUtc(),
            ),
            play(
              id: '3',
              qualifiedAt: DateTime(
                dayTwo.year,
                dayTwo.month,
                dayTwo.day,
                9,
              ).toUtc(),
            ),
          ]),
        );

        final metrics = await service.load(
          period: AnalyticsPeriod.week,
          referenceLocal: DateTime(2026, 9, 23),
        );

        expect(metrics.activeQualifiedDayCount, 2);
        expect(metrics.averageQualifiedStreamsPerActiveDay, 1.5);
      },
    );

    test('identifies peak qualified listening day', () async {
      final peakDate = DateTime(2026, 9, 23);

      final service = AnalyticsBehaviorMetricsService(
        playbackSessions: FakePlaybackSessionRepository(),
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(id: '1', qualifiedAt: DateTime(2026, 9, 21, 8).toUtc()),
          play(id: '2', qualifiedAt: DateTime(2026, 9, 23, 8).toUtc()),
          play(id: '3', qualifiedAt: DateTime(2026, 9, 23, 10).toUtc()),
          play(id: '4', qualifiedAt: DateTime(2026, 9, 23, 12).toUtc()),
        ]),
      );

      final metrics = await service.load(
        period: AnalyticsPeriod.week,
        referenceLocal: DateTime(2026, 9, 23),
      );

      expect(metrics.peakDay, isNotNull);
      expect(metrics.peakDay!.localDate, peakDate);
      expect(metrics.peakDay!.qualifiedStreamCount, 3);
    });

    test('peak-day ties prefer the earlier local calendar day', () async {
      final earlierDate = DateTime(2026, 9, 21);

      final service = AnalyticsBehaviorMetricsService(
        playbackSessions: FakePlaybackSessionRepository(),
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(id: '1', qualifiedAt: DateTime(2026, 9, 21, 8).toUtc()),
          play(id: '2', qualifiedAt: DateTime(2026, 9, 21, 9).toUtc()),
          play(id: '3', qualifiedAt: DateTime(2026, 9, 23, 8).toUtc()),
          play(id: '4', qualifiedAt: DateTime(2026, 9, 23, 9).toUtc()),
        ]),
      );

      final metrics = await service.load(
        period: AnalyticsPeriod.week,
        referenceLocal: DateTime(2026, 9, 23),
      );

      expect(metrics.peakDay!.localDate, earlierDate);
      expect(metrics.peakDay!.qualifiedStreamCount, 2);
    });

    test(
      'period filtering applies independently to sessions and plays',
      () async {
        final service = AnalyticsBehaviorMetricsService(
          playbackSessions: FakePlaybackSessionRepository([
            session(
              id: 'inside',
              startedAt: DateTime(2026, 9, 25, 12).toUtc(),
              endReason: PlaybackSessionEndReason.completed,
            ),
            session(
              id: 'outside',
              startedAt: DateTime(2026, 9, 26).toUtc(),
              endReason: PlaybackSessionEndReason.completed,
            ),
          ]),
          qualifiedPlays: FakeQualifiedPlayRepository([
            play(id: 'inside', qualifiedAt: DateTime(2026, 9, 25, 12).toUtc()),
            play(id: 'outside', qualifiedAt: DateTime(2026, 9, 26).toUtc()),
          ]),
        );

        final metrics = await service.load(
          period: AnalyticsPeriod.day,
          referenceLocal: DateTime(2026, 9, 25),
        );

        expect(metrics.sessionCount, 1);
        expect(metrics.completedSessionCount, 1);
        expect(metrics.activeQualifiedDayCount, 1);
        expect(metrics.averageQualifiedStreamsPerActiveDay, 1);
      },
    );

    test('day calendar average divides by one calendar day', () async {
      final service = AnalyticsBehaviorMetricsService(
        playbackSessions: FakePlaybackSessionRepository(),
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(id: '1', qualifiedAt: DateTime(2026, 9, 25, 8).toUtc()),
          play(id: '2', qualifiedAt: DateTime(2026, 9, 25, 12).toUtc()),
        ]),
      );

      final metrics = await service.load(
        period: AnalyticsPeriod.day,
        referenceLocal: DateTime(2026, 9, 25),
      );

      expect(metrics.averageQualifiedStreamsPerCalendarDay, 2);
    });

    test('week calendar average divides by seven days', () async {
      final service = AnalyticsBehaviorMetricsService(
        playbackSessions: FakePlaybackSessionRepository(),
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(id: '1', qualifiedAt: DateTime(2026, 9, 21, 8).toUtc()),
          play(id: '2', qualifiedAt: DateTime(2026, 9, 21, 12).toUtc()),
          play(id: '3', qualifiedAt: DateTime(2026, 9, 23, 9).toUtc()),
        ]),
      );

      final metrics = await service.load(
        period: AnalyticsPeriod.week,
        referenceLocal: DateTime(2026, 9, 23),
      );

      expect(
        metrics.averageQualifiedStreamsPerCalendarDay,
        closeTo(3 / 7, 0.000001),
      );

      expect(metrics.averageQualifiedStreamsPerActiveDay, 1.5);
    });

    test('month calendar average uses actual month length', () async {
      final service = AnalyticsBehaviorMetricsService(
        playbackSessions: FakePlaybackSessionRepository(),
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(id: '1', qualifiedAt: DateTime(2024, 2, 10, 12).toUtc()),
        ]),
      );

      final metrics = await service.load(
        period: AnalyticsPeriod.month,
        referenceLocal: DateTime(2024, 2, 15),
      );

      expect(
        metrics.averageQualifiedStreamsPerCalendarDay,
        closeTo(1 / 29, 0.000001),
      );
    });

    test('year calendar average respects leap years', () async {
      final service = AnalyticsBehaviorMetricsService(
        playbackSessions: FakePlaybackSessionRepository(),
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(id: '1', qualifiedAt: DateTime(2024, 6, 15, 12).toUtc()),
        ]),
      );

      final metrics = await service.load(
        period: AnalyticsPeriod.year,
        referenceLocal: DateTime(2024, 6, 15),
      );

      expect(
        metrics.averageQualifiedStreamsPerCalendarDay,
        closeTo(1 / 366, 0.000001),
      );
    });

    test(
      'lifetime calendar average uses inclusive span from first play',
      () async {
        final firstLocalDay = DateTime(2020, 1, 1);
        final referenceLocalDay = DateTime(2026, 9, 25);

        final service = AnalyticsBehaviorMetricsService(
          playbackSessions: FakePlaybackSessionRepository(),
          qualifiedPlays: FakeQualifiedPlayRepository([
            play(id: 'old', qualifiedAt: DateTime(2020, 1, 1, 8).toUtc()),
            play(id: 'new', qualifiedAt: DateTime(2026, 9, 25, 8).toUtc()),
          ]),
        );

        final metrics = await service.load(
          period: AnalyticsPeriod.lifetime,
          referenceLocal: referenceLocalDay,
        );

        final inclusiveCalendarDays =
            DateTime.utc(
                  referenceLocalDay.year,
                  referenceLocalDay.month,
                  referenceLocalDay.day,
                )
                .difference(
                  DateTime.utc(
                    firstLocalDay.year,
                    firstLocalDay.month,
                    firstLocalDay.day,
                  ),
                )
                .inDays +
            1;

        expect(
          metrics.averageQualifiedStreamsPerCalendarDay,
          closeTo(2 / inclusiveCalendarDays, 0.000000001),
        );

        expect(metrics.averageQualifiedStreamsPerActiveDay, 1);
      },
    );
    test('lifetime includes activity across all dates', () async {
      final service = AnalyticsBehaviorMetricsService(
        playbackSessions: FakePlaybackSessionRepository([
          session(
            id: 'old',
            startedAt: DateTime.utc(2020, 1, 1),
            endReason: PlaybackSessionEndReason.skipped,
          ),
          session(
            id: 'new',
            startedAt: DateTime.utc(2026, 9, 25),
            endReason: PlaybackSessionEndReason.completed,
          ),
        ]),
        qualifiedPlays: FakeQualifiedPlayRepository([
          play(id: 'old', qualifiedAt: DateTime.utc(2020, 1, 1)),
          play(id: 'new', qualifiedAt: DateTime.utc(2026, 9, 25)),
        ]),
      );

      final metrics = await service.load(
        period: AnalyticsPeriod.lifetime,
        referenceLocal: DateTime(2026, 9, 25),
      );

      expect(metrics.sessionCount, 2);
      expect(metrics.endedSessionCount, 2);
      expect(metrics.completedSessionCount, 1);
      expect(metrics.skippedSessionCount, 1);
      expect(metrics.activeQualifiedDayCount, 2);
      expect(metrics.averageQualifiedStreamsPerActiveDay, 1);
    });
  });
}
