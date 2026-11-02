import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_ranking_history.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_chart_ranking_engine.dart';
import 'package:sonus_next/features/charts/domain/services/chart_ranking_engine.dart';
import 'package:sonus_next/features/charts/presentation/models/chart_entry_movement.dart';
import 'package:sonus_next/features/charts/presentation/widgets/chart_movement_indicator.dart';

final now = DateTime.utc(2026, 10, 30, 12);

ChartEntry entry({
  required int rank,
  required ChartMovement movement,
  int? previousFinalRank,
  int? previousExtendedRank,
  int? priorPeakRank,
  DateTime? firstChartedAt,
  DateTime? firstHot100At,
  int? peakRank,
  DateTime? peakAchievedAt,
}) => ChartEntry(
  entity: const ChartEntitySnapshot(
    entityId: 'song',
    title: 'Song',
    artistName: 'Artist',
  ),
  rank: rank,
  qualifiedStreamCount: 10,
  lastQualifiedAt: now,
  peakRank: peakRank ?? rank,
  peakAchievedAt: peakAchievedAt ?? now,
  weeksOnChart: 3,
  movement: movement,
  previousFinalRank: previousFinalRank,
  previousExtendedRank: previousExtendedRank,
  priorPeakRank: priorPeakRank,
  firstChartedAt: firstChartedAt,
  firstHot100At: firstHot100At,
);

ChartEntryMovement live(ChartEntry e, {DateTime? at}) =>
    ChartEntryMovement.of(e, live: true, now: at ?? now);

ChartEntryMovement finalized(
  ChartEntry e, {
  DateTime? weekStart,
  DateTime? weekEnd,
}) => ChartEntryMovement.of(
  e,
  live: false,
  now: now,
  weekStartUtc: weekStart,
  weekEndUtc: weekEnd,
);

void main() {
  group('movement', () {
    test('a climb: green +N with a bounded position percentage', () {
      final m = live(
        entry(rank: 6, movement: ChartMovement.up, previousFinalRank: 10),
      );
      expect(m.kind, ChartMoveKind.up);
      expect(m.positions, 4);
      expect(m.positionPercent, closeTo(4 / 99 * 100, 1e-9));
      expect(m.shortLabel, '+4');
      expect(m.percentLabel, '+4% position');
      expect(m.spokenLabel(6), 'Up 4 places, 4 percent position movement');
    });

    test('a fall from #1 to #100 is exactly −100%; = has no percentage', () {
      final m = live(
        entry(rank: 100, movement: ChartMovement.down, previousFinalRank: 1),
      );
      expect(m.positions, -99);
      expect(m.positionPercent, -100);
      expect(m.shortLabel, '−99');
      expect(m.percentLabel, '−100% position');

      final same = live(
        entry(rank: 12, movement: ChartMovement.same, previousFinalRank: 12),
      );
      expect(same.kind, ChartMoveKind.same);
      expect(same.shortLabel, '=');
      expect(same.percentLabel, isNull);
    });

    test('Bubbling Under moves on its own scale', () {
      final m = live(
        entry(
          rank: 150,
          movement: ChartMovement.reentry,
          previousExtendedRank: 160,
        ),
      );
      expect(m.zone, ChartZone.bubblingUnder);
      expect(m.kind, ChartMoveKind.up);
      expect(m.positions, 10);
      expect(m.positionPercent, closeTo(10 / 99 * 100, 1e-9));
    });

    test('across rank 100: real positions, never a percentage', () {
      // All-time view: the stored movement compares with #150.
      final promoted = live(
        entry(rank: 80, movement: ChartMovement.up, previousFinalRank: 150),
      );
      expect(promoted.kind, ChartMoveKind.promoted);
      expect(promoted.positions, 70);
      expect(promoted.positionPercent, isNull);
      expect(promoted.crossChartNote, 'from Bubbling Under');

      final demoted = live(
        entry(rank: 120, movement: ChartMovement.down, previousFinalRank: 90),
      );
      expect(demoted.kind, ChartMoveKind.demoted);
      expect(demoted.positions, -30);
      expect(demoted.positionPercent, isNull);
      expect(demoted.crossChartNote, 'to Bubbling Under');
    });

    test('a recorded Hot 100 debut from Bubbling Under stays NEW', () {
      final m = finalized(
        entry(
          rank: 80,
          movement: ChartMovement.newEntry,
          previousExtendedRank: 150,
        ),
      );
      expect(m.kind, ChartMoveKind.debut);
      expect(m.achievement, ChartAchievement.newEntry);
      expect(m.positionPercent, isNull);
    });

    test('missing history: no movement and no percentage is invented', () {
      final m = live(entry(rank: 40, movement: ChartMovement.same));
      expect(m.kind, ChartMoveKind.unknown);
      expect(m.positions, isNull);
      expect(m.positionPercent, isNull);
      expect(m.shortLabel, '');
      expect(m.achievement, ChartAchievement.none);
    });
  });

  group('achievements', () {
    test('NEW wins over a simultaneous new peak; a #1 debut says so', () {
      final m = live(
        entry(
          rank: 1,
          movement: ChartMovement.newEntry,
          priorPeakRank: 50,
          firstHot100At: now.subtract(const Duration(hours: 2)),
        ),
      );
      expect(m.achievement, ChartAchievement.newEntry);
      expect(m.spokenLabel(1), 'New entry at number 1');
    });

    test(
      'a new peak beats the best finalized position; live is provisional',
      () {
        final m = live(
          entry(
            rank: 7,
            movement: ChartMovement.up,
            previousFinalRank: 12,
            priorPeakRank: 9,
          ),
        );
        expect(m.achievement, ChartAchievement.newPeak);
        expect(m.highlighted, isTrue);
        expect(m.provisional, isTrue);
        expect(m.spokenLabel(7), endsWith('provisional new peak'));

        final notBetter = live(
          entry(
            rank: 9,
            movement: ChartMovement.up,
            previousFinalRank: 12,
            priorPeakRank: 9,
          ),
        );
        expect(notBetter.achievement, ChartAchievement.none);
      },
    );

    test('a finalized week shows a peak reached in that week as final', () {
      final start = DateTime.utc(2026, 10, 18);
      final end = DateTime.utc(2026, 10, 25);
      final m = finalized(
        entry(
          rank: 5,
          movement: ChartMovement.up,
          previousFinalRank: 9,
          peakRank: 5,
          peakAchievedAt: DateTime.utc(2026, 10, 20),
        ),
        weekStart: start,
        weekEnd: end,
      );
      expect(m.achievement, ChartAchievement.newPeak);
      expect(m.provisional, isFalse);
      expect(m.spokenLabel(5), endsWith(', new peak'));

      final earlierPeak = finalized(
        entry(
          rank: 5,
          movement: ChartMovement.up,
          previousFinalRank: 9,
          peakRank: 5,
          peakAchievedAt: DateTime.utc(2026, 9, 1),
        ),
        weekStart: start,
        weekEnd: end,
      );
      expect(earlierPeak.achievement, ChartAchievement.none);
    });

    test('NEW and RE-ENTRY stay highlighted for 24 hours on a live chart', () {
      ChartEntryMovement reentryAt(Duration ago, {bool isLive = true}) =>
          ChartEntryMovement.of(
            entry(
              rank: 30,
              movement: ChartMovement.reentry,
              firstHot100At: now.subtract(ago),
            ),
            live: isLive,
            now: now,
          );
      expect(
        reentryAt(const Duration(hours: 23, minutes: 59)).highlighted,
        isTrue,
      );
      expect(reentryAt(const Duration(hours: 24)).highlighted, isFalse);
      expect(
        reentryAt(const Duration(hours: 30)).achievement,
        ChartAchievement.reentry,
        reason: 'the fact stays',
      );
      expect(
        reentryAt(const Duration(hours: 1), isLive: false).highlighted,
        isFalse,
        reason: 'a finalized week shows the fact, not a highlight',
      );
      final unknown = live(entry(rank: 30, movement: ChartMovement.reentry));
      expect(unknown.highlighted, isFalse, reason: 'no first appearance');
    });

    test('Bubbling Under debuts expire from their first Top 200 time', () {
      final m = live(
        entry(
          rank: 140,
          movement: ChartMovement.newEntry,
          firstChartedAt: now.subtract(const Duration(hours: 3)),
          firstHot100At: now.subtract(const Duration(hours: 40)),
        ),
      );
      expect(m.achievement, ChartAchievement.newEntry);
      expect(m.highlighted, isTrue);
    });
  });

  group('engines record display facts without changing ranks', () {
    test('weekly: first Top 200 / Top 100 times, prior peak and last week', () {
      final t0 = DateTime.utc(2026, 10, 26, 10);
      final results = ChartRankingEngine().rank(
        events: [
          for (var i = 0; i < 3; i++)
            ChartRankingEvent(
              entityId: 'a',
              qualifiedAt: t0.add(Duration(minutes: i)),
            ),
          ChartRankingEvent(
            entityId: 'b',
            qualifiedAt: t0.add(const Duration(hours: 2)),
          ),
        ],
        historyByEntityId: {
          'a': ChartRankingHistory(
            entityId: 'a',
            finalizedWeeksOnChart: 4,
            hasEverCharted: true,
            previousFinalRank: 3,
            previousExtendedRank: 3,
            peakRank: 2,
            peakAchievedAt: DateTime.utc(2026, 9, 1),
          ),
        },
      );
      final a = results.firstWhere((r) => r.entityId == 'a');
      final b = results.firstWhere((r) => r.entityId == 'b');
      expect(a.rank, 1);
      expect(a.movement, ChartMovement.up, reason: 'rules unchanged');
      expect(a.priorPeakRank, 2);
      expect(a.previousExtendedRank, 3);
      expect(a.firstChartedAt, t0);
      expect(a.firstHot100At, t0);
      expect(b.firstChartedAt, t0.add(const Duration(hours: 2)));
      expect(b.priorPeakRank, isNull);
    });

    test('all-time: first appearances after the cutoff and the peak then', () {
      final cutoff = DateTime.utc(2026, 10, 25);
      final results = AllTimeChartRankingEngine().rank(
        events: [
          ChartRankingEvent(
            entityId: 'a',
            qualifiedAt: DateTime.utc(2026, 10, 1),
          ),
          ChartRankingEvent(
            entityId: 'b',
            qualifiedAt: DateTime.utc(2026, 10, 26),
          ),
        ],
        comparisonStartUtc: cutoff,
      );
      final a = results.firstWhere((r) => r.entityId == 'a');
      final b = results.firstWhere((r) => r.entityId == 'b');
      expect(a.priorPeakRank, 1);
      expect(a.firstChartedAt, isNull, reason: 'no play since the cutoff');
      expect(b.priorPeakRank, isNull);
      expect(b.firstChartedAt, DateTime.utc(2026, 10, 26));
      expect(b.firstHot100At, DateTime.utc(2026, 10, 26));
    });
  });

  group('indicator', () {
    Future<void> pump(
      WidgetTester tester,
      ChartEntryMovement m,
      ChartEntry e, {
      SonusThemeId theme = SonusThemeId.neonMixtape,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: theme)),
        home: Scaffold(
          body: Center(
            child: ChartMovementIndicator(entry: e, movement: m),
          ),
        ),
      ),
    );

    testWidgets('climb shows +N and the position percentage', (tester) async {
      final e = entry(
        rank: 6,
        movement: ChartMovement.up,
        previousFinalRank: 10,
      );
      await pump(tester, live(e), e);
      expect(find.text('+4'), findsOneWidget);
      expect(find.text('+4% position'), findsOneWidget);
    });

    testWidgets('NEW lit within 24 h, plain afterwards', (tester) async {
      final e = entry(
        rank: 20,
        movement: ChartMovement.newEntry,
        firstHot100At: now.subtract(const Duration(hours: 5)),
      );
      await pump(tester, live(e), e);
      expect(find.text('NEW'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('charts-achievement-song-lit')),
        findsOneWidget,
      );

      await pump(tester, live(e, at: now.add(const Duration(days: 1))), e);
      expect(find.text('NEW'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('charts-achievement-song-plain')),
        findsOneWidget,
      );
    });

    testWidgets('gold peak: live vs finalized wording', (tester) async {
      final e = entry(
        rank: 7,
        movement: ChartMovement.up,
        previousFinalRank: 12,
        priorPeakRank: 9,
      );
      await pump(tester, live(e), e);
      expect(find.text('PEAK · LIVE'), findsOneWidget);
      await pump(tester, finalized(e), e);
      expect(find.text('NEW PEAK'), findsOneWidget);
      await pump(tester, finalized(e), e, theme: SonusThemeId.monochrome);
      expect(tester.takeException(), isNull);
    });
  });
}
