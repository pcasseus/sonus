// App Update 1.2, REF-19: artist dominance on the weekly Sonus Hot 100,
// stored as the existing "N songs in the Top T" Moment type.
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_artist_dominance.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';

void main() {
  const detector = ChartMomentArtistDominanceDetector();
  final createdAt = DateTime.utc(2026, 11, 16, 1);
  final weekStart = DateTime.utc(2026, 11, 8);
  final weekEnd = DateTime.utc(2026, 11, 15);
  final previousStart = DateTime.utc(2026, 11, 1);

  ChartEntry entry(String songId, String artistId, int rank) => ChartEntry(
    entity: ChartEntitySnapshot(
      entityId: songId,
      title: 'Song $songId',
      artistId: artistId,
      artistName: 'Name $artistId',
    ),
    rank: rank,
    qualifiedStreamCount: 300 - rank,
    lastQualifiedAt: weekEnd.subtract(const Duration(hours: 1)),
    peakRank: rank,
    peakAchievedAt: weekEnd.subtract(const Duration(hours: 1)),
    weeksOnChart: 1,
    movement: ChartMovement.newEntry,
  );

  /// A 200-place week: [nova] holds [ranks]; every other place belongs to
  /// an artist of its own, so nobody else dominates.
  ChartSnapshot week(
    Iterable<int> ranks, {
    DateTime? start,
    String id = 'week',
    List<ChartEntry> extra = const [],
    ChartType chartType = ChartType.songs,
  }) {
    final mine = ranks.toSet();
    final from = start ?? weekStart;
    return ChartSnapshot(
      id: id,
      chartType: chartType,
      weekStartUtc: from,
      weekEndUtc: from.add(const Duration(days: 7)),
      finalizedAt: from.add(const Duration(days: 7)),
      entries: [
        for (var rank = 1; rank <= 200; rank++)
          if (mine.contains(rank))
            entry('nova-$rank', 'nova', rank)
          else
            entry('other-$rank', 'other-$rank', rank),
        ...extra,
      ],
    );
  }

  ChartSnapshot previousWeek(Iterable<int> ranks) =>
      week(ranks, start: previousStart, id: 'previous');

  List<(ArtistDominanceKind, int, int, int)> facts(
    ChartSnapshot snapshot, {
    List<ChartSnapshot> history = const [],
  }) => [
    for (final event in detector.detect(
      snapshot: snapshot,
      history: history,
      createdAt: createdAt,
    ))
      if (ArtistDominance.of(event) case final fact?)
        (fact.kind, fact.tier, event.threshold!, event.milestoneValue!),
  ];

  List<int> range(int from, int to) => [for (var r = from; r <= to; r++) r];

  group('sweeps', () {
    test('#1–3, #1–5 and #1–10: only the highest sweep, and never again '
        'as a count of the same songs', () {
      expect(facts(week(range(1, 3))), [(ArtistDominanceKind.sweep, 3, 3, 3)]);
      expect(facts(week(range(1, 5))), [(ArtistDominanceKind.sweep, 5, 5, 5)]);
      expect(facts(week(range(1, 10))), [
        (ArtistDominanceKind.sweep, 10, 10, 10),
      ]);
    });

    test('a sweep plus more songs further down is two facts', () {
      expect(facts(week([1, 2, 3, 7, 9, 40])), [
        (ArtistDominanceKind.sweep, 3, 3, 3),
        (ArtistDominanceKind.top10, 5, 10, 5),
        (ArtistDominanceKind.hot100, 5, 100, 6),
      ]);
    });

    test('a gap is not a sweep', () {
      expect(
        facts(week([1, 2, 4])).where((f) => f.$1 == ArtistDominanceKind.sweep),
        isEmpty,
      );
    });

    test('a shared position is not held alone', () {
      final shared = week(range(1, 3), extra: [entry('rival', 'rival', 2)]);
      expect(
        facts(shared).where((f) => f.$1 == ArtistDominanceKind.sweep),
        isEmpty,
      );
    });
  });

  group('Top 10 presence', () {
    test('3, 5 or 10 songs anywhere in the Top 10; the highest tier', () {
      expect(facts(week([2, 6, 9])), [(ArtistDominanceKind.top10, 3, 10, 3)]);
      expect(facts(week([2, 4, 6, 8, 9, 10])), [
        (ArtistDominanceKind.top10, 5, 10, 6),
        // All six Hot 100 songs are those Top 10 songs: not told twice.
      ]);
      expect(facts(week([2, 4])), isEmpty);
    });
  });

  group('Hot 100 presence', () {
    test('5, 10, 15 or 20 songs at #1–100, the highest tier, with the true '
        'count', () {
      List<int> spread(int n) => [for (var i = 0; i < n; i++) 15 + i * 4];
      expect(facts(week(spread(4))), isEmpty);
      expect(facts(week(spread(5))), [(ArtistDominanceKind.hot100, 5, 100, 5)]);
      expect(facts(week(spread(12))), [
        (ArtistDominanceKind.hot100, 10, 100, 12),
      ]);
      expect(facts(week(spread(15))), [
        (ArtistDominanceKind.hot100, 15, 100, 15),
      ]);
      expect(facts(week(spread(21))), [
        (ArtistDominanceKind.hot100, 20, 100, 21),
      ]);
    });

    test('#100 counts; Bubbling Under (#101–200) never does', () {
      expect(facts(week([60, 70, 80, 90, 100])), [
        (ArtistDominanceKind.hot100, 5, 100, 5),
      ]);
      expect(facts(week([60, 70, 80, 90, 101, 150, 200])), isEmpty);
    });
  });

  test('a song counts once, at its best rank, even if listed twice', () {
    final twice = week([20, 30, 40, 50], extra: [entry('nova-20', 'nova', 55)]);
    expect(facts(twice), isEmpty, reason: 'four distinct songs');
  });

  test('songs count for the artist the chart attributes them to (the '
      'primary artist), never for anyone else', () {
    // Five songs charting for "host": only host is counted.
    final week5 = week(
      const [],
      extra: [for (var i = 0; i < 5; i++) entry('g$i', 'host', 20 + i)],
    );
    final counted = detector.detect(
      snapshot: week5,
      history: const [],
      createdAt: createdAt,
    );
    expect(counted.map((e) => e.entity.artistId).toSet(), {'host'});
  });

  group('repeats', () {
    test('a held tier is quiet; a higher tier is told; a return after a '
        'lower week is told again', () {
      final five = [for (var i = 0; i < 5; i++) 30 + i];
      expect(facts(week(five), history: [previousWeek(five)]), isEmpty);
      expect(
        facts(
          week([...five, 40, 41, 42, 43, 44]),
          history: [previousWeek(five)],
        ),
        [(ArtistDominanceKind.hot100, 10, 100, 10)],
      );
      expect(facts(week(five), history: [previousWeek(five.take(4))]), [
        (ArtistDominanceKind.hot100, 5, 100, 5),
      ]);
    });

    test('a smaller sweep after a bigger one is not news', () {
      expect(
        facts(week(range(1, 3)), history: [previousWeek(range(1, 5))]),
        isEmpty,
      );
    });
  });

  test('the album chart and unfinalized weeks are never read', () {
    expect(facts(week(range(1, 10), chartType: ChartType.albums)), isEmpty);
    final live = ChartSnapshot(
      id: 'live',
      chartType: ChartType.songs,
      weekStartUtc: weekStart,
      weekEndUtc: weekEnd,
      entries: const [],
    );
    expect(
      () => detector.detect(snapshot: live, history: [], createdAt: createdAt),
      throwsArgumentError,
    );
  });

  test('deterministic: the same week gives the same events and keys', () {
    final a = detector.detect(
      snapshot: week(range(1, 5)),
      history: const [],
      createdAt: createdAt,
    );
    final b = detector.detect(
      snapshot: week(range(1, 5)),
      history: const [],
      createdAt: createdAt,
    );
    expect(
      [for (final e in a) e.deduplicationKey],
      [for (final e in b) e.deduplicationKey],
    );
    expect(a.map((e) => e.deduplicationKey).toSet(), hasLength(a.length));
  });

  group('compatibility', () {
    test('stored as the existing type, with a true threshold and count, so '
        'every Sonus version reads and tells it', () {
      final event = detector
          .detect(
            snapshot: week([3, 6, 9]),
            history: const [],
            createdAt: createdAt,
          )
          .single;
      expect(
        event.eventType,
        ChartMomentEventType.artistSimultaneousThresholdSongs,
      );
      expect(event.scope, ChartMomentScope.finalized);
      expect((event.threshold, event.milestoneValue), (10, 3));
      expect(event.entity.entityId, 'nova-3', reason: 'the best-ranked song');
      expect(event.relatedEntity?.entityId, 'nova-6');
      expect(event.sourceId, 'dominance:top10:3:week');
      expect(
        event.deduplicationKey,
        'moment:finalized:songs:${weekStart.millisecondsSinceEpoch}:nova:'
        'dominance:top10:3:week',
      );
    });

    test('ordinary Moments are not dominance, whatever their source', () {
      ChartMomentEvent stored(String? source, ChartMomentEventType type) =>
          ChartMomentEvent(
            id: 'id',
            deduplicationKey: 'key',
            chartType: ChartType.songs,
            scope: ChartMomentScope.finalized,
            eventType: type,
            entity: entry('s', 'nova', 1).entity,
            weekStartUtc: weekStart,
            weekEndUtc: weekEnd,
            occurredAt: weekEnd,
            createdAt: createdAt,
            sourceId: source,
          );
      const simultaneous =
          ChartMomentEventType.artistSimultaneousThresholdSongs;
      expect(ArtistDominance.of(stored('week', simultaneous)), isNull);
      expect(ArtistDominance.of(stored(null, simultaneous)), isNull);
      expect(
        ArtistDominance.of(
          stored('dominance:top10:3:w', ChartMomentEventType.debut),
        ),
        isNull,
      );
      expect(
        ArtistDominance.of(stored('dominance:top10:4:w', simultaneous)),
        isNull,
        reason: 'not a tier',
      );
      expect(
        ArtistDominance.of(stored('dominance:sweep:5:w', simultaneous))?.tier,
        5,
      );
    });
  });
}
