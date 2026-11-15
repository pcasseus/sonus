import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_aggregator.dart';
import 'package:sonus_next/features/charts/application/services/moment_chart_journey_service.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_history_replay.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_editorial_desk.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_facts.dart';
import 'package:sonus_next/features/charts/presentation/pages/moment_story_page.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';

/// App Update 1.1: a story's Chart Journey always belongs to the story's
/// own chart. Weekly and artist stories show an explicit unavailable
/// state; the all-time journey is never borrowed for them.
class _Lookups implements MomentLookups {
  @override
  String? artistName(String artistId) => 'Madison Beer';
  @override
  ReleaseFormat? formatOf(String albumId) => ReleaseFormat.album;
  @override
  ReleaseFormat? songReleaseFormat(String songId) => ReleaseFormat.album;
  @override
  List<String> featuredOf(String songId) => const [];
  @override
  List<String> guestsOf(String songId) => const [];
  @override
  String? artistIdNamed(String name) => null;
  @override
  String? songCover(String songId) => null;
  @override
  String? releaseCover(String albumId) => null;
  @override
  String? currentSongCover(String songId) => null;
  @override
  String? currentReleaseCover(String albumId) => null;
  @override
  String? artistPortrait(String artistId) => null;
}

const _song = ChartEntitySnapshot(
  entityId: 'song-angel',
  title: 'angel wings',
  artistId: 'artist-madison',
  artistName: 'Madison Beer',
);

const _artist = ChartEntitySnapshot(
  entityId: 'artist-madison',
  title: 'Madison Beer',
  artistId: 'artist-madison',
  artistName: 'Madison Beer',
);

const _rival = ChartEntitySnapshot(
  entityId: 'artist-tate',
  title: 'Tate McRae',
  artistId: 'artist-tate',
  artistName: 'Tate McRae',
);

final _at = DateTime.utc(2026, 11, 6, 15);

ChartMomentEvent _event(
  ChartMomentScope scope,
  ChartMomentEventType type, {
  ChartEntitySnapshot entity = _song,
  ChartEntitySnapshot? related,
  int? previousRank,
  int? currentRank,
  int? threshold,
}) {
  final key = '${scope.name}|${type.name}|${entity.entityId}';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: 'play-1',
    chartType: ChartType.songs,
    scope: scope,
    eventType: type,
    entity: entity,
    relatedEntity: related,
    weekStartUtc: DateTime.utc(2026, 10, 25, 4),
    weekEndUtc: DateTime.utc(2026, 11, 1, 4),
    occurredAt: _at,
    createdAt: _at,
    previousRank: previousRank,
    currentRank: currentRank,
    threshold: threshold,
    previousPeakRank: 9,
    currentPeakRank: currentRank,
    qualifiedStreamCount: 30,
  );
}

MomentStory _story(List<ChartMomentEvent> events) => MomentEditorialDesk(
  lookups: _Lookups(),
  rules: ChartMomentRules(devicePolishFromUtc: DateTime.utc(2026, 11, 1)),
).compose(const ChartMomentFeedAggregator().aggregate(events)).first;

void main() {
  final calls = <(ChartType, String)>[];

  Future<MomentChartJourney?> loader(ChartType type, String id) async {
    calls.add((type, id));
    return MomentChartJourney(
      chartType: type,
      entityId: id,
      days: [
        ChartDayStanding(dayStartLocal: DateTime(2026, 11, 4), rank: 4),
        ChartDayStanding(dayStartLocal: DateTime(2026, 11, 5), rank: 3),
      ],
      totals: const ChartDayTotals(chartDays: 2, hot100Days: 2),
      peakRank: 3,
    );
  }

  setUp(calls.clear);

  Future<void> pump(WidgetTester tester, MomentStory story) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        home: MomentStoryPage(story: story, now: _at, journey: loader),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder unavailable(MomentStory story) => find.byKey(
    ValueKey<String>('moment-story-journey-unavailable-${story.id}'),
  );
  Finder chart(MomentStory story) =>
      find.byKey(ValueKey<String>('moment-story-journey-${story.id}'));

  testWidgets('an all-time story shows its own chart\'s journey', (
    tester,
  ) async {
    final story = _story([
      _event(
        ChartMomentScope.allTime,
        ChartMomentEventType.rankRise,
        previousRank: 9,
        currentRank: 3,
      ),
    ]);
    await pump(tester, story);

    expect(calls, [(ChartType.songs, 'song-angel')]);
    expect(chart(story), findsOneWidget);
    expect(unavailable(story), findsNothing);
    // App Update 1.3 (REF-1.3-06): the chart the journey is on.
    expect(find.textContaining('on the Career Top 200'), findsOneWidget);
  });

  testWidgets('a weekly story never borrows the all-time journey', (
    tester,
  ) async {
    final story = _story([
      _event(
        ChartMomentScope.finalized,
        ChartMomentEventType.newPeak,
        previousRank: 9,
        currentRank: 3,
      ),
    ]);
    expect(story.item.scope, ChartMomentScope.finalized);
    await pump(tester, story);

    expect(calls, isEmpty, reason: 'nothing from another chart is read');
    expect(chart(story), findsNothing);
    expect(unavailable(story), findsOneWidget);
    expect(
      find.descendant(
        of: unavailable(story),
        matching: find.textContaining(
          'from the Weekly Hot 100. Day-by-day ranks are kept only for the '
          'Career Top 200',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Total Days on Chart'), findsNothing);
  });

  // App Update 1.3 (REF-1.3-06): a weekly #114 is the weekly Bubbling
  // Under, never the Hot 100; the journey's chart is the career Top 200.
  testWidgets('a weekly Bubbling Under story names its own chart', (
    tester,
  ) async {
    final story = _story([
      _event(
        ChartMomentScope.finalized,
        ChartMomentEventType.debut,
        currentRank: 114,
      ),
    ]);
    await pump(tester, story);
    final reason = find.descendant(
      of: unavailable(story),
      matching: find.textContaining('from the Weekly Bubbling Under.'),
    );
    expect(reason, findsOneWidget);
    expect(find.textContaining('Weekly Hot 100'), findsNothing);
  });

  testWidgets('the facts name the career Top 200 and LIVE says it is '
      'provisional', (tester) async {
    final story = _story([
      _event(
        ChartMomentScope.allTime,
        ChartMomentEventType.rankRise,
        previousRank: 9,
        currentRank: 3,
      ),
    ]);
    await pump(tester, story);
    expect(find.text('Career Top 200'), findsOneWidget);
    expect(
      find.textContaining(
        "LIVE is today's position so far: provisional, and never added to "
        'the finalized history.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an artist story has no chart journey to show', (tester) async {
    final story = _story([
      _event(
        ChartMomentScope.allTime,
        ChartMomentEventType.artistBecomesTopArtist,
        entity: _artist,
        related: _rival,
        currentRank: 1,
        threshold: 1,
      ),
    ]);
    await pump(tester, story);

    expect(calls, isEmpty);
    expect(chart(story), findsNothing);
    expect(unavailable(story), findsOneWidget);
  });

  // App Update 1.3 (REF-1.3-02): the provisional live position after the
  // completed days, never stored.
  group('the live position', () {
    final allTime = _story([
      _event(
        ChartMomentScope.allTime,
        ChartMomentEventType.rankRise,
        previousRank: 9,
        currentRank: 3,
      ),
    ]);
    final days = [
      ChartDayStanding(dayStartLocal: DateTime(2026, 11, 4), rank: 4),
      ChartDayStanding(dayStartLocal: DateTime(2026, 11, 5), rank: 3),
    ];
    MomentChartJourney journeyWith(
      int? live, {
      List<ChartDayStanding>? history,
    }) => MomentChartJourney(
      chartType: ChartType.songs,
      entityId: 'song-angel',
      days: history ?? days,
      totals: const ChartDayTotals(chartDays: 2, hot100Days: 2),
      peakRank: 3,
      currentRank: live,
    );

    Future<void> open(
      WidgetTester tester,
      MomentStory story,
      MomentJourneyLoader load, {
      bool reduceMotion = false,
      LibraryChangeSignal? changes,
      bool settle = true,
    }) async {
      await tester.binding.setSurfaceSize(const Size(400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: MomentStoryPage(
            story: story,
            now: _at,
            journey: load,
            changes: changes ?? LibraryChangeSignal(),
          ),
        ),
      );
      if (settle) await tester.pumpAndSettle();
    }

    Finder live() => find.byKey(const ValueKey<String>('moment-journey-live'));
    Finder inLive(String text) =>
        find.descendant(of: live(), matching: find.text(text));

    testWidgets('a charting song: LIVE and its rank after the finalized '
        'days, which keep their ranks', (tester) async {
      final semantics = tester.ensureSemantics();
      final journey = journeyWith(2);
      await open(tester, allTime, (_, _) async => journey);

      expect(inLive('LIVE'), findsOneWidget);
      expect(inLive('#2'), findsOneWidget);
      expect(find.text('#4'), findsOneWidget);
      expect(find.text('#3'), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('moment-journey-live-unranked')),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Nov 5: #3, Live now, provisional: #2')),
        findsOneWidget,
      );
      // The provisional position is never added to the history.
      expect([for (final day in journey.days) day.rank], [4, 3]);
      semantics.dispose();
    });

    testWidgets('not charting now: an explicit unranked live state', (
      tester,
    ) async {
      await open(tester, allTime, (_, _) async => journeyWith(null));

      expect(inLive('LIVE'), findsOneWidget);
      expect(inLive('—'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('moment-journey-live-unranked')),
        findsOneWidget,
      );
      expect(find.text('Not on the all-time chart right now.'), findsOneWidget);
    });

    testWidgets('a weekly story has no live position', (tester) async {
      final weekly = _story([
        _event(
          ChartMomentScope.finalized,
          ChartMomentEventType.newPeak,
          previousRank: 9,
          currentRank: 3,
        ),
      ]);
      await open(tester, weekly, (_, _) async => journeyWith(2));
      expect(live(), findsNothing);
      expect(find.text('LIVE'), findsNothing);
    });

    testWidgets('one completed day and charting now still shows the live '
        'position', (tester) async {
      await open(
        tester,
        allTime,
        (_, _) async => journeyWith(
          7,
          history: [
            ChartDayStanding(dayStartLocal: DateTime(2026, 11, 5), rank: 9),
          ],
        ),
      );
      expect(chart(allTime), findsOneWidget);
      expect(inLive('#7'), findsOneWidget);
    });

    testWidgets('no ranked day shown and not charting now: the unavailable '
        'message, never an empty chart', (tester) async {
      final offChart = [
        for (var day = 1; day <= 9; day++)
          ChartDayStanding(
            dayStartLocal: DateTime(2026, 10, 27 + day),
            rank: day <= 2 ? 40 : null,
          ),
      ];
      await open(
        tester,
        allTime,
        (_, _) async => journeyWith(null, history: offChart),
      );
      expect(chart(allTime), findsNothing);
      expect(unavailable(allTime), findsOneWidget);
    });

    testWidgets('the marker pulses a few times, then rests', (tester) async {
      await open(
        tester,
        allTime,
        (_, _) async => journeyWith(2),
        settle: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue, reason: 'pulsing');

      await tester.pump(const Duration(seconds: 5));
      expect(tester.hasRunningAnimations, isFalse, reason: 'at rest');
    });

    testWidgets('Reduce Motion: no pulse', (tester) async {
      await open(
        tester,
        allTime,
        (_, _) async => journeyWith(2),
        reduceMotion: true,
        settle: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isFalse);
      expect(inLive('#2'), findsOneWidget);
    });

    testWidgets('new listening refreshes the live position in place', (
      tester,
    ) async {
      final changes = LibraryChangeSignal();
      var rank = 5;
      var loads = 0;
      await open(tester, allTime, (_, _) async {
        loads++;
        return journeyWith(rank);
      }, changes: changes);
      expect(inLive('#5'), findsOneWidget);

      rank = 1;
      changes.notify(LibraryChangeKind.listeningRecorded);
      await tester.pump(const Duration(milliseconds: 300));
      // While it reloads, the journey stays on screen.
      expect(chart(allTime), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();

      expect(loads, 2);
      expect(inLive('#1'), findsOneWidget);
      expect(find.text('#4'), findsOneWidget, reason: 'history unchanged');
    });
  });
}
