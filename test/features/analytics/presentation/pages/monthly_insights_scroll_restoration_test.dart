import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_behavior_metrics.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_period.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_summary.dart';
import 'package:sonus_next/features/analytics/application/models/analytics_time_window.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_album_insight_row.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_artist_insight_row.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_daily_listening.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_entity_listening_durations.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_listening_distribution.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_listening_insights.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_listening_insights_presentation_data.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_ranked_entity.dart';
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_track_insight_row.dart';
import 'package:sonus_next/features/analytics/application/services/monthly_insights/monthly_listening_insights_enrichment_service.dart';
import 'package:sonus_next/features/analytics/application/services/monthly_insights/monthly_listening_insights_service.dart';
import 'package:sonus_next/features/analytics/presentation/controllers/monthly_listening_insights_controller.dart';
import 'package:sonus_next/features/analytics/presentation/pages/monthly_listening_insights_page.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

// Regression (SN-48K1 K1-1): the daily timeline and the three ranking tables
// had no PageStorage slot of their own, so they shared the page's slot and
// reopened at the page's vertical offset, scrolling the rank, artwork and
// title columns off screen ("artwork vanished").
void main() {
  Finder horizontalScrollables() => find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.right,
  );

  ScrollableState page(WidgetTester tester) => tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byKey(
            const PageStorageKey<String>('monthly-insights-scroll'),
          ),
          matching: find.byType(Scrollable),
        )
        .first,
  );

  Future<void> scrollPageTo(WidgetTester tester, double offset) async {
    final position = page(tester).position;
    position.jumpTo(offset.clamp(0, position.maxScrollExtent));
    await tester.pumpAndSettle();
  }

  // The page's lazy extent grows as it scrolls; jump until it settles.
  Future<void> scrollPageToEnd(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      final position = page(tester).position;
      final end = position.maxScrollExtent;
      position.jumpTo(end);
      await tester.pumpAndSettle();
      if (page(tester).position.maxScrollExtent == end) break;
    }
  }

  testWidgets('every horizontal area opens at its first column after the '
      'page scrolls', (tester) async {
    await _pump(tester);

    await scrollPageToEnd(tester);

    final areas = horizontalScrollables();
    expect(areas, findsWidgets);

    for (final state in tester.stateList<ScrollableState>(areas)) {
      expect(state.position.maxScrollExtent, greaterThan(0));
      expect(state.position.pixels, 0);
    }

    // The identifying column of the table on screen is visible, not
    // scrolled off to the left.
    expect(
      find
          .descendant(
            of: find.byKey(
              const ValueKey<String>('monthly-insights-album-al1'),
            ),
            matching: find.text('Album 1'),
          )
          .hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('each area keeps its own horizontal position', (tester) async {
    await _pump(tester);
    await scrollPageToEnd(tester);

    final trackRow = find.byKey(
      const ValueKey<String>('monthly-insights-track-t1'),
    );
    final tracksTable = find
        .ancestor(of: trackRow, matching: horizontalScrollables())
        .first;
    tester.state<ScrollableState>(tracksTable).position.jumpTo(120);
    await tester.pumpAndSettle();

    // Scroll away so the tables are disposed, then back so they rebuild.
    await scrollPageTo(tester, 0);
    await scrollPageToEnd(tester);

    expect(
      tester
          .state<ScrollableState>(
            find
                .ancestor(of: trackRow, matching: horizontalScrollables())
                .first,
          )
          .position
          .pixels,
      120,
    );

    final albumRow = find.byKey(
      const ValueKey<String>('monthly-insights-album-al1'),
    );
    expect(
      tester
          .state<ScrollableState>(
            find
                .ancestor(of: albumRow, matching: horizontalScrollables())
                .first,
          )
          .position
          .pixels,
      0,
    );
  });
}

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(411, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final insights = _insights();
  final controller = MonthlyListeningInsightsController(
    service: _Loader(insights),
    enrichment: _Enricher(),
    now: () => DateTime(2026, 10, 20),
  );
  await controller.load();

  await tester.pumpWidget(
    ChangeNotifierProvider<MonthlyListeningInsightsController?>.value(
      value: controller,
      child: const MaterialApp(
        home: Scaffold(body: MonthlyListeningInsightsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MonthlyListeningInsights _insights() {
  final selected = DateTime(2026, 10);
  final window = AnalyticsTimeWindow(
    startUtc: selected.toUtc(),
    endUtc: DateTime(2026, 11).toUtc(),
  );

  AnalyticsSummary summary(AnalyticsTimeWindow w, int streams) =>
      AnalyticsSummary(
        period: AnalyticsPeriod.month,
        window: w,
        qualifiedStreamCount: streams,
        qualifiedListeningDuration: const Duration(hours: 5),
        distinctSongCount: 12,
        distinctArtistCount: 6,
        distinctAlbumCount: 5,
        firstQualifiedAt: w.startUtc,
        lastQualifiedAt: w.startUtc,
      );

  return MonthlyListeningInsights(
    selectedMonth: selected,
    previousMonth: DateTime(2026, 9),
    currentSummary: summary(window, 60),
    previousSummary: summary(
      AnalyticsTimeWindow(
        startUtc: DateTime(2026, 9).toUtc(),
        endUtc: selected.toUtc(),
      ),
      40,
    ),
    currentAudibleListeningDuration: const Duration(hours: 5),
    previousAudibleListeningDuration: const Duration(hours: 4),
    behavior: AnalyticsBehaviorMetrics(
      period: AnalyticsPeriod.month,
      window: window,
      sessionCount: 70,
      endedSessionCount: 70,
      completedSessionCount: 55,
      skippedSessionCount: 10,
      stoppedSessionCount: 5,
      replacedSessionCount: 0,
      interruptedSessionCount: 0,
      failedSessionCount: 0,
      firstSessionStartedAt: window.startUtc,
      lastSessionStartedAt: window.startUtc,
      activeQualifiedDayCount: 12,
      averageQualifiedStreamsPerActiveDay: 5,
      averageQualifiedStreamsPerCalendarDay: 60 / 31,
      peakDay: null,
    ),
    distribution: MonthlyListeningDistribution(
      days: [
        for (var day = 1; day <= 24; day += 2)
          MonthlyDailyListening(
            localDate: DateTime(2026, 10, day),
            streams: 3 + day % 4,
            listeningDuration: Duration(minutes: 20 + day),
          ),
      ],
      hours: const [],
    ),
    entityListeningDurations: const MonthlyEntityListeningDurations(
      songs: {},
      artists: {},
      albums: {},
    ),
    songs: const [],
    artists: const [],
    albums: const [],
  );
}

class _Loader implements MonthlyListeningInsightsLoader {
  const _Loader(this.result);

  final MonthlyListeningInsights result;

  @override
  Future<MonthlyListeningInsights> load({
    required DateTime referenceLocal,
  }) async => result;
}

class _Enricher implements MonthlyListeningInsightsEnricher {
  @override
  Future<MonthlyListeningInsightsPresentationData> enrich(
    MonthlyListeningInsights insights,
  ) async {
    MonthlyRankedEntity rank(String id, int r) => MonthlyRankedEntity(
      entityId: id,
      rank: r,
      previousRank: r,
      streams: 20 - r,
      previousStreams: 10,
      lifetimeStreams: 100,
    );

    return MonthlyListeningInsightsPresentationData(
      insights: insights,
      tracks: [
        for (var i = 1; i <= 3; i++)
          MonthlyTrackInsightRow(
            track: LibraryTrack(
              songId: 't$i',
              title: 'Track $i',
              artistId: 'a$i',
              artistName: 'Artist $i',
              albumId: 'al$i',
              albumTitle: 'Album $i',
              albumEditionId: 'e$i',
              albumEditionTitle: 'Standard',
              albumEditionType: AlbumEditionType.standard,
              trackNumber: 1,
              durationSeconds: 200,
              isSingle: false,
              featuredArtists: const [],
              dateAdded: DateTime(2026),
              isAvailable: true,
              isSongBlocked: false,
              filePath: '/music/t$i.mp3',
            ),
            title: 'Track $i',
            artistName: 'Artist $i',
            albumTitle: 'Album $i',
            ranking: rank('t$i', i),
            listeningDuration: const Duration(minutes: 30),
          ),
      ],
      artists: [
        for (var i = 1; i <= 3; i++)
          MonthlyArtistInsightRow(
            artist: LibraryArtist(
              artistId: 'a$i',
              name: 'Artist $i',
              albumCount: 1,
              songCount: 3,
              dateAdded: DateTime(2026),
            ),
            name: 'Artist $i',
            ranking: rank('a$i', i),
            listeningDuration: const Duration(minutes: 40),
          ),
      ],
      albums: [
        for (var i = 1; i <= 3; i++)
          MonthlyAlbumInsightRow(
            album: LibraryAlbum(
              albumId: 'al$i',
              title: 'Album $i',
              artistId: 'a$i',
              artistName: 'Artist $i',
              trackCount: 10,
              dateAdded: DateTime(2026),
            ),
            title: 'Album $i',
            artistName: 'Artist $i',
            ranking: rank('al$i', i),
            listeningDuration: const Duration(minutes: 50),
          ),
      ],
    );
  }
}
