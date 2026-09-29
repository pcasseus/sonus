import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_lifetime_stream_service.dart';

void main() {
  QualifiedPlay play({
    required String id,
    required String songId,
    required String albumId,
    required DateTime qualifiedAt,
  }) {
    return QualifiedPlay(
      id: id,
      playbackSessionId: 'session-$id',
      songId: songId,
      artistId: 'artist-$albumId',
      albumId: albumId,
      albumEditionId: 'edition-$albumId',
      qualifiedAt: qualifiedAt,
      listenedDuration: const Duration(seconds: 30),
      trackDuration: const Duration(minutes: 3),
      createdAt: qualifiedAt,
    );
  }

  ChartSnapshot finalized({
    ChartType chartType = ChartType.songs,
    DateTime? start,
  }) {
    final resolvedStart = start ?? DateTime.utc(2026, 9, 27);

    return ChartSnapshot(
      id: 'chart-${chartType.name}',
      chartType: chartType,
      weekStartUtc: resolvedStart,
      weekEndUtc: resolvedStart.add(const Duration(days: 7)),
      finalizedAt: resolvedStart.add(const Duration(days: 7)),
      entries: const [],
    );
  }

  group('ChartMomentLifetimeStreamService', () {
    test('counts lifetime song streams through finalized week end', () async {
      final repository = _FakeQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 8, 1),
        ),
        play(
          id: '2',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28),
        ),
        play(
          id: '3',
          songId: 'song-b',
          albumId: 'album-b',
          qualifiedAt: DateTime.utc(2026, 9, 29),
        ),
      ]);

      final service = ChartMomentLifetimeStreamService(
        qualifiedPlays: repository,
      );

      final totals = await service.load(snapshot: finalized());

      expect(totals['song-a'], 2);
      expect(totals['song-b'], 1);
    });

    test('album totals combine qualified plays from different songs', () async {
      final repository = _FakeQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'song-a1',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 28),
        ),
        play(
          id: '2',
          songId: 'song-a2',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 29),
        ),
        play(
          id: '3',
          songId: 'song-b1',
          albumId: 'album-b',
          qualifiedAt: DateTime.utc(2026, 9, 30),
        ),
      ]);

      final service = ChartMomentLifetimeStreamService(
        qualifiedPlays: repository,
      );

      final totals = await service.load(
        snapshot: finalized(chartType: ChartType.albums),
      );

      expect(totals['album-a'], 2);
      expect(totals['album-b'], 1);
    });

    test(
      'future qualified plays are excluded from historical rebuild',
      () async {
        final repository = _FakeQualifiedPlayRepository([
          play(
            id: 'historical',
            songId: 'song-a',
            albumId: 'album-a',
            qualifiedAt: DateTime.utc(2026, 9, 30),
          ),
          play(
            id: 'future',
            songId: 'song-a',
            albumId: 'album-a',
            qualifiedAt: DateTime.utc(2026, 10, 5),
          ),
        ]);

        final service = ChartMomentLifetimeStreamService(
          qualifiedPlays: repository,
        );

        final totals = await service.load(snapshot: finalized());

        expect(totals['song-a'], 1);
      },
    );

    test('play exactly at week end is excluded', () async {
      final repository = _FakeQualifiedPlayRepository([
        play(
          id: 'inside',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 10, 3, 23, 59, 59),
        ),
        play(
          id: 'boundary',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 10, 4),
        ),
      ]);

      final service = ChartMomentLifetimeStreamService(
        qualifiedPlays: repository,
      );

      final totals = await service.load(snapshot: finalized());

      expect(totals['song-a'], 1);
    });

    test('different song ids remain independent', () async {
      final repository = _FakeQualifiedPlayRepository([
        play(
          id: '1',
          songId: 'song-a',
          albumId: 'album-shared',
          qualifiedAt: DateTime.utc(2026, 9, 28),
        ),
        play(
          id: '2',
          songId: 'song-b',
          albumId: 'album-shared',
          qualifiedAt: DateTime.utc(2026, 9, 29),
        ),
      ]);

      final service = ChartMomentLifetimeStreamService(
        qualifiedPlays: repository,
      );

      final totals = await service.load(snapshot: finalized());

      expect(totals['song-a'], 1);
      expect(totals['song-b'], 1);
    });

    test('empty qualified-play history returns empty totals', () async {
      final service = ChartMomentLifetimeStreamService(
        qualifiedPlays: _FakeQualifiedPlayRepository(),
      );

      final totals = await service.load(snapshot: finalized());

      expect(totals, isEmpty);
    });

    test('historical week uses its own week-end cutoff', () async {
      final repository = _FakeQualifiedPlayRepository([
        play(
          id: 'old',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 22),
        ),
        play(
          id: 'later',
          songId: 'song-a',
          albumId: 'album-a',
          qualifiedAt: DateTime.utc(2026, 9, 30),
        ),
      ]);

      final service = ChartMomentLifetimeStreamService(
        qualifiedPlays: repository,
      );

      final totals = await service.load(
        snapshot: finalized(start: DateTime.utc(2026, 9, 20)),
      );

      expect(totals['song-a'], 1);
    });

    test(
      'loadBefore can derive previous and current lifetime states',
      () async {
        final repository = _FakeQualifiedPlayRepository([
          play(
            id: 'old-1',
            songId: 'song-a',
            albumId: 'album-a',
            qualifiedAt: DateTime.utc(2026, 9, 1),
          ),
          play(
            id: 'old-2',
            songId: 'song-a',
            albumId: 'album-a',
            qualifiedAt: DateTime.utc(2026, 9, 20),
          ),
          play(
            id: 'current-week',
            songId: 'song-a',
            albumId: 'album-a',
            qualifiedAt: DateTime.utc(2026, 9, 30),
          ),
        ]);

        final service = ChartMomentLifetimeStreamService(
          qualifiedPlays: repository,
        );

        final previous = await service.loadBefore(
          chartType: ChartType.songs,
          qualifiedBeforeUtc: DateTime.utc(2026, 9, 27),
        );

        final current = await service.loadBefore(
          chartType: ChartType.songs,
          qualifiedBeforeUtc: DateTime.utc(2026, 10, 4),
        );

        expect(previous['song-a'], 2);
        expect(current['song-a'], 3);
      },
    );
    test('rejects live chart snapshots', () async {
      final service = ChartMomentLifetimeStreamService(
        qualifiedPlays: _FakeQualifiedPlayRepository(),
      );

      final live = ChartSnapshot(
        id: 'live',
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 27),
        weekEndUtc: DateTime.utc(2026, 10, 4),
        entries: const [],
      );

      await expectLater(service.load(snapshot: live), throwsArgumentError);
    });

    test('returned totals cannot be mutated', () async {
      final service = ChartMomentLifetimeStreamService(
        qualifiedPlays: _FakeQualifiedPlayRepository([
          play(
            id: '1',
            songId: 'song-a',
            albumId: 'album-a',
            qualifiedAt: DateTime.utc(2026, 9, 28),
          ),
        ]),
      );

      final totals = await service.load(snapshot: finalized());

      expect(() => totals['song-a'] = 99, throwsUnsupportedError);
    });
  });
}

class _FakeQualifiedPlayRepository implements QualifiedPlayRepository {
  _FakeQualifiedPlayRepository([Iterable<QualifiedPlay> plays = const []])
    : _plays = List<QualifiedPlay>.from(plays);

  final List<QualifiedPlay> _plays;

  @override
  Future<void> create(QualifiedPlay play) async {
    _plays.add(play);
  }

  @override
  Future<void> save(QualifiedPlay play) async {
    final index = _plays.indexWhere((candidate) => candidate.id == play.id);

    if (index < 0) {
      _plays.add(play);
      return;
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
