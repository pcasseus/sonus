// Chart movement and status rules, end to end (App Update 1.3 audit).
//
// Weekly charts run through the real ChartSnapshotBuilderService (history
// context + ChartRankingEngine) and career standings through the real
// AllTimeChartService (AllTimeChartRankingEngine). Every assertion is on
// the ChartEntryMovement a chart row shows.
//
// Product rules under test:
// - NEW: first appearance on the relevant chart ever.
// - RE-ENTRY: back on the relevant chart after being absent from it in the
//   preceding completed chart period; it never persists.
// - Rise / fall / hold against the same chart's previous period.
// - NEW PEAK: best position in the chart's history.
// - Hot 100 (#1–100) and Bubbling Under (#101–200) stay distinct; no
//   movement without a valid comparison period.
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/analytics/domain/entities/playback_session.dart';
import 'package:sonus_next/features/analytics/domain/entities/qualified_play.dart';
import 'package:sonus_next/features/analytics/domain/repositories/playback_session_repository.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/chart_snapshot_builder_service.dart';
import 'package:sonus_next/features/charts/data/mappers/chart_entry_row_mapper.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/domain/services/chart_week_resolver.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_entry_movement.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_longevity.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';

const song = 'target';

void main() {
  group('weekly chart', () {
    test('a fresh debut is NEW, never a re-entry', () async {
      final chart = _WeeklyChart();
      final week = await chart.week(0, {song: 30});

      for (final m in [week.live(song), week.stored(song)]) {
        expect(m.kind, ChartMoveKind.debut);
        expect(m.shortLabel, 'NEW');
        expect(m.achievement, ChartAchievement.newEntry);
        expect(m.positions, isNull);
      }
    });

    test('weeks A–D: RE-ENTRY on return, then plain movement', () async {
      final chart = _WeeklyChart();
      await chart.week(0, {song: 30});
      final a = await chart.week(1, {}); // Week A: absent.
      final b = await chart.week(2, {song: 42});
      final c = await chart.week(3, {song: 27});
      final d = await chart.week(4, {song: 19});

      expect(a.entry(song), isNull);
      for (final m in [b.live(song), b.stored(song)]) {
        expect(m.kind, ChartMoveKind.reentry);
        expect(m.shortLabel, 'RE-ENTRY');
        expect(m.achievement, ChartAchievement.reentry);
      }
      for (final m in [c.live(song), c.stored(song)]) {
        expect(m.kind, ChartMoveKind.up);
        expect(m.shortLabel, '+15');
        expect(m.achievement, isNot(ChartAchievement.reentry));
      }
      for (final m in [d.live(song), d.stored(song)]) {
        expect(m.kind, ChartMoveKind.up);
        expect(m.shortLabel, '+8');
        expect(m.achievement, isNot(ChartAchievement.reentry));
      }
    });

    test('continuous charting is never a re-entry', () async {
      final chart = _WeeklyChart();
      await chart.week(0, {song: 50});
      for (final (w, rank) in [(1, 60), (2, 60), (3, 10), (4, 99)]) {
        final week = await chart.week(w, {song: rank});
        for (final m in [week.live(song), week.stored(song)]) {
          expect(m.kind, isNot(ChartMoveKind.reentry), reason: 'week $w');
          expect(m.kind, isNot(ChartMoveKind.debut), reason: 'week $w');
        }
      }
    });

    test('rise, fall and hold', () async {
      final chart = _WeeklyChart();
      await chart.week(0, {'riser': 20, 'faller': 12, 'holder': 7});
      final week = await chart.week(1, {
        'riser': 15,
        'faller': 17,
        'holder': 7,
      });

      for (final view in [week.live, week.stored]) {
        expect(view('riser').kind, ChartMoveKind.up);
        expect(view('riser').shortLabel, '+5');
        expect(view('faller').kind, ChartMoveKind.down);
        expect(view('faller').shortLabel, '−5');
        expect(view('holder').kind, ChartMoveKind.same);
        expect(view('holder').shortLabel, '=');
      }
    });

    test('a new peak coexists with a climb; a climb short of the peak '
        'is not one', () async {
      final chart = _WeeklyChart();
      await chart.week(0, {'peaker': 20, 'former-high': 5});
      await chart.week(1, {'peaker': 18, 'former-high': 20});
      final week = await chart.week(2, {'peaker': 14, 'former-high': 15});

      for (final view in [week.live, week.stored]) {
        expect(view('peaker').kind, ChartMoveKind.up);
        expect(view('peaker').achievement, ChartAchievement.newPeak);
        expect(view('former-high').kind, ChartMoveKind.up);
        expect(view('former-high').shortLabel, '+5');
        expect(view('former-high').achievement, ChartAchievement.none);
      }
    });

    test('a Bubbling Under climb to its best position is a new peak', () async {
      final chart = _WeeklyChart();
      await chart.week(0, {song: 160});
      final week = await chart.week(1, {song: 140});

      for (final m in [week.live(song), week.stored(song)]) {
        expect(m.zone, ChartZone.bubblingUnder);
        expect(m.kind, ChartMoveKind.up);
        expect(m.shortLabel, '+20');
        expect(m.achievement, ChartAchievement.newPeak);
      }
    });

    test('#100 to #101: down to Bubbling Under, no percentage', () async {
      final chart = _WeeklyChart();
      await chart.week(0, {song: 100});
      final week = await chart.week(1, {song: 101});

      for (final m in [week.live(song), week.stored(song)]) {
        expect(m.kind, ChartMoveKind.demoted);
        expect(m.shortLabel, '−1');
        expect(m.crossChartNote, 'to Bubbling Under');
        expect(m.positionPercent, isNull);
      }
    });

    test(
      '#101 to #100, never on the Hot 100 before: NEW on the Hot 100',
      () async {
        final chart = _WeeklyChart();
        await chart.week(0, {song: 101});
        final week = await chart.week(1, {song: 100});

        for (final m in [week.live(song), week.stored(song)]) {
          expect(m.kind, ChartMoveKind.debut);
          expect(m.achievement, ChartAchievement.newEntry);
          expect(m.positionPercent, isNull);
        }
      },
    );

    test('#101 to #100 after an earlier Hot 100 run: RE-ENTRY', () async {
      final chart = _WeeklyChart();
      await chart.week(0, {song: 50});
      await chart.week(1, {song: 101});
      final week = await chart.week(2, {song: 100});

      for (final m in [week.live(song), week.stored(song)]) {
        expect(m.kind, ChartMoveKind.reentry);
        expect(m.achievement, ChartAchievement.reentry);
      }
    });

    test('Bubbling Under before, never the Hot 100: its Hot 100 arrival is '
        'NEW', () async {
      final chart = _WeeklyChart();
      await chart.week(0, {song: 150});
      await chart.week(1, {});
      final week = await chart.week(2, {song: 90});

      for (final m in [week.live(song), week.stored(song)]) {
        expect(m.kind, ChartMoveKind.debut);
        expect(m.shortLabel, 'NEW');
      }
    });

    test('a return to Bubbling Under after a week away is RE-ENTRY, not '
        'NEW', () async {
      final chart = _WeeklyChart();
      await chart.week(0, {song: 150});
      await chart.week(1, {});
      final week = await chart.week(2, {song: 160});

      for (final m in [week.live(song), week.stored(song)]) {
        expect(m.zone, ChartZone.bubblingUnder);
        expect(m.kind, ChartMoveKind.reentry);
        expect(m.shortLabel, 'RE-ENTRY');
      }
    });

    test('continuous Bubbling Under moves on its own scale', () async {
      final chart = _WeeklyChart();
      await chart.week(0, {song: 150});
      final week = await chart.week(1, {song: 140});

      for (final m in [week.live(song), week.stored(song)]) {
        expect(m.kind, ChartMoveKind.up);
        expect(m.shortLabel, '+10');
        expect(m.positionPercent, closeTo(10 / 99 * 100, 1e-9));
      }
    });

    test('no movement across a missing week: the comparison period must be '
        'the one right before', () async {
      final chart = _WeeklyChart();
      await chart.week(0, {song: 30});
      // Week 1 was never finalized (no chart exists for it).
      final week = await chart.week(2, {song: 20});

      for (final m in [week.live(song), week.stored(song)]) {
        expect(m.kind, ChartMoveKind.reentry);
        expect(m.positions, isNull);
      }
    });

    test('no comparison facts: no arrow, no NEW, nothing invented', () {
      final m = ChartEntryMovement.of(
        ChartEntry(
          entity: _WeeklyChart.identity(song),
          rank: 40,
          qualifiedStreamCount: 1,
          lastQualifiedAt: _WeeklyChart.start(0),
          peakRank: 40,
          peakAchievedAt: _WeeklyChart.start(0),
          weeksOnChart: 0,
          movement: ChartMovement.up,
        ),
        live: true,
        now: _WeeklyChart.start(0),
      );

      expect(m.kind, ChartMoveKind.unknown);
      expect(m.shortLabel, '');
      expect(m.positions, isNull);
      expect(m.achievement, ChartAchievement.none);
    });
  });

  group('career standings', () {
    test('a fresh debut is NEW', () async {
      final career = _CareerChart()
        ..plays('old', 3, career0)
        ..plays(song, 1, careerWeek(1));

      final m = await career.movement(song, week: 1);
      expect(m.kind, ChartMoveKind.debut);
      expect(m.achievement, ChartAchievement.newEntry);
    });

    test('weeks A–D: RE-ENTRY on return, then plain movement', () async {
      final career = _CareerChart()
        // The song charts first (#1), then everyone else arrives.
        ..plays(song, 1, career0)
        ..tier('top', 18, 100)
        ..tier('upper', 8, 80)
        ..tier('middle', 15, 60)
        // 200 more push it out of the Top 200 before week A.
        ..tier('crowd', 200, 10);

      expect(await career.rankOf(song, week: 1), isNull); // Week A: absent.

      career.plays(song, 54, careerWeek(2)); // 55 plays: #42.
      final b = await career.movement(song, week: 2);
      expect(await career.rankOf(song, week: 2), 42);
      expect(b.kind, ChartMoveKind.reentry);
      expect(b.shortLabel, 'RE-ENTRY');

      career.plays(song, 15, careerWeek(3)); // 70 plays: #27.
      final c = await career.movement(song, week: 3);
      expect(c.kind, ChartMoveKind.up);
      expect(c.shortLabel, '+15');
      expect(c.achievement, isNot(ChartAchievement.reentry));

      career.plays(song, 20, careerWeek(4)); // 90 plays: #19.
      final d = await career.movement(song, week: 4);
      expect(d.kind, ChartMoveKind.up);
      expect(d.shortLabel, '+8');
      expect(d.achievement, isNot(ChartAchievement.reentry));
    });

    test('rise, fall and hold', () async {
      final riser = _CareerChart()
        ..tier('top', 14, 20)
        ..tier('low', 5, 12)
        ..plays(song, 10, career0) // #20.
        ..plays(song, 4, careerWeek(1)); // 14 plays: #15.
      expect((await riser.movement(song, week: 1)).kind, ChartMoveKind.up);
      expect((await riser.movement(song, week: 1)).shortLabel, '+5');

      final faller = _CareerChart()
        ..tier('top', 11, 20)
        ..plays(song, 15, career0) // #12.
        ..tier('low', 5, 10)
        ..tier('low', 5, 6, at: careerWeek(1)); // Five pass it: #17.
      expect((await faller.movement(song, week: 1)).kind, ChartMoveKind.down);
      expect((await faller.movement(song, week: 1)).shortLabel, '−5');

      final holder = _CareerChart()
        ..tier('top', 6, 20)
        ..plays(song, 15, career0) // #7.
        ..tier('low', 3, 5)
        ..tier('low', 3, 2, at: careerWeek(1)); // Still below it.
      expect((await holder.movement(song, week: 1)).kind, ChartMoveKind.same);
      expect((await holder.movement(song, week: 1)).shortLabel, '=');
    });

    test('a new peak coexists with a climb; a climb short of the peak is '
        'not one', () async {
      final career = _CareerChart()
        ..plays('former-high', 2, career0) // #1 at first.
        ..tier('top', 20, 10)
        ..plays('peaker', 3, career0)
        ..plays('peaker', 10, careerWeek(1))
        ..plays('former-high', 10, careerWeek(1));

      final peaker = await career.movement('peaker', week: 1);
      expect(peaker.kind, ChartMoveKind.up);
      expect(peaker.achievement, ChartAchievement.newPeak);

      final formerHigh = await career.movement('former-high', week: 1);
      expect(formerHigh.kind, ChartMoveKind.up);
      expect(formerHigh.achievement, ChartAchievement.none);
    });

    test('#100 to #101: down to Bubbling Under, no percentage', () async {
      final career = _CareerChart()
        ..tier('top', 99, 10)
        ..plays(song, 5, career0)
        ..plays('passer', 4, career0)
        ..plays('passer', 2, careerWeek(1));

      expect(await career.rankOf(song, week: 1), 101);
      final m = await career.movement(song, week: 1);
      expect(m.kind, ChartMoveKind.demoted);
      expect(m.shortLabel, '−1');
      expect(m.crossChartNote, 'to Bubbling Under');
      expect(m.positionPercent, isNull);
    });

    // Charts 2.0 C2 (ChartEntryMovement doc; chart_entry_movement_test
    // "across rank 100"): on career standings a continuous move across
    // rank 100 is a promotion, and #100 to #101 a demotion (above).
    // Approved by user decision 2026-11-16: career #101 to #100 shows
    // PROMOTED and #100 to #101 DEMOTED, keeping continuous-chart movement,
    // peaks and history.
    test(
      '#101 to #100, never on the Hot 100: promoted (approved 2026-11-16)',
      () async {
        final career = _CareerChart()
          ..tier('top', 99, 10)
          ..plays('holder', 5, career0)
          ..plays(song, 4, career0)
          ..plays(song, 2, careerWeek(1));

        expect(await career.rankOf(song, week: 1), 100);
        final m = await career.movement(song, week: 1);
        expect(m.kind, ChartMoveKind.promoted);
        expect(m.shortLabel, '+1');
        expect(m.crossChartNote, 'from Bubbling Under');
        expect(m.positionPercent, isNull);
      },
    );

    test('#101 to #100 after an earlier Hot 100 run: promoted (approved '
        '2026-11-16)', () async {
      final career = _CareerChart()
        ..plays(song, 4, career0) // #1 at first.
        ..tier('top', 99, 10)
        ..plays('holder', 5, career0)
        ..plays(song, 2, careerWeek(1));

      expect(await career.rankOf(song, week: 1), 100);
      final m = await career.movement(song, week: 1);
      expect(m.kind, ChartMoveKind.promoted);
    });

    test('Bubbling Under before, never the Hot 100: a return straight into '
        'the Hot 100 is NEW there', () async {
      final career = _CareerChart()
        ..tier('top', 149, 20)
        ..plays(song, 1, career0) // #150: Bubbling Under only.
        ..tier('crowd', 60, 2) // Out of the Top 200.
        ..plays(song, 20, careerWeek(1));

      expect(await career.rankOf(song, week: 0), isNull);
      final m = await career.movement(song, week: 1);
      expect(m.zone, ChartZone.hot100);
      expect(m.kind, ChartMoveKind.debut);
      expect(m.shortLabel, 'NEW');
    });

    test('a Hot 100 song back from outside the Top 200 is RE-ENTRY', () async {
      final career = _CareerChart()
        ..plays(song, 1, career0) // #1 at first.
        ..tier('top', 149, 20)
        ..tier('crowd', 60, 2)
        ..plays(song, 20, careerWeek(1));

      final m = await career.movement(song, week: 1);
      expect(m.zone, ChartZone.hot100);
      expect(m.kind, ChartMoveKind.reentry);
    });

    test(
      'a Bubbling Under song back from outside the Top 200 is RE-ENTRY',
      () async {
        final career = _CareerChart()
          ..tier('top', 149, 20)
          ..plays(song, 1, career0) // #150.
          ..tier('crowd', 60, 2)
          ..plays(song, 2, careerWeek(1)); // 3 plays: back in #101–200.

        final m = await career.movement(song, week: 1);
        expect(m.zone, ChartZone.bubblingUnder);
        expect(m.kind, ChartMoveKind.reentry);
      },
    );

    test('continuous Bubbling Under moves on its own scale', () async {
      final career = _CareerChart()
        ..tier('top', 139, 20)
        ..tier('band', 10, 8)
        ..plays(song, 5, career0) // #150.
        ..plays(song, 4, careerWeek(1)); // 9 plays: #140.

      final m = await career.movement(song, week: 1);
      expect(m.zone, ChartZone.bubblingUnder);
      expect(m.kind, ChartMoveKind.up);
      expect(m.shortLabel, '+10');
    });
  });
}

// ---------------------------------------------------------------------------
// Weekly harness: each week is built live (as seen during the week) and then
// finalized into history; [stored] reads it back as a stored row, as weekly
// history does.

final _weekZero = DateTime.utc(2026, 9, 6);

class _WeekViews {
  _WeekViews(this._live, this._stored, this._liveIndex, this._storedIndex);

  final ChartSnapshot _live;
  final ChartSnapshot _stored;
  final ChartLongevityIndex _liveIndex;
  final ChartLongevityIndex _storedIndex;

  ChartEntry? entry(String id) =>
      _stored.entries.where((e) => e.entity.entityId == id).firstOrNull;

  ChartEntryMovement live(String id) =>
      _movement(_live, _liveIndex, id, live: true);

  ChartEntryMovement stored(String id) =>
      _movement(_stored, _storedIndex, id, live: false);

  static ChartEntryMovement _movement(
    ChartSnapshot week,
    ChartLongevityIndex index,
    String id, {
    required bool live,
  }) {
    final entry = week.entries.firstWhere((e) => e.entity.entityId == id);
    return ChartEntryMovement.of(
      entry,
      live: live,
      now: week.weekEndUtc.subtract(const Duration(hours: 1)),
      weekStartUtc: live ? null : week.weekStartUtc,
      weekEndUtc: live ? null : week.weekEndUtc,
      // As ChartsController.previousExtendedRankFor supplies it.
      previousExtendedRank: entry.previousFinalRank != null
          ? null
          : index.previousExtendedRank(week.weekStartUtc, id),
    );
  }
}

class _WeeklyChart {
  final _plays = <QualifiedPlay>[];
  final _sessions = <String, PlaybackSession>{};
  final _history = <ChartSnapshot>[];

  static DateTime start(int week) => _weekZero.add(Duration(days: 7 * week));

  static ChartEntitySnapshot identity(String id) =>
      ChartEntitySnapshot(entityId: id, title: id, artistName: 'Artist');

  /// Places each id at its rank; fillers take every other position up to
  /// the lowest one asked for (or #50 for an empty week). One play each,
  /// most recent first, so ranks are exact.
  Future<_WeekViews> week(int week, Map<String, int> ranks) async {
    final size = ranks.isEmpty
        ? 50
        : ranks.values.reduce((a, b) => a > b ? a : b);
    final byRank = {for (final e in ranks.entries) e.value: e.key};
    final weekStart = start(week);
    for (var rank = size; rank >= 1; rank--) {
      final id = byRank[rank] ?? 'filler-$rank';
      final at = weekStart.add(Duration(minutes: size - rank + 1));
      final playId = 'w$week-$rank';
      _plays.add(
        QualifiedPlay(
          id: playId,
          playbackSessionId: 's-$playId',
          songId: id,
          artistId: 'artist',
          albumId: 'album-$id',
          albumEditionId: 'edition-$id',
          qualifiedAt: at,
          listenedDuration: const Duration(seconds: 30),
          trackDuration: const Duration(minutes: 3),
          createdAt: at,
        ),
      );
      _sessions['s-$playId'] = _session('s-$playId', id, at);
    }

    final builder = ChartSnapshotBuilderService(
      qualifiedPlays: _Plays(_plays),
      library: _EmptyLibrary(),
      charts: _History(_history),
      playbackSessions: _Sessions(_sessions),
    );
    final weekEnd = start(week + 1);
    final liveIndex = ChartLongevityIndex.fromHistory(_history);
    final live = await builder.build(
      chartType: ChartType.songs,
      weekStartUtc: weekStart,
      weekEndUtc: weekEnd,
    );
    final finalized = await builder.build(
      chartType: ChartType.songs,
      weekStartUtc: weekStart,
      weekEndUtc: weekEnd,
      finalizedAt: weekEnd,
    );
    final stored = ChartSnapshot(
      id: finalized.id,
      chartType: finalized.chartType,
      weekStartUtc: finalized.weekStartUtc,
      weekEndUtc: finalized.weekEndUtc,
      finalizedAt: finalized.finalizedAt,
      entries: [
        for (final entry in finalized.entries)
          ChartEntryRowMapper.fromRow(
            ChartEntryRowMapper.toRow(
              snapshotId: finalized.id,
              entry: entry,
              createdAt: weekEnd,
              updatedAt: weekEnd,
            ),
          ),
      ],
    );
    _history.add(stored);
    return _WeekViews(
      live,
      stored,
      liveIndex,
      ChartLongevityIndex.fromHistory(_history),
    );
  }
}

// ---------------------------------------------------------------------------
// Career harness: plays before each chart week, through AllTimeChartService
// (Top 200 view), compared from that week's start.

const _resolver = ChartWeekResolver();

/// Local Sundays, so the service's own week resolver agrees in any zone.
DateTime careerWeek(int week) =>
    _resolver.resolve(DateTime(2026, 9, 6 + 7 * week, 12)).startUtc;

final career0 = careerWeek(-2);

class _CareerChart {
  final _plays = <QualifiedPlay>[];
  final _sessions = <String, PlaybackSession>{};
  var _clock = 0;

  /// [count] plays of [id] from [from], each after every play added so far
  /// in that week.
  void plays(String id, int count, DateTime from) {
    for (var i = 0; i < count; i++) {
      final at = from.add(Duration(seconds: ++_clock));
      final playId = 'p$_clock';
      _plays.add(
        QualifiedPlay(
          id: playId,
          playbackSessionId: 's-$playId',
          songId: id,
          artistId: 'artist',
          albumId: 'album-$id',
          albumEditionId: 'edition-$id',
          qualifiedAt: at,
          listenedDuration: const Duration(seconds: 30),
          trackDuration: const Duration(minutes: 3),
          createdAt: at,
        ),
      );
      _sessions['s-$playId'] = _session('s-$playId', id, at);
    }
  }

  /// [size] songs with [count] plays each.
  void tier(String name, int size, int count, {DateTime? at}) {
    for (var i = 0; i < size; i++) {
      plays('$name-${i.toString().padLeft(3, '0')}', count, at ?? career0);
    }
  }

  Future<List<ChartEntry>> _load(int week) async {
    final reference = careerWeek(week).add(const Duration(days: 6)).toLocal();
    final service = AllTimeChartService(
      qualifiedPlays: _Plays([
        for (final play in _plays)
          if (!play.qualifiedAt.isAfter(reference.toUtc())) play,
      ]),
      library: _EmptyLibrary(),
      playbackSessions: _Sessions(_sessions),
    );
    final chart = await service.load(
      chartType: ChartType.songs,
      referenceLocal: reference,
      viewSize: ChartViewSize.top200,
    );
    return chart.entries;
  }

  Future<int?> rankOf(String id, {required int week}) async => (await _load(
    week,
  )).where((e) => e.entity.entityId == id).firstOrNull?.rank;

  /// What the career row shows. Career rows must not be handed a weekly
  /// previous position, so none is passed.
  Future<ChartEntryMovement> movement(String id, {required int week}) async {
    final entry = (await _load(
      week,
    )).firstWhere((e) => e.entity.entityId == id);
    return ChartEntryMovement.of(
      entry,
      live: true,
      now: careerWeek(week).add(const Duration(days: 6)),
    );
  }
}

// ---------------------------------------------------------------------------
// Fakes.

PlaybackSession _session(String id, String songId, DateTime at) =>
    PlaybackSession(
      id: id,
      songId: songId,
      artistId: 'artist',
      albumId: 'album-$songId',
      albumEditionId: 'edition-$songId',
      songTitle: songId,
      artistName: 'Artist',
      albumTitle: 'Album $songId',
      albumEditionTitle: 'Album $songId',
      startedAt: at,
      endedAt: at,
      listenedDuration: const Duration(minutes: 3),
      trackDuration: const Duration(minutes: 3),
      finalPosition: const Duration(minutes: 3),
      createdAt: at,
      updatedAt: at,
    );

class _Plays implements QualifiedPlayRepository {
  _Plays(this.plays);

  final List<QualifiedPlay> plays;

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async => [
    for (final play in plays)
      if ((qualifiedAtOrAfter == null ||
              !play.qualifiedAt.isBefore(qualifiedAtOrAfter)) &&
          (qualifiedBefore == null ||
              play.qualifiedAt.isBefore(qualifiedBefore)))
        play,
  ];

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Sessions implements PlaybackSessionRepository {
  _Sessions(this.byId);

  final Map<String, PlaybackSession> byId;

  @override
  Future<List<PlaybackSession>> getByIds(Iterable<String> ids) async => [
    for (final id in ids.toSet()) ?byId[id],
  ];

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _History implements ChartRepository {
  _History(this.history);

  final List<ChartSnapshot> history;

  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async => List.of(history);

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _EmptyLibrary implements LibraryQueryRepository {
  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async => const [];

  @override
  Future<List<LibraryAlbum>> getAlbums() async => const [];

  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
