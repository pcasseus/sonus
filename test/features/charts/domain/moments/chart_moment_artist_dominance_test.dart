// App Update 1.2, REF-19: artist dominance on the weekly Sonus Hot 100,
// stored as the existing "N songs in the Top T" Moment type. Sweeps of the
// Top 2 to 10, Top 10 and Hot 100 presence, verified streaks, and
// historical claims that need complete, original chart history.
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_history_evidence.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_artist_dominance.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';

const _sweep = ArtistDominanceKind.sweep;
const _top10 = ArtistDominanceKind.top10;
const _hot100 = ArtistDominanceKind.hot100;
const _original = ChartSnapshotProvenance.original;

void main() {
  const detector = ChartMomentArtistDominanceDetector();
  final createdAt = DateTime.utc(2026, 11, 16, 1);

  /// The current week; earlier weeks are [weeksBefore] weeks back.
  final weekStart = DateTime.utc(2027, 3, 7);
  DateTime startOf(int weeksBefore) =>
      weekStart.subtract(Duration(days: 7 * weeksBefore));

  ChartEntry entry(String songId, String artistId, int rank) => ChartEntry(
    entity: ChartEntitySnapshot(
      entityId: songId,
      title: 'Song $songId',
      artistId: artistId,
      artistName: 'Name $artistId',
    ),
    rank: rank,
    qualifiedStreamCount: 300 - rank,
    lastQualifiedAt: weekStart,
    peakRank: rank,
    peakAchievedAt: weekStart,
    weeksOnChart: 1,
    movement: ChartMovement.newEntry,
  );

  /// A 200-place week: [nova] holds [ranks], [rival] holds [rivalRanks];
  /// every other place belongs to an artist of its own.
  ChartSnapshot week(
    Iterable<int> ranks, {
    int weeksBefore = 0,
    Iterable<int> rivalRanks = const [],
    List<ChartEntry> extra = const [],
    ChartType chartType = ChartType.songs,
    ChartSnapshotProvenance? provenance = _original,
  }) {
    final mine = ranks.toSet();
    final rival = rivalRanks.toSet();
    final from = startOf(weeksBefore);
    return ChartSnapshot(
      id: 'week-$weeksBefore',
      chartType: chartType,
      weekStartUtc: from,
      weekEndUtc: from.add(const Duration(days: 7)),
      finalizedAt: from.add(const Duration(days: 7)),
      provenance: provenance,
      entries: [
        for (var rank = 1; rank <= 200; rank++)
          if (mine.contains(rank))
            entry('nova-$rank', 'nova', rank)
          else if (rival.contains(rank))
            entry('rival-$rank', 'rival', rank)
          else
            entry('other-$rank-$weeksBefore', 'other-$rank-$weeksBefore', rank),
        ...extra,
      ],
    );
  }

  List<int> range(int from, int to) => [for (var r = from; r <= to; r++) r];

  /// Evidence for a fully recorded history beginning long ago.
  final complete = ChartHistoryEvidence(
    currentWeekOriginal: true,
    historyOriginUtc: DateTime.utc(2026, 1, 1),
  );

  /// [count] quiet original weeks before the current one (no dominance).
  List<ChartSnapshot> quietWeeks(int count, {int from = 1}) => [
    for (var back = from; back < from + count; back++)
      week(const [], weeksBefore: back),
  ];

  List<ChartMomentEvent> detect(
    ChartSnapshot snapshot, {
    List<ChartSnapshot> history = const [],
    ChartHistoryEvidence? evidence,
  }) => detector.detect(
    snapshot: snapshot,
    history: history,
    createdAt: createdAt,
    evidence: evidence ?? ChartHistoryEvidence.unverified,
  );

  List<(ArtistDominanceKind, int, int, int, String)> facts(
    ChartSnapshot snapshot, {
    List<ChartSnapshot> history = const [],
    ChartHistoryEvidence? evidence,
  }) => [
    for (final event in detect(snapshot, history: history, evidence: evidence))
      if (ArtistDominance.of(event) case final fact?)
        (
          fact.kind,
          fact.tier,
          event.threshold!,
          event.milestoneValue!,
          fact.context.token,
        ),
  ];

  group('sweeps of the Top 2 to Top 10', () {
    for (var size = 2; size <= 10; size++) {
      test('#1–$size alone is a Top $size sweep, recorded once', () {
        expect(facts(week(range(1, size))), [(_sweep, size, size, size, '-')]);
      });
    }

    test('#1 alone, or a gap at #2, is no sweep', () {
      expect(facts(week([1])).where((f) => f.$1 == _sweep), isEmpty);
      expect(facts(week([1, 3, 4])).where((f) => f.$1 == _sweep), isEmpty);
    });

    test('the largest consecutive run from #1 counts, gaps after it do '
        'not', () {
      expect(facts(week([1, 2, 3, 4, 6])).first, (_sweep, 4, 4, 4, '-'));
    });

    test('another artist at #1 means no sweep for anyone below it', () {
      expect(facts(week(range(2, 6))).where((f) => f.$1 == _sweep), isEmpty);
    });

    test('a shared position is not held alone', () {
      final shared = week(range(1, 3), extra: [entry('x', 'rival', 2)]);
      expect(facts(shared).where((f) => f.$1 == _sweep), isEmpty);
    });

    test('a sweep plus more songs further down is separate facts', () {
      expect(facts(week([1, 2, 3, 7, 9, 40])), [
        (_sweep, 3, 3, 3, '-'),
        (_top10, 5, 10, 5, '-'),
        (_hot100, 5, 100, 6, '-'),
      ]);
    });
  });

  group('new, grown, held, smaller and returning sweeps', () {
    test('new: no sweep the week before', () {
      expect(
        facts(
          week(range(1, 3)),
          history: [
            week([5], weeksBefore: 1),
          ],
        ),
        [(_sweep, 3, 3, 3, '-')],
      );
    });

    test('grown: larger than the week before', () {
      expect(
        facts(week(range(1, 4)), history: [week(range(1, 3), weeksBefore: 1)]),
        [(_sweep, 4, 4, 4, '-')],
      );
    });

    test('held at the same size, or smaller: not news again', () {
      for (final before in [range(1, 3), range(1, 5)]) {
        expect(
          facts(week(range(1, 3)), history: [week(before, weeksBefore: 1)]),
          isEmpty,
          reason: 'held $before',
        );
      }
    });

    test('returning after a week without it, or after a week with no '
        'chart, is told again', () {
      expect(
        facts(
          week(range(1, 3)),
          history: [
            week([4], weeksBefore: 1),
          ],
        ),
        [(_sweep, 3, 3, 3, '-')],
      );
      expect(
        facts(week(range(1, 3)), history: [week(range(1, 3), weeksBefore: 2)]),
        [(_sweep, 3, 3, 3, '-')],
      );
    });
  });

  group('verified streaks of a held sweep', () {
    /// The current week and [held] earlier weeks with a Top 3 sweep, then a
    /// quiet original week before them.
    List<ChartSnapshot> streak(int held, {int quietBefore = 1}) => [
      for (var back = 1; back <= held; back++)
        week(range(1, 3), weeksBefore: back),
      ...quietWeeks(quietBefore, from: held + 1),
    ];

    test('told at the 2nd, 3rd, 5th and 10th straight week and every five '
        'weeks after, never in between', () {
      final told = <int>[];
      for (var weeks = 2; weeks <= 21; weeks++) {
        final result = facts(
          week(range(1, 3)),
          history: streak(weeks - 1),
          evidence: complete,
        );
        if (result.isNotEmpty) {
          expect(result.single, (_sweep, 3, 3, 3, 'streak$weeks'));
          told.add(weeks);
        }
      }
      expect(told, [2, 3, 5, 10, 15, 20]);
    });

    test('a smaller sweep continues a larger one as a streak of its size', () {
      expect(
        facts(
          week(range(1, 2)),
          history: [
            week(range(1, 5), weeksBefore: 1),
            ...quietWeeks(1, from: 2),
          ],
          evidence: complete,
        ),
        [(_sweep, 2, 2, 2, 'streak2')],
      );
    });

    test('a missing chart week ends the streak, so it is not counted '
        'across it', () {
      final history = [
        week(range(1, 3), weeksBefore: 1),
        // weeksBefore: 2 had no chart (no plays).
        week(range(1, 3), weeksBefore: 3),
        week(range(1, 3), weeksBefore: 4),
      ];
      expect(facts(week(range(1, 3)), history: history, evidence: complete), [
        (_sweep, 3, 3, 3, 'streak2'),
      ]);
    });

    group('never told when it cannot be shown', () {
      test('the current week is not original', () {
        expect(
          facts(
            week(range(1, 3), provenance: ChartSnapshotProvenance.unverified),
            history: streak(1),
            evidence: ChartHistoryEvidence.unverified,
          ),
          isEmpty,
        );
      });

      for (final provenance in [ChartSnapshotProvenance.unverified, null]) {
        test('a week of the streak is ${provenance?.name ?? 'unknown'}', () {
          expect(
            facts(
              week(range(1, 3)),
              history: [
                week(range(1, 3), weeksBefore: 1, provenance: provenance),
                ...quietWeeks(1, from: 2),
              ],
              evidence: complete,
            ),
            isEmpty,
          );
        });

        test('the week before the streak is '
            '${provenance?.name ?? 'unknown'}', () {
          expect(
            facts(
              week(range(1, 3)),
              history: [
                week(range(1, 3), weeksBefore: 1),
                week(const [], weeksBefore: 2, provenance: provenance),
              ],
              evidence: complete,
            ),
            isEmpty,
          );
        });
      }

      test('the week before the streak had plays but no chart', () {
        expect(
          facts(
            week(range(1, 3)),
            history: [week(range(1, 3), weeksBefore: 1)],
            evidence: ChartHistoryEvidence(
              currentWeekOriginal: true,
              historyOriginUtc: DateTime.utc(2026, 1, 1),
              incompleteWeekStartsUtc: {startOf(2)},
            ),
          ),
          isEmpty,
        );
      });

      test('the week before the streak predates the chart history', () {
        expect(
          facts(
            week(range(1, 3)),
            history: [week(range(1, 3), weeksBefore: 1)],
            evidence: ChartHistoryEvidence(
              currentWeekOriginal: true,
              historyOriginUtc: startOf(1),
            ),
          ),
          isEmpty,
        );
      });
    });
  });

  group('Top 10 presence', () {
    test('3, 5 or 10 songs anywhere in the Top 10; the highest tier, with '
        'the true count', () {
      expect(facts(week([2, 6, 9])), [(_top10, 3, 10, 3, '-')]);
      expect(facts(week([2, 4, 6, 9])), [(_top10, 3, 10, 4, '-')]);
      expect(facts(week([2, 4, 6, 8, 9, 10])), [(_top10, 5, 10, 6, '-')]);
      expect(facts(week([2, 4])), isEmpty);
    });

    test('a held or lower tier is quiet; a higher tier is told', () {
      expect(
        facts(
          week([2, 6, 9, 10]),
          history: [
            week([3, 5, 7], weeksBefore: 1),
          ],
        ),
        isEmpty,
        reason: '4 songs is still the 3 tier',
      );
      expect(
        facts(
          week([2, 4, 6, 8, 9]),
          history: [
            week([3, 5, 7], weeksBefore: 1),
          ],
        ),
        [(_top10, 5, 10, 5, '-')],
      );
    });
  });

  group('Hot 100 presence', () {
    List<int> spread(int n) => [for (var i = 0; i < n; i++) 15 + i * 4];

    test('5, 10, 15 or 20 songs at #1–100, the highest tier, with the true '
        'count', () {
      expect(facts(week(spread(4))), isEmpty);
      expect(facts(week(spread(5))), [(_hot100, 5, 100, 5, '-')]);
      expect(facts(week(spread(7))), [(_hot100, 5, 100, 7, '-')]);
      expect(facts(week(spread(12))), [(_hot100, 10, 100, 12, '-')]);
      expect(facts(week(spread(15))), [(_hot100, 15, 100, 15, '-')]);
      expect(facts(week(spread(21))), [(_hot100, 20, 100, 21, '-')]);
    });

    test('#100 counts; Bubbling Under (#101–200) never does', () {
      expect(facts(week([60, 70, 80, 90, 100])), [(_hot100, 5, 100, 5, '-')]);
      expect(facts(week([60, 70, 80, 90, 101, 150, 200])), isEmpty);
    });

    test('a held tier is quiet; a higher one is told', () {
      final five = spread(5);
      expect(facts(week(five), history: [week(five, weeksBefore: 1)]), isEmpty);
      expect(facts(week(spread(10)), history: [week(five, weeksBefore: 1)]), [
        (_hot100, 10, 100, 10, '-'),
      ]);
    });
  });

  group('overlap', () {
    test('a kind counting the same songs as a more notable one is not '
        'recorded again', () {
      expect(facts(week(range(1, 3))), [(_sweep, 3, 3, 3, '-')]);
      expect(facts(week(range(1, 5))), [(_sweep, 5, 5, 5, '-')]);
      expect(facts(week([2, 4, 6, 8, 9, 10])), [(_top10, 5, 10, 6, '-')]);
    });

    test('a held sweep still keeps its songs from being told as presence', () {
      expect(
        facts(week(range(1, 3)), history: [week(range(1, 3), weeksBefore: 1)]),
        isEmpty,
      );
    });
  });

  test('a song counts once, at its best rank, even if listed twice', () {
    final twice = week([20, 30, 40, 50], extra: [entry('nova-20', 'nova', 55)]);
    expect(facts(twice), isEmpty, reason: 'four distinct songs');
  });

  test('songs count for the artist the chart attributes them to (the '
      'primary artist), never for anyone else', () {
    final week5 = week(
      const [],
      extra: [for (var i = 0; i < 5; i++) entry('g$i', 'host', 20 + i)],
    );
    expect(detect(week5).map((e) => e.entity.artistId).toSet(), {'host'});
  });

  group('historical claims', () {
    /// Eight quiet earlier weeks: the minimum that can support a claim.
    final eight = quietWeeks(8);

    test('the first Top N sweep in Sonus Hot 100 history', () {
      expect(facts(week(range(1, 4)), history: eight, evidence: complete), [
        (_sweep, 4, 4, 4, 'chart-first'),
      ]);
    });

    test("the artist's first: someone else had swept this size before", () {
      final history = [
        ...eight,
        week(const [], rivalRanks: range(1, 4), weeksBefore: 9),
      ];
      expect(facts(week(range(1, 4)), history: history, evidence: complete), [
        (_sweep, 4, 4, 4, 'artist-first'),
      ]);
    });

    test('a repeat counts separate runs, never weeks of one run', () {
      final history = [
        week(const [], weeksBefore: 1),
        week(range(1, 3), weeksBefore: 2),
        week(range(1, 3), weeksBefore: 3),
        ...quietWeeks(3, from: 4),
        week(range(1, 4), weeksBefore: 7),
        ...quietWeeks(2, from: 8),
      ];
      expect(facts(week(range(1, 3)), history: history, evidence: complete), [
        (_sweep, 3, 3, 3, 'repeat3'),
      ]);
    });

    test('a chart record, a tie, and a personal best for presence', () {
      final record = [
        ...quietWeeks(7),
        week([2, 4, 6, 8], weeksBefore: 8),
      ];
      expect(
        facts(week([2, 4, 6, 8, 9]), history: record, evidence: complete),
        [(_top10, 5, 10, 5, 'chart-record')],
      );

      final tie = [
        ...quietWeeks(7),
        week(const [], rivalRanks: [2, 4, 6, 8, 9], weeksBefore: 8),
      ];
      expect(facts(week([3, 5, 7, 8, 10]), history: tie, evidence: complete), [
        (_top10, 5, 10, 5, 'chart-record-tie'),
      ]);

      final personal = [
        ...quietWeeks(6),
        week([20, 30, 40], weeksBefore: 7),
        week(
          const [],
          rivalRanks: [for (var i = 0; i < 9; i++) 11 + i],
          weeksBefore: 8,
        ),
      ];
      expect(
        facts(
          week([for (var i = 0; i < 5; i++) 30 + i * 3]),
          history: personal,
          evidence: complete,
        ),
        [(_hot100, 5, 100, 5, 'personal-best')],
      );
    });

    test('nothing to claim: an ordinary headline', () {
      final history = [
        ...quietWeeks(7),
        week(
          const [],
          rivalRanks: [for (var i = 0; i < 9; i++) 11 + i],
          weeksBefore: 8,
        ),
      ];
      expect(
        facts(
          week([for (var i = 0; i < 5; i++) 30 + i * 3]),
          history: history,
          evidence: complete,
        ),
        [(_hot100, 5, 100, 5, '-')],
      );
    });

    group('incomplete or unverified history: no claim, the ordinary '
        'headline instead', () {
      void ordinary(
        List<ChartSnapshot> history,
        ChartHistoryEvidence evidence, {
        ChartSnapshotProvenance? current = _original,
      }) {
        expect(
          facts(
            week(range(1, 4), provenance: current),
            history: history,
            evidence: evidence,
          ),
          [(_sweep, 4, 4, 4, '-')],
        );
      }

      test('seven earlier weeks are not enough', () {
        ordinary(quietWeeks(7), complete);
      });

      test('an earlier week is unverified', () {
        ordinary([
          ...quietWeeks(7),
          week(
            const [],
            weeksBefore: 8,
            provenance: ChartSnapshotProvenance.unverified,
          ),
        ], complete);
      });

      test('an earlier week is unknown (stored before version 46)', () {
        ordinary([
          ...quietWeeks(8),
          week(const [], weeksBefore: 9, provenance: null),
        ], complete);
      });

      test('an earlier week had plays but no chart', () {
        ordinary(
          eight,
          ChartHistoryEvidence(
            currentWeekOriginal: true,
            historyOriginUtc: DateTime.utc(2026, 1, 1),
            incompleteWeekStartsUtc: {startOf(12)},
          ),
        );
      });

      test('the current week is not original', () {
        ordinary(
          eight,
          ChartHistoryEvidence.unverified,
          current: ChartSnapshotProvenance.unverified,
        );
      });
    });
  });

  test('the album chart and unfinalized weeks are never read', () {
    expect(facts(week(range(1, 10), chartType: ChartType.albums)), isEmpty);
    final live = ChartSnapshot(
      id: 'live',
      chartType: ChartType.songs,
      weekStartUtc: weekStart,
      weekEndUtc: weekStart.add(const Duration(days: 7)),
      entries: const [],
    );
    expect(() => detect(live), throwsArgumentError);
  });

  test('deterministic and idempotent: the same week gives the same events '
      'and keys, and the key never depends on the claim', () {
    final a = detect(
      week(range(1, 5)),
      history: quietWeeks(8),
      evidence: complete,
    );
    final b = detect(
      week(range(1, 5)),
      history: quietWeeks(8),
      evidence: complete,
    );
    final plain = detect(week(range(1, 5)));
    expect([for (final e in a) e.sourceId], [for (final e in b) e.sourceId]);
    expect(
      [for (final e in a) e.deduplicationKey],
      [for (final e in plain) e.deduplicationKey],
    );
    expect(a.single.sourceId, 'dominance:sweep:5:chart-first:week-0');
    expect(plain.single.sourceId, 'dominance:sweep:5:-:week-0');
  });

  group('compatibility', () {
    test('stored as the existing type, with a true threshold and count, so '
        'every Sonus version reads and tells it', () {
      final event = detect(week([3, 6, 9])).single;
      expect(
        event.eventType,
        ChartMomentEventType.artistSimultaneousThresholdSongs,
      );
      expect(event.scope, ChartMomentScope.finalized);
      expect((event.threshold, event.milestoneValue), (10, 3));
      expect(event.entity.entityId, 'nova-3', reason: 'the best-ranked song');
      expect(event.relatedEntity?.entityId, 'nova-6');
      expect(event.sourceId, 'dominance:top10:3:-:week-0');
      expect(
        event.deduplicationKey,
        'moment:finalized:songs:${weekStart.millisecondsSinceEpoch}:nova:'
        'dominance:top10:3:week-0',
      );
    });

    test('a Top 2 sweep reads as "2 songs in the Top 2" in older builds', () {
      final event = detect(week([1, 2])).single;
      expect((event.threshold, event.milestoneValue), (2, 2));
      expect(event.currentRank, 1);
    });

    test('ordinary Moments and malformed sources are not dominance', () {
      ChartMomentEvent stored(String? source, ChartMomentEventType type) =>
          ChartMomentEvent(
            id: 'id',
            deduplicationKey: 'key',
            chartType: ChartType.songs,
            scope: ChartMomentScope.finalized,
            eventType: type,
            entity: entry('s', 'nova', 1).entity,
            weekStartUtc: weekStart,
            weekEndUtc: weekStart.add(const Duration(days: 7)),
            occurredAt: weekStart,
            createdAt: createdAt,
            sourceId: source,
          );
      const simultaneous =
          ChartMomentEventType.artistSimultaneousThresholdSongs;
      for (final source in [
        'week',
        null,
        'dominance:top10:4:-:w',
        'dominance:sweep:1:-:w',
        'dominance:sweep:11:-:w',
        'dominance:sweep:5:w',
        'dominance:sweep:5:streak1:w',
        'dominance:sweep:5:bogus:w',
        'dominance:sweep:5:-:',
      ]) {
        expect(
          ArtistDominance.of(stored(source, simultaneous)),
          isNull,
          reason: '$source',
        );
      }
      expect(
        ArtistDominance.of(
          stored('dominance:top10:3:-:w', ChartMomentEventType.debut),
        ),
        isNull,
      );
      expect(
        ArtistDominance.of(
          stored('dominance:sweep:5:streak10:w', simultaneous),
        ),
        const ArtistDominance(
          _sweep,
          5,
          DominanceContext(DominanceContextKind.streak, 10),
        ),
      );
    });

    test('every context round-trips through its token', () {
      for (final context in const [
        DominanceContext.none,
        DominanceContext(DominanceContextKind.chartFirst),
        DominanceContext(DominanceContextKind.chartRecord),
        DominanceContext(DominanceContextKind.chartRecordTie),
        DominanceContext(DominanceContextKind.streak, 5),
        DominanceContext(DominanceContextKind.artistFirst),
        DominanceContext(DominanceContextKind.personalBest),
        DominanceContext(DominanceContextKind.repeat, 3),
      ]) {
        expect(context.token, isNot(contains(':')));
        expect(DominanceContext.parse(context.token), context);
      }
    });
  });
}
