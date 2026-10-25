import 'dart:async';

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
import 'package:sonus_next/features/analytics/application/models/monthly_insights/monthly_hourly_listening.dart';
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

void main() {
  group('MonthlyListeningInsightsPage', () {
    testWidgets('shows initializing state without controller', (tester) async {
      await tester.pumpWidget(_app(controller: null));

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-initializing')),
        findsOneWidget,
      );

      expect(find.text('Insights are getting ready'), findsOneWidget);
    });

    testWidgets('shows loading state while initial month loads', (
      tester,
    ) async {
      final loader = ControlledInsightsLoader();

      final controller = _controller(loader: loader);

      unawaited(controller.load());

      await tester.pumpWidget(_app(controller: controller));

      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-loading')),
        findsOneWidget,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state when initial load fails', (tester) async {
      final controller = _controller(loader: ErrorInsightsLoader());

      await controller.load();

      await tester.pumpWidget(_app(controller: controller));

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-error')),
        findsOneWidget,
      );

      expect(find.text('Monthly Insights could not be loaded'), findsOneWidget);

      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows empty month when there is no listening', (tester) async {
      final controller = _controller(
        loader: ImmediateInsightsLoader(
          result: _insights(
            month: DateTime(2026, 10),
            streamCount: 0,
            previousStreamCount: 0,
            audibleListening: Duration.zero,
            previousAudibleListening: Duration.zero,
          ),
        ),
      );

      await controller.load();

      await tester.pumpWidget(_app(controller: controller));

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-empty')),
        findsOneWidget,
      );

      expect(find.text('No listening this month'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-rankings')),
        findsNothing,
      );
    });

    testWidgets('renders headline and activity metrics', (tester) async {
      final insights = _insights(
        month: DateTime(2026, 10),
        streamCount: 12,
        previousStreamCount: 10,
        audibleListening: const Duration(hours: 3, minutes: 20),
        previousAudibleListening: const Duration(hours: 2),
      );

      final controller = _controller(
        loader: ImmediateInsightsLoader(result: insights),
      );

      await controller.load();

      await tester.pumpWidget(_app(controller: controller));

      expect(find.text('October 2026'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-headline-metrics')),
        findsOneWidget,
      );

      expect(find.text('12'), findsWidgets);

      expect(find.text('3h 20m'), findsOneWidget);

      expect(find.text('+20.0% vs previous month'), findsOneWidget);

      expect(find.text('+33.3% vs prev'), findsOneWidget);
      expect(find.text('+50.0% vs prev'), findsOneWidget);
      expect(find.text('0% vs prev'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-activity')),
        findsOneWidget,
      );

      expect(find.text('Oct 12 · 5 streams'), findsOneWidget);

      expect(find.text('8 PM · 1h 30m'), findsOneWidget);

      expect(find.text('Completion rate'), findsOneWidget);
      expect(find.text('66.7%'), findsOneWidget);

      expect(find.text('Skip rate'), findsOneWidget);
      expect(find.text('16.7%'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('monthly-insights-daily-timeline')),
        500,
        scrollable: _verticalScrollable(),
      );

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-daily-timeline')),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-day-2026-10-12')),
        findsOneWidget,
      );
    });

    testWidgets('disables next navigation on the current month', (
      tester,
    ) async {
      final controller = _controller(
        loader: ImmediateInsightsLoader(
          result: _insights(
            month: DateTime(2026, 10),
            streamCount: 1,
            previousStreamCount: 0,
          ),
        ),
      );

      await controller.load();

      await tester.pumpWidget(_app(controller: controller));

      final nextFinder = find.byKey(
        const ValueKey<String>('monthly-insights-next-month'),
      );

      expect(nextFinder, findsOneWidget);

      final button = tester.widget<IconButton>(nextFinder);

      expect(button.onPressed, isNull);
    });

    testWidgets('clears old month data while previous month loads', (
      tester,
    ) async {
      final loader = ControlledInsightsLoader();

      final controller = _controller(loader: loader);

      final octoberLoad = controller.load();

      loader.completeNext(
        _insights(
          month: DateTime(2026, 10),
          streamCount: 99,
          previousStreamCount: 50,
        ),
      );

      await octoberLoad;

      await tester.pumpWidget(_app(controller: controller));

      expect(find.text('99'), findsWidgets);

      await tester.tap(
        find.byKey(const ValueKey<String>('monthly-insights-previous-month')),
      );

      await tester.pump();

      expect(controller.selectedMonth, DateTime(2026, 9));

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-loading')),
        findsOneWidget,
      );

      expect(find.text('99'), findsNothing);

      loader.completeNext(
        _insights(
          month: DateTime(2026, 9),
          streamCount: 7,
          previousStreamCount: 5,
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('September 2026'), findsOneWidget);

      expect(find.text('7'), findsWidgets);
    });

    testWidgets('renders ranked track artist and album tables', (tester) async {
      final insights = _insights(
        month: DateTime(2026, 10),
        streamCount: 20,
        previousStreamCount: 10,
      );

      final presentation = _presentationData(
        insights: insights,
        tracks: [
          _trackRow(
            id: 'song-1',
            title: 'First Track',
            artistName: 'First Artist',
            rank: 1,
            previousRank: 3,
            streams: 8,
            previousStreams: 4,
            lifetimeStreams: 42,
            listeningDuration: const Duration(minutes: 32),
          ),
          _trackRow(
            id: 'song-2',
            title: 'New Track',
            artistName: 'Second Artist',
            rank: 2,
            previousRank: null,
            streams: 5,
            previousStreams: 0,
            lifetimeStreams: 5,
            listeningDuration: const Duration(minutes: 20),
          ),
        ],
        artists: [
          _artistRow(
            id: 'artist-1',
            name: 'First Artist',
            rank: 1,
            previousRank: 2,
            streams: 12,
            previousStreams: 8,
            lifetimeStreams: 88,
          ),
        ],
        albums: [
          _albumRow(
            id: 'album-1',
            title: 'First Album',
            artistName: 'First Artist',
            rank: 1,
            previousRank: 1,
            streams: 10,
            previousStreams: 9,
            lifetimeStreams: 70,
          ),
        ],
      );

      final controller = _controller(
        loader: ImmediateInsightsLoader(result: insights),
        enricher: StaticInsightsEnricher(presentation),
      );

      await controller.load();

      await tester.pumpWidget(_app(controller: controller));

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('monthly-insights-track-song-1')),
        500,
        scrollable: _verticalScrollable(),
      );

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-track-song-1')),
        findsOneWidget,
      );

      expect(find.text('First Track'), findsOneWidget);

      expect(find.text('New Track'), findsOneWidget);

      expect(find.text('NEW'), findsWidgets);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('monthly-insights-artist-artist-1')),
        500,
        scrollable: _verticalScrollable(),
      );

      expect(find.text('First Artist'), findsWidgets);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('monthly-insights-album-album-1')),
        500,
        scrollable: _verticalScrollable(),
      );

      expect(find.text('First Album'), findsOneWidget);
    });

    testWidgets('keeps blocked and unavailable tracks visible', (tester) async {
      final insights = _insights(
        month: DateTime(2026, 10),
        streamCount: 10,
        previousStreamCount: 5,
      );

      final presentation = _presentationData(
        insights: insights,
        tracks: [
          _trackRow(
            id: 'blocked-song',
            title: 'Blocked Song',
            artistName: 'Artist A',
            rank: 1,
            previousRank: 1,
            streams: 6,
            previousStreams: 4,
            lifetimeStreams: 30,
            blocked: true,
          ),
          _trackRow(
            id: 'missing-song',
            title: 'Unavailable Song',
            artistName: 'Artist B',
            rank: 2,
            previousRank: 2,
            streams: 4,
            previousStreams: 1,
            lifetimeStreams: 12,
            available: false,
          ),
        ],
      );

      final controller = _controller(
        loader: ImmediateInsightsLoader(result: insights),
        enricher: StaticInsightsEnricher(presentation),
      );

      await controller.load();

      await tester.pumpWidget(_app(controller: controller));

      await tester.scrollUntilVisible(
        find.byKey(
          const ValueKey<String>('monthly-insights-track-blocked-song'),
        ),
        500,
        scrollable: _verticalScrollable(),
      );

      expect(find.text('Blocked Song'), findsOneWidget);

      expect(find.text('BLACKLISTED'), findsOneWidget);

      expect(find.text('Unavailable Song'), findsOneWidget);

      expect(find.text('UNAVAILABLE'), findsOneWidget);
    });

    testWidgets('limits rendered track rankings to top 25', (tester) async {
      final insights = _insights(
        month: DateTime(2026, 10),
        streamCount: 100,
        previousStreamCount: 80,
      );

      final tracks = [
        for (var index = 1; index <= 26; index++)
          _trackRow(
            id: 'song-$index',
            title: 'Track $index',
            artistName: 'Artist $index',
            rank: index,
            previousRank: index,
            streams: 27 - index,
            previousStreams: 20 - (index ~/ 2),
            lifetimeStreams: 100 + index,
          ),
      ];

      final controller = _controller(
        loader: ImmediateInsightsLoader(result: insights),
        enricher: StaticInsightsEnricher(
          _presentationData(insights: insights, tracks: tracks),
        ),
      );

      await controller.load();

      await tester.pumpWidget(_app(controller: controller));

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('monthly-insights-track-song-25')),
        1000,
        scrollable: _verticalScrollable(),
      );

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-track-song-25')),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey<String>('monthly-insights-track-song-26')),
        findsNothing,
      );

      expect(find.text('Top 25 of 26'), findsOneWidget);
    });

    // Characterization (SN-48K1): navigation and ranking order the redesign
    // must keep.
    testWidgets('previous month loads the month before', (tester) async {
      final loader = _RecordingInsightsLoader();
      final controller = _controller(loader: loader);

      await controller.load();
      await tester.pumpWidget(_app(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('October 2026'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('monthly-insights-previous-month')),
      );
      await tester.pumpAndSettle();

      expect(find.text('September 2026'), findsOneWidget);
      expect(loader.requestedMonths, [DateTime(2026, 10), DateTime(2026, 9)]);
    });

    testWidgets('ranked rows keep their rank order', (tester) async {
      final insights = _insights(
        month: DateTime(2026, 10),
        streamCount: 20,
        previousStreamCount: 10,
      );
      final controller = _controller(
        loader: ImmediateInsightsLoader(result: insights),
        enricher: StaticInsightsEnricher(
          _presentationData(
            insights: insights,
            tracks: [
              for (var rank = 1; rank <= 3; rank++)
                _trackRow(
                  id: 'song-$rank',
                  title: 'Track $rank',
                  artistName: 'Artist',
                  rank: rank,
                  previousRank: rank,
                  streams: 10 - rank,
                  previousStreams: 5,
                  lifetimeStreams: 50,
                ),
            ],
          ),
        ),
      );

      await controller.load();
      await tester.pumpWidget(_app(controller: controller));

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('monthly-insights-track-song-3')),
        500,
        scrollable: _verticalScrollable(),
      );

      double top(String id) => tester
          .getTopLeft(
            find.byKey(ValueKey<String>('monthly-insights-track-$id')),
          )
          .dy;

      expect(top('song-1'), lessThan(top('song-2')));
      expect(top('song-2'), lessThan(top('song-3')));
    });
  });
}

class _RecordingInsightsLoader implements MonthlyListeningInsightsLoader {
  final List<DateTime> requestedMonths = [];

  @override
  Future<MonthlyListeningInsights> load({
    required DateTime referenceLocal,
  }) async {
    requestedMonths.add(referenceLocal);

    return _insights(
      month: referenceLocal,
      streamCount: 12,
      previousStreamCount: 6,
    );
  }
}

Finder _verticalScrollable() {
  return find
      .descendant(
        of: find.byKey(const PageStorageKey<String>('monthly-insights-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
}

Widget _app({required MonthlyListeningInsightsController? controller}) {
  return ChangeNotifierProvider<MonthlyListeningInsightsController?>.value(
    value: controller,
    child: const MaterialApp(
      home: Scaffold(body: MonthlyListeningInsightsPage()),
    ),
  );
}

MonthlyListeningInsightsController _controller({
  required MonthlyListeningInsightsLoader loader,
  MonthlyListeningInsightsEnricher? enricher,
}) {
  return MonthlyListeningInsightsController(
    service: loader,
    enrichment: enricher,
    now: () => DateTime(2026, 10, 6),
  );
}

MonthlyListeningInsights _insights({
  required DateTime month,
  required int streamCount,
  required int previousStreamCount,
  Duration audibleListening = const Duration(hours: 2),
  Duration previousAudibleListening = const Duration(hours: 1),
}) {
  final selected = DateTime(month.year, month.month);

  final previous = DateTime(selected.year, selected.month - 1);

  final currentWindow = AnalyticsTimeWindow(
    startUtc: selected.toUtc(),
    endUtc: DateTime(selected.year, selected.month + 1).toUtc(),
  );

  final previousWindow = AnalyticsTimeWindow(
    startUtc: previous.toUtc(),
    endUtc: selected.toUtc(),
  );

  return MonthlyListeningInsights(
    selectedMonth: selected,
    previousMonth: previous,
    currentSummary: AnalyticsSummary(
      period: AnalyticsPeriod.month,
      window: currentWindow,
      qualifiedStreamCount: streamCount,
      qualifiedListeningDuration: audibleListening,
      distinctSongCount: streamCount == 0 ? 0 : 4,
      distinctArtistCount: streamCount == 0 ? 0 : 3,
      distinctAlbumCount: streamCount == 0 ? 0 : 2,
      firstQualifiedAt: streamCount == 0 ? null : selected.toUtc(),
      lastQualifiedAt: streamCount == 0
          ? null
          : selected.add(const Duration(days: 12)).toUtc(),
    ),
    previousSummary: AnalyticsSummary(
      period: AnalyticsPeriod.month,
      window: previousWindow,
      qualifiedStreamCount: previousStreamCount,
      qualifiedListeningDuration: previousAudibleListening,
      distinctSongCount: previousStreamCount == 0 ? 0 : 3,
      distinctArtistCount: previousStreamCount == 0 ? 0 : 2,
      distinctAlbumCount: previousStreamCount == 0 ? 0 : 2,
      firstQualifiedAt: previousStreamCount == 0 ? null : previous.toUtc(),
      lastQualifiedAt: previousStreamCount == 0
          ? null
          : previous.add(const Duration(days: 10)).toUtc(),
    ),
    currentAudibleListeningDuration: audibleListening,
    previousAudibleListeningDuration: previousAudibleListening,
    behavior: AnalyticsBehaviorMetrics(
      period: AnalyticsPeriod.month,
      window: currentWindow,
      sessionCount: streamCount,
      endedSessionCount: streamCount,
      completedSessionCount: streamCount == 0 ? 0 : 8,
      skippedSessionCount: streamCount == 0 ? 0 : 2,
      stoppedSessionCount: 0,
      replacedSessionCount: 0,
      interruptedSessionCount: 0,
      failedSessionCount: 0,
      firstSessionStartedAt: streamCount == 0 ? null : selected.toUtc(),
      lastSessionStartedAt: streamCount == 0
          ? null
          : selected.add(const Duration(days: 12)).toUtc(),
      activeQualifiedDayCount: streamCount == 0 ? 0 : 4,
      averageQualifiedStreamsPerActiveDay: streamCount == 0
          ? 0
          : streamCount / 4,
      averageQualifiedStreamsPerCalendarDay: streamCount == 0
          ? 0
          : streamCount / 31,
      peakDay: null,
    ),
    distribution: MonthlyListeningDistribution(
      days: streamCount == 0
          ? const []
          : [
              MonthlyDailyListening(
                localDate: DateTime(2026, 10, 12),
                streams: 5,
                listeningDuration: const Duration(hours: 1),
              ),
            ],
      hours: streamCount == 0
          ? const []
          : const [
              MonthlyHourlyListening(
                hour: 20,
                streams: 4,
                listeningDuration: Duration(hours: 1, minutes: 30),
              ),
            ],
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

MonthlyListeningInsightsPresentationData _presentationData({
  required MonthlyListeningInsights insights,
  List<MonthlyTrackInsightRow> tracks = const [],
  List<MonthlyArtistInsightRow> artists = const [],
  List<MonthlyAlbumInsightRow> albums = const [],
}) {
  return MonthlyListeningInsightsPresentationData(
    insights: insights,
    tracks: tracks,
    artists: artists,
    albums: albums,
  );
}

MonthlyTrackInsightRow _trackRow({
  required String id,
  required String title,
  required String artistName,
  required int rank,
  required int? previousRank,
  required int streams,
  required int previousStreams,
  required int lifetimeStreams,
  Duration listeningDuration = const Duration(minutes: 10),
  bool blocked = false,
  bool available = true,
}) {
  return MonthlyTrackInsightRow(
    track: LibraryTrack(
      songId: id,
      title: title,
      artistId: 'artist-$id',
      artistName: artistName,
      albumId: 'album-$id',
      albumTitle: 'Album $id',
      albumEditionId: 'edition-$id',
      albumEditionTitle: 'Standard',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: 1,
      durationSeconds: 240,
      isSingle: false,
      featuredArtists: const [],
      dateAdded: DateTime(2026, 1, 1),
      isAvailable: available,
      isSongBlocked: blocked,
      filePath: available ? 'C:\\music\\$id.mp3' : null,
    ),
    title: title,
    artistName: artistName,
    albumTitle: 'Album $id',

    ranking: MonthlyRankedEntity(
      entityId: id,
      rank: rank,
      previousRank: previousRank,
      streams: streams,
      previousStreams: previousStreams,
      lifetimeStreams: lifetimeStreams,
    ),
    listeningDuration: listeningDuration,
  );
}

MonthlyArtistInsightRow _artistRow({
  required String id,
  required String name,
  required int rank,
  required int? previousRank,
  required int streams,
  required int previousStreams,
  required int lifetimeStreams,
}) {
  return MonthlyArtistInsightRow(
    artist: LibraryArtist(
      artistId: id,
      name: name,
      albumCount: 2,
      songCount: 7,
      dateAdded: DateTime(2026, 1, 1),
    ),
    name: name,

    ranking: MonthlyRankedEntity(
      entityId: id,
      rank: rank,
      previousRank: previousRank,
      streams: streams,
      previousStreams: previousStreams,
      lifetimeStreams: lifetimeStreams,
    ),
    listeningDuration: const Duration(hours: 1),
  );
}

MonthlyAlbumInsightRow _albumRow({
  required String id,
  required String title,
  required String artistName,
  required int rank,
  required int? previousRank,
  required int streams,
  required int previousStreams,
  required int lifetimeStreams,
}) {
  return MonthlyAlbumInsightRow(
    album: LibraryAlbum(
      albumId: id,
      title: title,
      artistId: 'artist-$id',
      artistName: artistName,
      trackCount: 10,
      dateAdded: DateTime(2026, 1, 1),
      primaryEditionId: 'edition-$id',
      primaryEditionTitle: 'Standard',
      primaryEditionType: AlbumEditionType.standard,
    ),
    title: title,
    artistName: artistName,

    ranking: MonthlyRankedEntity(
      entityId: id,
      rank: rank,
      previousRank: previousRank,
      streams: streams,
      previousStreams: previousStreams,
      lifetimeStreams: lifetimeStreams,
    ),
    listeningDuration: const Duration(minutes: 50),
  );
}

class ImmediateInsightsLoader implements MonthlyListeningInsightsLoader {
  ImmediateInsightsLoader({required this.result});

  final MonthlyListeningInsights result;

  @override
  Future<MonthlyListeningInsights> load({
    required DateTime referenceLocal,
  }) async {
    return result;
  }
}

class ErrorInsightsLoader implements MonthlyListeningInsightsLoader {
  @override
  Future<MonthlyListeningInsights> load({required DateTime referenceLocal}) {
    throw StateError('test load failure');
  }
}

class ControlledInsightsLoader implements MonthlyListeningInsightsLoader {
  final List<Completer<MonthlyListeningInsights>> _completers = [];

  @override
  Future<MonthlyListeningInsights> load({required DateTime referenceLocal}) {
    final completer = Completer<MonthlyListeningInsights>();

    _completers.add(completer);

    return completer.future;
  }

  void completeNext(MonthlyListeningInsights insights) {
    final completer = _completers.firstWhere(
      (candidate) => !candidate.isCompleted,
    );

    completer.complete(insights);
  }
}

class StaticInsightsEnricher implements MonthlyListeningInsightsEnricher {
  const StaticInsightsEnricher(this.data);

  final MonthlyListeningInsightsPresentationData data;

  @override
  Future<MonthlyListeningInsightsPresentationData> enrich(
    MonthlyListeningInsights insights,
  ) async {
    return MonthlyListeningInsightsPresentationData(
      insights: insights,
      tracks: data.tracks,
      artists: data.artists,
      albums: data.albums,
    );
  }
}
