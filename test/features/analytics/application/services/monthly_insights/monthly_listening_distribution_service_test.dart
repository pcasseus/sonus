import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/application/services/monthly_insights/monthly_listening_distribution_service.dart';
import 'package:sonus_next/features/analytics/domain/entities/playback_listening_segment.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_listening_segment_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';

void main() {
  group('MonthlyListeningDistributionService', () {
    test('builds every calendar day and all 24 hours', () async {
      final service = MonthlyListeningDistributionService(
        qualifiedPlays: FakeQualifiedPlayRepository(),
        listeningSegments: FakeListeningSegmentRepository(),
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(result.days, hasLength(31));
      expect(result.days.first.localDate, DateTime(2026, 10, 1));
      expect(result.days.last.localDate, DateTime(2026, 10, 31));

      expect(result.hours, hasLength(24));
      expect(result.hours.first.hour, 0);
      expect(result.hours.last.hour, 23);
    });

    test('counts qualified streams by local day and local hour', () async {
      final firstLocal = DateTime(2026, 10, 4, 9, 15);
      final secondLocal = DateTime(2026, 10, 4, 9, 45);
      final thirdLocal = DateTime(2026, 10, 5, 21, 30);

      final service = MonthlyListeningDistributionService(
        qualifiedPlays: FakeQualifiedPlayRepository(
          plays: [
            play(id: 'play-1', qualifiedAt: firstLocal.toUtc()),
            play(id: 'play-2', qualifiedAt: secondLocal.toUtc()),
            play(id: 'play-3', qualifiedAt: thirdLocal.toUtc()),
          ],
        ),
        listeningSegments: FakeListeningSegmentRepository(),
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      final octoberFourth = result.days.singleWhere(
        (day) => day.localDate == DateTime(2026, 10, 4),
      );

      final octoberFifth = result.days.singleWhere(
        (day) => day.localDate == DateTime(2026, 10, 5),
      );

      expect(octoberFourth.streams, 2);
      expect(octoberFifth.streams, 1);

      expect(result.hours[9].streams, 2);
      expect(result.hours[21].streams, 1);
    });

    test('splits audible listening across local hour boundaries', () async {
      final startLocal = DateTime(2026, 10, 8, 10, 50);

      final service = MonthlyListeningDistributionService(
        qualifiedPlays: FakeQualifiedPlayRepository(),
        listeningSegments: FakeListeningSegmentRepository(
          segments: [
            segment(
              id: 'segment-1',
              startedAt: startLocal.toUtc(),
              duration: const Duration(minutes: 30),
            ),
          ],
        ),
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(result.hours[10].listeningDuration, const Duration(minutes: 10));

      expect(result.hours[11].listeningDuration, const Duration(minutes: 20));

      final day = result.days.singleWhere(
        (day) => day.localDate == DateTime(2026, 10, 8),
      );

      expect(day.listeningDuration, const Duration(minutes: 30));
    });

    test('splits audible listening across local midnight', () async {
      final startLocal = DateTime(2026, 10, 8, 23, 50);

      final service = MonthlyListeningDistributionService(
        qualifiedPlays: FakeQualifiedPlayRepository(),
        listeningSegments: FakeListeningSegmentRepository(
          segments: [
            segment(
              id: 'segment-midnight',
              startedAt: startLocal.toUtc(),
              duration: const Duration(minutes: 30),
            ),
          ],
        ),
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      final octoberEighth = result.days.singleWhere(
        (day) => day.localDate == DateTime(2026, 10, 8),
      );

      final octoberNinth = result.days.singleWhere(
        (day) => day.localDate == DateTime(2026, 10, 9),
      );

      expect(octoberEighth.listeningDuration, const Duration(minutes: 10));

      expect(octoberNinth.listeningDuration, const Duration(minutes: 20));

      expect(result.hours[23].listeningDuration, const Duration(minutes: 10));

      expect(result.hours[0].listeningDuration, const Duration(minutes: 20));
    });

    test('clips audible listening to selected month', () async {
      final startLocal = DateTime(2026, 9, 30, 23, 50);

      final service = MonthlyListeningDistributionService(
        qualifiedPlays: FakeQualifiedPlayRepository(),
        listeningSegments: FakeListeningSegmentRepository(
          segments: [
            segment(
              id: 'segment-boundary',
              startedAt: startLocal.toUtc(),
              duration: const Duration(minutes: 30),
            ),
          ],
        ),
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      final octoberFirst = result.days.first;

      expect(octoberFirst.listeningDuration, const Duration(minutes: 20));

      expect(result.hours[0].listeningDuration, const Duration(minutes: 20));
    });

    test('ignores listening completely outside selected month', () async {
      final service = MonthlyListeningDistributionService(
        qualifiedPlays: FakeQualifiedPlayRepository(),
        listeningSegments: FakeListeningSegmentRepository(
          segments: [
            segment(
              id: 'segment-september',
              startedAt: DateTime.utc(2026, 9, 15, 12),
              duration: const Duration(minutes: 10),
            ),
          ],
        ),
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(
        result.days.every((day) => day.listeningDuration == Duration.zero),
        isTrue,
      );

      expect(
        result.hours.every((hour) => hour.listeningDuration == Duration.zero),
        isTrue,
      );
    });

    test('uses listened duration as endpoint for open segment', () async {
      final startLocal = DateTime(2026, 10, 8, 14, 0);

      final service = MonthlyListeningDistributionService(
        qualifiedPlays: FakeQualifiedPlayRepository(),
        listeningSegments: FakeListeningSegmentRepository(
          segments: [
            PlaybackListeningSegment(
              id: 'segment-open',
              playbackSessionId: 'session-1',
              startedAt: startLocal.toUtc(),
              endedAt: null,
              listenedDuration: const Duration(seconds: 45),
              createdAt: startLocal.toUtc(),
              updatedAt: startLocal.add(const Duration(seconds: 45)).toUtc(),
            ),
          ],
        ),
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(result.hours[14].listeningDuration, const Duration(seconds: 45));
    });

    test('busiest day prefers stream count then earliest day', () async {
      final dayOneLocal = DateTime(2026, 10, 10, 8);
      final dayTwoLocal = DateTime(2026, 10, 11, 8);

      final service = MonthlyListeningDistributionService(
        qualifiedPlays: FakeQualifiedPlayRepository(
          plays: [
            play(id: 'play-1', qualifiedAt: dayOneLocal.toUtc()),
            play(
              id: 'play-2',
              qualifiedAt: dayOneLocal.add(const Duration(minutes: 5)).toUtc(),
            ),
            play(id: 'play-3', qualifiedAt: dayTwoLocal.toUtc()),
            play(
              id: 'play-4',
              qualifiedAt: dayTwoLocal.add(const Duration(minutes: 5)).toUtc(),
            ),
          ],
        ),
        listeningSegments: FakeListeningSegmentRepository(
          segments: [
            segment(
              id: 'segment-day-1',
              startedAt: dayOneLocal.toUtc(),
              duration: const Duration(minutes: 20),
            ),
            segment(
              id: 'segment-day-2',
              startedAt: dayTwoLocal.toUtc(),
              duration: const Duration(minutes: 40),
            ),
          ],
        ),
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(result.busiestDay?.localDate, DateTime(2026, 10, 10));

      expect(result.busiestDay?.streams, 2);

      expect(result.busiestDay?.listeningDuration, const Duration(minutes: 20));
    });

    test('most active hour prefers listening duration then streams', () async {
      final tenLocal = DateTime(2026, 10, 10, 10);
      final elevenLocal = DateTime(2026, 10, 10, 11);

      final service = MonthlyListeningDistributionService(
        qualifiedPlays: FakeQualifiedPlayRepository(
          plays: [
            play(id: 'play-10', qualifiedAt: tenLocal.toUtc()),
            play(id: 'play-11-a', qualifiedAt: elevenLocal.toUtc()),
            play(
              id: 'play-11-b',
              qualifiedAt: elevenLocal.add(const Duration(minutes: 5)).toUtc(),
            ),
          ],
        ),
        listeningSegments: FakeListeningSegmentRepository(
          segments: [
            segment(
              id: 'segment-10',
              startedAt: tenLocal.toUtc(),
              duration: const Duration(minutes: 45),
            ),
            segment(
              id: 'segment-11',
              startedAt: elevenLocal.toUtc(),
              duration: const Duration(minutes: 20),
            ),
          ],
        ),
      );

      final result = await service.load(referenceLocal: DateTime(2026, 10, 15));

      expect(result.mostActiveHour?.hour, 10);

      expect(
        result.mostActiveHour?.listeningDuration,
        const Duration(minutes: 45),
      );
    });
  });
}

QualifiedPlay play({required String id, required DateTime qualifiedAt}) {
  return QualifiedPlay(
    id: id,
    playbackSessionId: 'session-$id',
    songId: 'song-$id',
    artistId: 'artist-1',
    albumId: 'album-1',
    albumEditionId: 'edition-1',
    qualifiedAt: qualifiedAt,
    listenedDuration: const Duration(seconds: 30),
    trackDuration: const Duration(minutes: 4),
    createdAt: qualifiedAt,
  );
}

PlaybackListeningSegment segment({
  required String id,
  required DateTime startedAt,
  required Duration duration,
}) {
  return PlaybackListeningSegment(
    id: id,
    playbackSessionId: 'session-$id',
    startedAt: startedAt,
    endedAt: startedAt.add(duration),
    listenedDuration: duration,
    createdAt: startedAt,
    updatedAt: startedAt.add(duration),
  );
}

class FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  FakeQualifiedPlayRepository({this.plays = const []});

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

class FakeListeningSegmentRepository
    implements PlaybackListeningSegmentRepository {
  FakeListeningSegmentRepository({this.segments = const []});

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
