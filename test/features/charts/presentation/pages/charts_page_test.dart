import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_album_edition.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/pages/album_profile_page.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/application/services/this_week_chart_service.dart';
import 'package:sonus_next/features/charts/domain/entities/all_time_chart.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/application/services/chart_moment_feed_pager.dart';
import 'package:sonus_next/features/charts/application/services/moments_last_seen_store.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/domain/models/chart_week.dart';
import 'package:sonus_next/features/charts/domain/services/chart_week_resolver.dart';
import 'package:sonus_next/features/charts/presentation/controllers/charts_controller.dart';
import 'package:sonus_next/features/charts/presentation/news/moment_post_card.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_category.dart';
import 'package:sonus_next/features/charts/presentation/editorial/moment_publisher.dart';
import 'package:sonus_next/features/charts/presentation/pages/charts_page.dart';
import 'package:sonus_next/features/charts/presentation/widgets/chart_board_rows.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

import '../../support/moment_page_fakes.dart';
import 'package:sonus_next/features/song_stats/application/song_stats_models.dart';
import 'package:sonus_next/features/song_stats/application/song_stats_service.dart';

/// Since the SN-50 device polish every position, #1–10 included, is a
/// compact row; its full card is one tap away.
Future<void> _showDetails(WidgetTester tester, String id) async {
  final button = find.byKey(ValueKey<String>('charts-row-expand-$id'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders branded Hot 100 controls and the career standings', (
    tester,
  ) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    expect(find.text('SONUS'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('charts-title')),
        matching: find.text('Hot 100'),
        matchRoot: true,
      ),
      findsOneWidget,
    );

    expect(find.text('Songs'), findsWidgets);
    expect(find.text('Albums & EPs'), findsOneWidget);

    expect(find.text('Top 10'), findsOneWidget);
    expect(find.text('Top 25'), findsOneWidget);
    expect(find.text('Top 50'), findsOneWidget);
    expect(find.text('Top 75'), findsOneWidget);
    expect(find.text('Top 100'), findsOneWidget);
    // #101–200 have their own board instead of a Top 200 size.
    expect(find.text('Top 200'), findsNothing);
    expect(find.text('Bubbling Under'), findsOneWidget);

    expect(find.text('CURRENT'), findsOneWidget);
    expect(find.text('Career standings'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    expect(find.textContaining('Last week'), findsNothing);
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Artist 1 • Album 1'), findsOneWidget);
    await _showDetails(tester, 'songs_1');
    expect(
      find.byKey(const ValueKey<String>('charts-spotlight-songs_1')),
      findsOneWidget,
    );
    expect(find.text('TOTAL STREAMS'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('CAREER PEAK'), findsOneWidget);
    expect(find.text('#1'), findsWidgets);
    expect(find.text('WEEKLY CHANGE'), findsOneWidget);
    expect(find.text('WEEKS IN TOP 3'), findsOneWidget);
    // SN-49: the explanation is one tap away, not a paragraph on the page.
    expect(find.textContaining('RE-ENTRY: back'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('charts-info-button')),
      findsOneWidget,
    );
  });

  testWidgets('older week control shows finalized chart', (tester) async {
    final controller = await _controller(
      history: [
        _snapshot(
          id: 'historical',
          start: DateTime.utc(2026, 9, 20),
          finalized: true,
        ),
      ],
    );

    await _pumpPage(tester, controller);

    await tester.tap(find.byKey(const ValueKey<String>('charts-older-week')));

    await tester.pump();

    expect(find.text('FINAL'), findsOneWidget);
    expect(find.text('CURRENT'), findsNothing);
  });

  testWidgets('album segment switches chart type', (tester) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    await tester.tap(find.text('Albums & EPs'));
    await tester.pumpAndSettle();

    expect(controller.chartType, ChartType.albums);
  });

  testWidgets('empty chart renders empty state', (tester) async {
    final controller = await _controller(
      live: ChartSnapshot(
        id: 'empty',
        chartType: ChartType.songs,
        weekStartUtc: DateTime.utc(2026, 9, 27),
        weekEndUtc: DateTime.utc(2026, 10, 4),
        entries: const [],
      ),
    );

    await _pumpPage(tester, controller);

    expect(find.text('No chart entries yet'), findsOneWidget);
  });

  // Charts 2.0 C4: a tap opens Song Stats; the song's actions stay one
  // long press away.
  testWidgets('live song tap opens Song Stats', (tester) async {
    final controller = await _controller();
    final stats = _FakeSongStatsLoader();

    await _pumpPage(tester, controller, songStats: stats);

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('song-stats-page')), findsOne);
    expect(stats.requested, ['songs_1']);
    expect(find.text('Chart History'), findsOneWidget);
  });

  testWidgets('a Bubbling Under row opens Song Stats', (tester) async {
    final controller = await _controller(live: _rankedSnapshot(130));
    final stats = _FakeSongStatsLoader();

    await _pumpPage(tester, controller, songStats: stats);
    await controller.selectBoard(ChartBoard.extended);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-row-songs_101')),
    );
    await tester.pumpAndSettle();

    expect(stats.requested, ['songs_101']);
    expect(find.byKey(const ValueKey<String>('song-stats-page')), findsOne);
  });

  testWidgets('live song long press opens chart track actions', (tester) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    await tester.longPress(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Add to playlist'), findsOneWidget);
    expect(find.text('Go to album'), findsOneWidget);
    expect(find.text('Go to artist'), findsOneWidget);
  });

  // SN-50 E-Q8: a finalized week's row opens the song that still exists;
  // the row keeps what was stored for that week.
  testWidgets('historical song row opens the living song', (tester) async {
    final controller = await _controller(
      history: [
        _snapshot(
          id: 'historical',
          start: DateTime.utc(2026, 9, 20),
          finalized: true,
          title: 'Song 1 (stored title)',
        ),
      ],
    );

    await _pumpPage(tester, controller);

    controller.showOlderWeek();
    await tester.pump();

    expect(find.text('Song 1 (stored title)'), findsOneWidget);
    expect(find.text('HISTORICAL'), findsNothing);

    await tester.longPress(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
  });

  // SN-50 E-Q8: opening a finalized week's song never touches what is
  // playing; only an explicit Play on Song Stats does (Charts 2.0 C4).
  testWidgets('historical song row leaves the queue alone until Play is '
      'chosen', (tester) async {
    final engine = _RecordingPlaybackEngine();
    final controller = await _controller(
      history: [
        _snapshot(
          id: 'historical',
          start: DateTime.utc(2026, 9, 20),
          finalized: true,
        ),
      ],
    );

    await _pumpPage(
      tester,
      controller,
      playback: PlaybackCoordinator(engine: engine),
      songStats: _FakeSongStatsLoader(track: _track()),
    );
    controller.showOlderWeek();
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('song-stats-page')), findsOne);
    expect(engine.calls, isEmpty);

    await tester.tap(find.byKey(const ValueKey<String>('song-stats-play')));
    await tester.pumpAndSettle();

    expect(engine.calls, ['loadQueue']);
  });

  // SN-50 R1: verified listening stays in Career standings when the song is
  // no longer in this library; it shows as heard and cannot be played.
  testWidgets('a song no longer in the library stays in the standings, '
      'marked and not playable', (tester) async {
    final engine = _RecordingPlaybackEngine();
    final controller = await _controller(tracks: const []);

    await _pumpPage(
      tester,
      controller,
      playback: PlaybackCoordinator(engine: engine),
    );

    expect(controller.isViewingAllTime, isTrue);
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.textContaining('HISTORICAL · '), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsNothing);
    expect(engine.calls, isEmpty);
  });

  testWidgets('historical album row opens the living release', (tester) async {
    final controller = await _controller(
      history: [
        _snapshot(
          id: 'historical-album',
          start: DateTime.utc(2026, 9, 20),
          chartType: ChartType.albums,
          finalized: true,
        ),
      ],
    );

    await _pumpPage(tester, controller);
    await controller.selectChartType(ChartType.albums);
    controller.showOlderWeek();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-albums_1')),
    );
    await tester.pumpAndSettle();

    final page = tester.widget<AlbumProfilePage>(find.byType(AlbumProfilePage));
    expect(page.albumId, 'albums_1');
    expect(page.initialEditionId, isNull);
  });
  testWidgets('blocked live song stays visible but is not interactive', (
    tester,
  ) async {
    final controller = await _controller(tracks: [_track(isBlocked: true)]);

    await _pumpPage(tester, controller);

    expect(find.text('Song 1'), findsOneWidget);
    expect(find.textContaining('BLACKLISTED · '), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsNothing);
    expect(find.text('Add to queue'), findsNothing);
  });

  testWidgets('unavailable live song stays visible but is not interactive', (
    tester,
  ) async {
    final controller = await _controller(
      tracks: [_track(isAvailable: false, filePath: null)],
    );

    await _pumpPage(tester, controller);

    expect(find.text('Song 1'), findsOneWidget);
    expect(find.textContaining('UNAVAILABLE · '), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsNothing);
    expect(find.text('Add to queue'), findsNothing);
  });

  testWidgets('deleted historical song still renders snapshot identity', (
    tester,
  ) async {
    final controller = await _controller(
      tracks: const [],
      history: [
        _snapshot(
          id: 'historical-deleted-song',
          start: DateTime.utc(2026, 9, 20),
          finalized: true,
        ),
      ],
    );

    await _pumpPage(tester, controller);

    controller.showOlderWeek();
    await tester.pump();

    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('HISTORICAL · Artist 1 • Album 1'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsNothing);
  });

  testWidgets('deleted historical album still renders snapshot identity', (
    tester,
  ) async {
    final historicalAlbum = _snapshot(
      id: 'historical-deleted-album',
      start: DateTime.utc(2026, 9, 20),
      chartType: ChartType.albums,
      finalized: true,
    );

    final controller = await _controller(
      albums: const [],
      history: [historicalAlbum],
    );

    await _pumpPage(tester, controller);

    await controller.selectChartType(ChartType.albums);
    controller.showOlderWeek();
    await tester.pump();

    expect(find.text('Album 1'), findsOneWidget);
    expect(find.textContaining('Artist 1'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-albums_1')),
    );

    await tester.pumpAndSettle();

    expect(find.byType(AlbumProfilePage), findsNothing);
  });

  testWidgets('live album row opens album profile', (tester) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    await controller.selectChartType(ChartType.albums);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-albums_1')),
    );

    await tester.pumpAndSettle();

    expect(find.byType(AlbumProfilePage), findsOneWidget);
  });
  testWidgets('the information sheet explains the chart', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = await _controller();

    await _pumpPage(tester, controller);
    // The chart has no notice above it.
    expect(find.textContaining('are Sonus Bubbling Under'), findsNothing);

    expect(find.byTooltip('About the Sonus Hot 100'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('charts-info-button')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey<String>('charts-info-sheet'));
    expect(sheet, findsOneWidget);
    for (final heading in [
      'About the Sonus Hot 100',
      'Positions',
      'Streams',
      'Career standings and weekly charts',
      'NEW and RE-ENTRY',
      'Movement',
      'Ties',
      'Chart history',
      'Percentage change',
      'Weeks in a zone',
    ]) {
      await tester.scrollUntilVisible(
        find.text(heading),
        200,
        scrollable: find.descendant(
          of: sheet,
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        tester.getSemantics(find.text(heading)),
        matchesSemantics(label: heading, isHeader: true),
      );
    }
    final sheetScroll = find.descendant(
      of: sheet,
      matching: find.byType(Scrollable),
    );
    for (final text in [
      'whoever reached the total first',
      'start of this chart week',
      'no minimum time away',
      'Sonus Bubbling Under, shown at',
    ]) {
      await tester.scrollUntilVisible(
        find.textContaining(text),
        -200,
        scrollable: sheetScroll,
      );
      expect(find.textContaining(text), findsOne, reason: text);
    }
    semantics.dispose();
  });

  testWidgets('on a final week the information sheet explains that week', (
    tester,
  ) async {
    final controller = await _controller(
      history: [
        _snapshot(
          id: 'historical',
          start: DateTime.utc(2026, 9, 20),
          finalized: true,
        ),
      ],
    );

    await _pumpPage(tester, controller);
    controller.showOlderWeek();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('charts-info-button')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey<String>('charts-info-sheet'));
    final scrollable = find.descendant(
      of: sheet,
      matching: find.byType(Scrollable),
    );
    for (final text in [
      'previous final weekly chart',
      'first week in any weekly Top 100',
      'most recent qualifying stream',
    ]) {
      await tester.scrollUntilVisible(
        find.textContaining(text),
        200,
        scrollable: scrollable,
      );
      expect(find.textContaining(text), findsOneWidget, reason: text);
    }
    expect(find.textContaining('start of this chart week'), findsNothing);
    expect(find.text('Percentage change'), findsNothing);
  });

  // SN-50 §0.4 / E-Q15A: the retired period words appear nowhere on the
  // default view, in either chart or in its information sheet.
  testWidgets('the default view never says "all time"', (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = await _controller(
      live: _rankedSnapshot(102),
      history: [_finalizedWeek(DateTime.utc(2026, 9, 20), ranks: 12)],
    );
    final banned = RegExp(r'all[\s-]*time', caseSensitive: false);

    void expectClean(String where) {
      for (final element in find.byType(RichText).evaluate()) {
        final text = (element.widget as RichText).text.toPlainText();
        expect(banned.hasMatch(text), isFalse, reason: '$where: "$text"');
      }
      for (final element in find.byType(Semantics).evaluate()) {
        final label = (element.widget as Semantics).properties.label ?? '';
        expect(banned.hasMatch(label), isFalse, reason: '$where: "$label"');
      }
      for (final element in find.byType(Tooltip).evaluate()) {
        final message = (element.widget as Tooltip).message ?? '';
        expect(banned.hasMatch(message), isFalse, reason: where);
      }
    }

    await _pumpPage(tester, controller, size: const Size(800, 20000));
    expectClean('songs');
    await tester.tap(find.text('Bubbling Under'));
    await tester.pumpAndSettle();
    expectClean('songs bubbling under');

    await tester.tap(find.byKey(const ValueKey<String>('charts-info-button')));
    await tester.pumpAndSettle();
    expectClean('songs information');
    Navigator.of(tester.element(find.byType(ChartsPage))).pop();
    await tester.pumpAndSettle();

    await controller.selectChartType(ChartType.albums);
    await tester.pumpAndSettle();
    expectClean('albums');
    semantics.dispose();
  });

  testWidgets('standings cards show longevity from final weeks', (
    tester,
  ) async {
    final controller = await _controller(
      live: _rankedSnapshot(3),
      history: [
        _finalizedWeek(DateTime.utc(2026, 9, 20), ranks: 3),
        _finalizedWeek(DateTime.utc(2026, 9, 13), ranks: 3),
      ],
    );

    await _pumpPage(tester, controller);
    await _showDetails(tester, 'songs_1');

    final spotlight = find.byKey(
      const ValueKey<String>('charts-longevity-songs_1'),
    );
    expect(
      find.descendant(of: spotlight, matching: find.text('2 weeks at #1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: spotlight, matching: find.text('2 official weeks')),
      findsOneWidget,
    );
  });

  testWidgets('a final week shows last week in Bubbling Under as context', (
    tester,
  ) async {
    final previous = DateTime(2026, 9, 13).toUtc();
    final current = DateTime(2026, 9, 20).toUtc();
    final controller = await _controller(
      history: [
        ChartSnapshot(
          id: 'current',
          chartType: ChartType.songs,
          weekStartUtc: current,
          weekEndUtc: DateTime(2026, 9, 27).toUtc(),
          finalizedAt: DateTime(2026, 9, 27).toUtc(),
          entries: [_weeklyEntry('songs_1', rank: 80)],
        ),
        ChartSnapshot(
          id: 'previous',
          chartType: ChartType.songs,
          weekStartUtc: previous,
          weekEndUtc: current,
          finalizedAt: current,
          entries: [_weeklyEntry('songs_1', rank: 150)],
        ),
      ],
    );

    await _pumpPage(tester, controller);
    controller.showOlderWeek();
    await tester.pumpAndSettle();

    expect(find.text('September 20–26, 2026'), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);
    // #80 is a compact row; its full card opens in place of the row.
    await tester.tap(
      find.byKey(const ValueKey<String>('charts-row-expand-songs_1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Last week #150 (Bubbling Under)'), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('Debut #80 · Sep 20, 2026'), findsOneWidget);
  });

  group('Deluxe-first album standings', () {
    LibraryAlbumEdition deluxe(
      String id, {
      String? title,
      String? artworkPath,
      DateTime? releaseDate,
    }) => LibraryAlbumEdition(
      editionId: id,
      albumId: 'albums_1',
      title: title ?? 'Album 1 ($id)',
      type: AlbumEditionType.deluxe,
      isPrimary: false,
      releaseDate: releaseDate,
      artworkPath: artworkPath,
      dateAdded: DateTime.utc(2026, 9, 2),
    );

    testWidgets('shows the Deluxe and opens it', (tester) async {
      final controller = await _controller(
        deluxeEditions: () async => [
          deluxe('deluxe_a', releaseDate: DateTime.utc(2024, 5, 1)),
          deluxe('deluxe_b', releaseDate: DateTime.utc(2025, 5, 1)),
        ],
      );

      await _pumpPage(tester, controller);
      await controller.selectChartType(ChartType.albums);
      await tester.pumpAndSettle();

      expect(find.text('Album 1 (deluxe_b)'), findsOneWidget);
      expect(find.text('Album 1'), findsNothing);
      // One combined position and stream total for the release.
      await _showDetails(tester, 'albums_1');
      expect(find.text('12'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('charts-entry-albums_1')),
      );
      await tester.pumpAndSettle();

      final page = tester.widget<AlbumProfilePage>(
        find.byType(AlbumProfilePage),
      );
      expect(page.initialEditionId, 'deluxe_b');
    });

    testWidgets('final weeks keep their stored title', (tester) async {
      final controller = await _controller(
        history: [
          _snapshot(
            id: 'historical-album',
            start: DateTime.utc(2026, 9, 20),
            chartType: ChartType.albums,
            finalized: true,
          ),
        ],
        deluxeEditions: () async => [deluxe('deluxe_a')],
      );

      await _pumpPage(tester, controller);
      await controller.selectChartType(ChartType.albums);
      controller.showOlderWeek();
      await tester.pumpAndSettle();

      expect(find.text('Album 1'), findsOneWidget);
      expect(find.text('Album 1 (deluxe_a)'), findsNothing);
    });

    testWidgets('a failing edition read falls back to the primary', (
      tester,
    ) async {
      final controller = await _controller(
        deluxeEditions: () async => throw StateError('offline'),
      );

      await _pumpPage(tester, controller);
      await controller.selectChartType(ChartType.albums);
      await tester.pumpAndSettle();

      expect(find.text('Album 1'), findsOneWidget);
    });
  });

  group('SN-50 BUG-02: song versions on the chart', () {
    final remix = _track(versionLabel: 'Remix', featured: const ['Artist A']);

    testWidgets('the current standings show the version and its credits', (
      tester,
    ) async {
      final controller = await _controller(tracks: [remix]);

      await _pumpPage(tester, controller);

      expect(find.text('Song 1 (Remix)'), findsOneWidget);
      expect(find.text('Artist 1 Ft. Artist A • Album 1'), findsOneWidget);
    });

    testWidgets('final weeks keep their stored title and artist', (
      tester,
    ) async {
      final controller = await _controller(
        tracks: [remix],
        history: [
          _snapshot(
            id: 'historical-songs',
            start: DateTime.utc(2026, 9, 20),
            finalized: true,
          ),
        ],
      );

      await _pumpPage(tester, controller);
      controller.showOlderWeek();
      await tester.pumpAndSettle();

      expect(find.text('Song 1'), findsOneWidget);
      expect(find.text('Artist 1 • Album 1'), findsOneWidget);
      expect(find.textContaining('(Remix)'), findsNothing);
      expect(find.textContaining('Artist A'), findsNothing);
    });
  });

  testWidgets('the release chart has its own explanation', (tester) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);
    await tester.tap(find.text('Albums & EPs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('charts-info-button')));
    await tester.pumpAndSettle();

    expect(find.text('About the Sonus Albums & EPs'), findsOneWidget);
    expect(find.textContaining('Singles chart only through'), findsOneWidget);
  });

  group('long charts', () {
    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );

    // Lazy lists estimate their extent, so jump until the end stops moving.
    Future<void> jumpToEnd(WidgetTester tester) async {
      final state = tester.state<ScrollableState>(scrollable.first);

      for (var i = 0; i < 20; i++) {
        final before = state.position.maxScrollExtent;
        state.position.jumpTo(before);
        await tester.pump();

        if (state.position.maxScrollExtent == before) {
          break;
        }
      }
    }

    // Regression (SN-48J J1): the size selector's horizontal scroller had no
    // PageStorage slot of its own. It shared the chart list's slot, so when
    // it was rebuilt while scrolling back up it reopened at the list's
    // vertical offset.
    testWidgets('size selector keeps its own horizontal scroll position', (
      tester,
    ) async {
      final controller = await _controller(live: _rankedSnapshot(100));
      await _pumpPage(
        tester,
        controller,
        size: const Size(320, 640),
        textScale: 1.6,
      );

      // At this size the chips start below the first screen.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('charts-size-selector')),
        120,
        scrollable: scrollable.first,
      );
      await tester.pumpAndSettle();
      final shownAt = tester
          .state<ScrollableState>(scrollable.first)
          .position
          .pixels;

      await tester.tap(
        find.byKey(const ValueKey<String>('charts-size-100')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      final selectorFinder = find.descendant(
        of: find.byKey(const ValueKey<String>('charts-size-selector')),
        matching: find.byType(Scrollable),
      );
      ScrollableState selector() =>
          tester.state<ScrollableState>(selectorFinder.first);
      final page = tester.state<ScrollableState>(scrollable.first);

      expect(selector().position.maxScrollExtent, greaterThan(0));
      selector().position.jumpTo(0);
      await tester.pumpAndSettle();

      await jumpToEnd(tester);
      await tester.pumpAndSettle();
      expect(selectorFinder, findsNothing);

      // Scroll back up the way a fling does: the selector is rebuilt while
      // the list is still moving.
      unawaited(
        page.position.animateTo(
          shownAt,
          duration: const Duration(milliseconds: 400),
          curve: Curves.linear,
        ),
      );
      await tester.pumpAndSettle();

      expect(selector().position.pixels, 0);
    });

    testWidgets('builds entries lazily, not all 200 at once', (tester) async {
      final controller = await _controller(live: _rankedSnapshot(200));

      await _pumpPage(tester, controller, size: const Size(411, 900));

      expect(
        find.byKey(const ValueKey<String>('charts-entry-songs_1')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('charts-entry-songs_200'),
          skipOffstage: false,
        ),
        findsNothing,
      );

      // #101–200 are on the Bubbling Under board.
      await tester.tap(find.text('Bubbling Under'));
      await tester.pumpAndSettle();
      await jumpToEnd(tester);

      expect(
        find.byKey(const ValueKey<String>('charts-entry-songs_200')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('charts-entry-songs_1'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Hot 100 and Bubbling Under are separate boards', (
      tester,
    ) async {
      final controller = await _controller(
        live: _rankedSnapshot(102, from: 99),
      );

      await _pumpPage(tester, controller);

      Finder row(int rank) => find.byKey(
        ValueKey<String>('charts-entry-songs_$rank'),
        skipOffstage: false,
      );
      expect(row(100), findsOneWidget);
      expect(row(101), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('charts-extended-divider')),
        findsNothing,
      );

      await tester.tap(find.text('Bubbling Under'));
      await tester.pumpAndSettle();

      expect(row(100), findsNothing);
      expect(row(101), findsOneWidget);
      expect(find.text('Sonus Bubbling Under'), findsOneWidget);
      // Bubbling Under keeps the real Top 200 position: #101, never #1.
      expect(
        find.descendant(of: row(101), matching: find.text('101')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row(101), matching: find.text('1')),
        findsNothing,
      );
    });

    group('Charts 2.0 C3 boards', () {
      testWidgets('SN-50 device polish: #1–10 are about as compact as the '
          'rows below them', (tester) async {
        final controller = await _controller(live: _rankedSnapshot(30));
        await _pumpPage(tester, controller, size: const Size(411, 20000));

        double height(String id) => tester
            .getSize(find.byKey(ValueKey<String>('charts-entry-$id')))
            .height;
        final row = height('songs_11');
        // The frames add only a few pixels.
        expect(height('songs_1'), lessThan(row * 1.2));
        expect(height('songs_5'), lessThan(row * 1.2));
        // #1 keeps its gradient frame and a trophy; #2–10 their frames.
        expect(
          find.byKey(const ValueKey<String>('charts-number-one')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('charts-top-ten-frame')),
          findsNWidgets(9),
        );
        // Movement and details stay on every framed row.
        expect(
          find.byKey(const ValueKey<String>('charts-movement-songs_2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('charts-row-expand-songs_1')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('SN-50 device polish: compact #1–10 fit 320dp at 2x text '
          'in every theme', (tester) async {
        for (final id in SonusThemeId.values) {
          final controller = await _controller(live: _rankedSnapshot(12));
          await _pumpPage(
            tester,
            controller,
            theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
            size: const Size(320, 6000),
            textScale: 2,
          );
          expect(tester.takeException(), isNull, reason: id.label);
          expect(
            find.byKey(const ValueKey<String>('charts-featured-frame')),
            findsOneWidget,
          );
        }
      });

      testWidgets('#1 is featured, #2–10 framed, #11+ compact rows', (
        tester,
      ) async {
        final controller = await _controller(live: _rankedSnapshot(30));
        await _pumpPage(tester, controller, size: const Size(411, 20000));

        expect(
          find.byKey(const ValueKey<String>('charts-featured-frame')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('charts-featured-frame')),
            matching: find.byKey(
              const ValueKey<String>('charts-entry-songs_1'),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('charts-top-ten-frame')),
          findsNWidgets(9),
        );
        // Every position is a compact row; #1–10 sit inside frames.
        expect(find.byType(ChartCompactRow), findsNWidgets(30));
        expect(
          find.byKey(const ValueKey<String>('charts-row-songs_11')),
          findsOneWidget,
        );
        // The compact row's full card is one tap away and replaces the row.
        expect(
          find.byKey(const ValueKey<String>('charts-entry-card-songs_11')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('charts-row-expand-songs_11')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('charts-entry-card-songs_11')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('charts-row-songs_11')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('charts-row-collapse-songs_11')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey<String>('charts-row-songs_11')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('compact rows read rank, title, artist and movement', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final controller = await _controller(live: _rankedSnapshot(15));
        await _pumpPage(tester, controller, size: const Size(411, 20000));

        expect(
          find.bySemanticsLabel(RegExp(r'^Number 12, Song 12, Artist 12')),
          findsOneWidget,
        );
        semantics.dispose();
      });

      testWidgets('Bubbling Under is all compact, from #101, with no Top N', (
        tester,
      ) async {
        final controller = await _controller(live: _rankedSnapshot(120));
        await _pumpPage(tester, controller, size: const Size(411, 20000));

        expect(find.text('Top 100'), findsOneWidget);
        await tester.tap(find.text('Bubbling Under'));
        await tester.pumpAndSettle();

        expect(controller.board, ChartBoard.extended);
        expect(find.text('Top 100'), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('charts-featured-frame')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('charts-top-ten-frame')),
          findsNothing,
        );
        expect(find.byType(ChartCompactRow), findsNWidgets(20));
        expect(find.text('20 positions'), findsOneWidget);
        // The chosen Top N is kept for the Hot 100 board.
        expect(controller.viewSize, ChartViewSize.top100);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an empty Bubbling Under says so', (tester) async {
        final controller = await _controller(live: _rankedSnapshot(12));
        await _pumpPage(tester, controller);

        await tester.tap(find.text('Bubbling Under'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('charts-board-empty')),
          findsOneWidget,
        );
      });

      testWidgets('each board remembers its own scroll position', (
        tester,
      ) async {
        final controller = await _controller(live: _rankedSnapshot(200));
        await _pumpPage(tester, controller, size: const Size(411, 900));

        ScrollPosition position() =>
            tester.state<ScrollableState>(scrollable.first).position;

        position().jumpTo(3000);
        await tester.pumpAndSettle();

        await controller.selectBoard(ChartBoard.extended);
        await tester.pumpAndSettle();
        expect(position().pixels, 0);
        position().jumpTo(1200);
        await tester.pumpAndSettle();

        await controller.selectBoard(ChartBoard.top100);
        await tester.pumpAndSettle();
        expect(position().pixels, 3000);

        await controller.selectBoard(ChartBoard.extended);
        await tester.pumpAndSettle();
        expect(position().pixels, 1200);
      });

      testWidgets('jump to rank brings a lazily built row into view', (
        tester,
      ) async {
        final controller = await _controller(live: _rankedSnapshot(100));
        await _pumpPage(tester, controller, size: const Size(411, 900));

        final target = find.byKey(
          const ValueKey<String>('charts-entry-songs_87'),
        );
        expect(target, findsNothing);

        await tester.tap(
          find.byKey(const ValueKey<String>('charts-jump-to-rank')),
        );
        await tester.pumpAndSettle();
        // Out of range is refused.
        await tester.enterText(
          find.byKey(const ValueKey<String>('charts-jump-field')),
          '150',
        );
        await tester.tap(find.byKey(const ValueKey<String>('charts-jump-go')));
        await tester.pumpAndSettle();
        expect(find.text('Enter a number from 1 to 100'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey<String>('charts-jump-field')),
          '87',
        );
        await tester.tap(find.byKey(const ValueKey<String>('charts-jump-go')));
        await tester.pumpAndSettle();

        expect(target, findsOneWidget);
        final top = tester.getTopLeft(target).dy;
        expect(top, inInclusiveRange(0, 900 - 60));
        expect(tester.takeException(), isNull);
      });

      testWidgets('long boards get a draggable rail, short ones do not', (
        tester,
      ) async {
        final controller = await _controller(live: _rankedSnapshot(100));
        await _pumpPage(tester, controller);
        final rail = find.byKey(const ValueKey<String>('charts-scroll-rail'));
        expect(rail, findsOneWidget);
        expect(tester.widget<Scrollbar>(rail).interactive, isTrue);
        // Shown while scrolling only: nothing stays on screen at rest.
        expect(tester.widget<Scrollbar>(rail).thumbVisibility, isNot(true));

        final short = await _controller(live: _rankedSnapshot(20));
        await _pumpPage(tester, short);
        expect(rail, findsNothing);
        expect(
          find.byKey(const ValueKey<String>('charts-jump-to-rank')),
          findsOneWidget,
        );

        final tiny = await _controller(live: _rankedSnapshot(8));
        await _pumpPage(tester, tiny);
        expect(
          find.byKey(const ValueKey<String>('charts-jump-to-rank')),
          findsNothing,
        );
      });

      testWidgets('albums use Top 100 and #101–200 boards', (tester) async {
        final controller = await _controller();
        await _pumpPage(tester, controller);
        await controller.selectChartType(ChartType.albums);
        await tester.pumpAndSettle();

        expect(find.text('#101–200'), findsOneWidget);
        expect(find.text('Bubbling Under'), findsNothing);
      });
    });

    testWidgets('a chart without extended standings has no boundary', (
      tester,
    ) async {
      final controller = await _controller(
        live: _rankedSnapshot(100, from: 97),
      );

      await _pumpPage(tester, controller);

      expect(
        find.byKey(const ValueKey<String>('charts-entry-songs_100')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('charts-extended-divider')),
        findsNothing,
      );
    });
  });

  group('Sonus themes', () {
    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} renders at 320px with 2x text', (tester) async {
        final controller = await _controller(
          live: _rankedSnapshot(3),
          history: [
            _finalizedWeek(DateTime.utc(2026, 9, 20), ranks: 3),
            _finalizedWeek(DateTime.utc(2026, 9, 13), ranks: 3),
          ],
        );

        await _pumpPage(
          tester,
          controller,
          theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
          size: const Size(320, 8000),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('charts-title')),
            matching: find.text('Hot 100'),
            matchRoot: true,
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('charts-entry-songs_1')),
          findsOneWidget,
        );
        for (final id in ['songs_1', 'songs_2', 'songs_3']) {
          await _showDetails(tester, id);
        }
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey<String>('charts-longevity-songs_1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('charts-top-accent-songs_2')),
          findsOneWidget,
        );

        controller.showOlderWeek();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final id in ['songs_1', 'songs_2', 'songs_3']) {
          if (find
              .byKey(ValueKey<String>('charts-row-expand-$id'))
              .evaluate()
              .isNotEmpty) {
            await _showDetails(tester, id);
          }
        }
        expect(find.text('Top 10 streak: 2 weeks'), findsNWidgets(3));
      });
    }

    // Regression from emulator QA: with 2x text "Moments" broke mid-word
    // because the decorative segment icons took its width.
    testWidgets('large text drops decorative selector icons only', (
      tester,
    ) async {
      final controller = await _controller();

      await _pumpPage(tester, controller);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
      expect(find.byIcon(Icons.album_rounded), findsWidgets);

      await _pumpPage(
        tester,
        controller,
        size: const Size(320, 2400),
        textScale: 2,
      );
      expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
      expect(find.byIcon(Icons.leaderboard_rounded), findsNothing);
      // The selected segments keep their checkmark.
      expect(find.byIcon(Icons.check), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selectors are styled locally, not through the theme', (
      tester,
    ) async {
      final theme = SonusThemeFactory.build(const SonusAppearanceSpec());
      final controller = await _controller();

      await _pumpPage(tester, controller, theme: theme);

      // The shared theme keeps its defaults for other screens.
      expect(theme.segmentedButtonTheme.style, isNull);
      expect(theme.chipTheme.selectedColor, isNull);

      final selector = tester.widget<SegmentedButton<ChartType>>(
        find.byKey(const ValueKey<String>('charts-type-selector')),
      );
      expect(selector.style, isNotNull);
    });

    testWidgets('header carries the theme motif with decoration on', (
      tester,
    ) async {
      final controller = await _controller();

      await _pumpPage(
        tester,
        controller,
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('charts-header')),
          matching: find.byKey(const ValueKey<String>('sonus-motif-mark')),
        ),
        findsOneWidget,
      );
    });
  });

  group('SN-50 This Week', () {
    Future<ChartsController> withThisWeek() => _controller(
      history: [_finalizedWeek(DateTime.utc(2026, 9, 20), ranks: 3)],
      thisWeek: _FakeThisWeekChartService(),
    );

    testWidgets('the default view stays the career standings', (tester) async {
      await _pumpPage(tester, await withThisWeek());

      expect(find.text('Career standings'), findsOneWidget);
      expect(find.text('CURRENT'), findsOneWidget);
      expect(find.text('IN PROGRESS'), findsNothing);
      expect(find.textContaining('Best so far'), findsNothing);
    });

    testWidgets('is clearly provisional, with its best so far apart from the '
        'official peak', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = await withThisWeek();
      await _pumpPage(tester, controller);

      await tester.tap(find.byKey(const ValueKey<String>('charts-older-week')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('charts-title')),
          matching: find.text('Hot 100'),
          matchRoot: true,
        ),
        findsOneWidget,
      );
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('CURRENT'), findsNothing);
      expect(find.text('FINAL'), findsNothing);
      expect(
        find.text('Updates as you listen. Final after Oct 3, 2026.'),
        findsOneWidget,
      );

      // songs_2 led earlier this week; its official peak is last week's #2.
      await _showDetails(tester, 'songs_2');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('charts-entry-songs_2')),
          matching: find.text('Best so far #1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('charts-entry-songs_2')),
          matching: find.text('Peak #2'),
        ),
        findsOneWidget,
      );
      await _showDetails(tester, 'songs_1');
      expect(
        find.byKey(const ValueKey<String>('charts-last-week-songs_1')),
        findsOneWidget,
      );
      expect(find.text('Last week #3'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('best so far this week number 1')),
        findsWidgets,
      );

      expect(find.byTooltip('Older chart week'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('charts-older-week')));
      await tester.pumpAndSettle();
      expect(find.text('FINAL'), findsOneWidget);
      expect(find.textContaining('Best so far'), findsNothing);

      await tester.tap(find.byKey(const ValueKey<String>('charts-newer-week')));
      await tester.pumpAndSettle();
      expect(find.text('IN PROGRESS'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('its information sheet explains This Week', (tester) async {
      final controller = await withThisWeek();
      await _pumpPage(tester, controller);
      controller.showOlderWeek();
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('charts-info-button')),
      );
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: find.byKey(const ValueKey<String>('charts-info-sheet')),
        matching: find.byType(Scrollable),
      );
      for (final text in [
        'updates as you listen',
        'Best so far is the highest position reached this week',
        'even if it dropped out of the Top 100',
        'most recent qualifying stream',
      ]) {
        await tester.scrollUntilVisible(
          find.textContaining(text),
          200,
          scrollable: scrollable,
        );
        expect(find.textContaining(text), findsOneWidget, reason: text);
      }
      expect(find.text('Percentage change'), findsNothing);
      expect(find.textContaining('start of this chart week'), findsNothing);
    });

    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} renders This Week at 320px with 2x text', (
        tester,
      ) async {
        final controller = await withThisWeek();
        await _pumpPage(
          tester,
          controller,
          theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
          size: const Size(320, 8000),
          textScale: 2,
        );

        controller.showOlderWeek();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('IN PROGRESS'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('charts-this-week-note')),
          findsOneWidget,
        );
        await _showDetails(tester, 'songs_3');
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey<String>('charts-best-so-far-songs_3')),
          findsOneWidget,
        );
      });
    }
  });

  testWidgets('calendar opens when finalized chart weeks exist', (
    tester,
  ) async {
    final controller = await _controller(
      history: [
        _snapshot(
          id: 'historical-1',
          start: DateTime.utc(2026, 9, 20),
          finalized: true,
        ),
        _snapshot(
          id: 'historical-2',
          start: DateTime.utc(2026, 9, 13),
          finalized: true,
        ),
      ],
    );

    await _pumpPage(tester, controller);

    await tester.tap(find.byKey(const ValueKey<String>('charts-calendar')));

    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(find.text('Choose a Sonus Hot 100 week'), findsOneWidget);
  });
  testWidgets('switches from Charts to populated Moments feed', (tester) async {
    final controller = await _controller(
      moments: [
        _momentEvent(
          id: 'final-peak',
          scope: ChartMomentScope.finalized,
          type: ChartMomentEventType.newPeak,
          currentRank: 3,
          currentPeakRank: 3,
        ),
      ],
    );

    await _pumpPage(tester, controller);

    expect(
      find.byKey(const ValueKey<String>('charts-presentation-selector')),
      findsOneWidget,
    );
    expect(find.text('Charts'), findsOneWidget);
    expect(find.text('Moments'), findsOneWidget);

    expect(
      find.byKey(const ValueKey<String>('charts-type-selector')),
      findsOneWidget,
    );

    await tester.tap(find.text('Moments'));
    await tester.pump();

    expect(controller.isShowingMoments, isTrue);

    expect(
      find.byKey(const ValueKey<String>('charts-moments-feed')),
      findsOneWidget,
    );

    expect(
      find.byKey(const ValueKey<String>('charts-type-selector')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('charts-week-navigation')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('charts-size-selector')),
      findsNothing,
    );

    final story = controller.momentStories.single;
    expect(find.text(story.headline), findsOneWidget);
    expect(story.headline, contains('#3'));
    expect(story.headline, contains('"Song 1"'));
    expect(find.text('WEEKLY SONUS HOT 100'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MomentPostCard),
        matching: find.text(story.publisher.label),
      ),
      findsOneWidget,
    );
    expect(find.text('NEW PEAK'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);
    // SN-50 F-Q22: the chart is named once, in the kicker.
    expect(find.textContaining('HOT 100 #'), findsNothing);
  });

  test('Singles and releases awaiting a format tell no release story; '
      'a song story names its Single as a Single', () async {
    ChartMomentEvent releaseDebut(String albumId) {
      final at = DateTime.utc(2026, 9, 28, 1);
      final week = DateTime.utc(2026, 9, 27);
      return ChartMomentEvent(
        id: 'debut-$albumId',
        deduplicationKey: 'debut-$albumId',
        sourceId: 'source-$albumId',
        chartType: ChartType.albums,
        scope: ChartMomentScope.allTime,
        eventType: ChartMomentEventType.debut,
        entity: ChartEntitySnapshot(
          entityId: albumId,
          title: 'Release $albumId',
          artistId: 'artist_1',
          artistName: 'Artist 1',
        ),
        weekStartUtc: week,
        weekEndUtc: week.add(const Duration(days: 7)),
        occurredAt: at,
        createdAt: at,
        currentRank: 2,
        qualifiedStreamCount: 4,
      );
    }

    final controller = await _controller(
      moments: [
        releaseDebut('album_single'),
        releaseDebut('album_review'),
        releaseDebut('album_ep'),
        _momentEvent(
          id: 'song-peak',
          scope: ChartMomentScope.allTime,
          type: ChartMomentEventType.newPeak,
          currentRank: 3,
          currentPeakRank: 3,
        ),
      ],
      releaseFormats: () async => {
        'album_single': ReleaseFormat.single,
        'album_review': null,
        'album_ep': ReleaseFormat.ep,
        'album_1': ReleaseFormat.single,
      },
    );

    final stories = controller.momentStories;
    expect(
      [
        for (final s in stories)
          if (s.facts.chartType == ChartType.albums) s.facts.title,
      ],
      ['Release album_ep'],
    );
    final song = stories.singleWhere(
      (s) => s.facts.chartType == ChartType.songs,
    );
    // "Song 1" is on album_1, a Single.
    expect(song.facts.releaseLabel, 'Single');
    // The stored events are untouched.
    expect(controller.momentFeedItems.length, 4);
  });

  testWidgets('a Moment post links to its song, album and artist', (
    tester,
  ) async {
    final controller = await _controller(
      albums: [_album(id: 'album_1')],
      artists: [_artist(portraitPath: '/art/artist_1.jpg')],
      moments: [
        _momentEvent(
          id: 'final-peak',
          scope: ChartMomentScope.finalized,
          type: ChartMomentEventType.newPeak,
          currentRank: 3,
          currentPeakRank: 3,
          artistId: 'artist_1',
        ),
      ],
    );

    await _pumpPage(tester, controller);
    await tester.tap(find.text('Moments'));
    await tester.pump();

    expect(_postPart('image-right'), findsOneWidget);
    for (final link in ['song', 'album', 'artist']) {
      expect(_postPart(link), findsOneWidget);
    }
    // Sonus never invents engagement.
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(find.byIcon(Icons.repeat_rounded), findsNothing);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);

    await tester.tap(_postPart('album'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlbumProfilePage), findsOneWidget);
    // The song's own edition opens, not whichever edition is primary.
    expect(
      tester
          .widget<AlbumProfilePage>(find.byType(AlbumProfilePage))
          .initialEditionId,
      'edition_1',
    );
  });

  testWidgets('a post only links to what exists in the library', (
    tester,
  ) async {
    final controller = await _controller(
      tracks: [_track(isBlocked: true)],
      moments: [
        _momentEvent(
          id: 'final-peak',
          scope: ChartMomentScope.finalized,
          type: ChartMomentEventType.newPeak,
          currentRank: 3,
          currentPeakRank: 3,
        ),
      ],
    );

    await _pumpPage(tester, controller);
    await tester.tap(find.text('Moments'));
    await tester.pump();

    expect(_postPart('song'), findsNothing);
    expect(_postPart('artist'), findsNothing);
    // The artist has no portrait: a placeholder, never someone else's.
    expect(
      find.descendant(
        of: _postPart('image-right'),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
  });

  testWidgets('a #1 on the permanent chart says #1 and names the Hot 100', (
    tester,
  ) async {
    final controller = await _controller(
      moments: [
        _momentEvent(
          id: 'all-time-one',
          scope: ChartMomentScope.allTime,
          type: ChartMomentEventType.firstNumberOne,
          previousRank: 2,
          currentRank: 1,
          threshold: 1,
          streams: 42,
          occurredAt: DateTime(2026, 9, 28, 9),
        ),
      ],
    );

    await _pumpPage(tester, controller);
    await tester.tap(find.text('Moments'));
    await tester.pump();

    final story = controller.momentStories.single;
    expect(find.text(story.headline), findsOneWidget);
    expect(story.headline, contains('#1'));
    for (final banned in ['lifetime', 'summit', 'all-time', 'weekly']) {
      expect(story.headline.toLowerCase(), isNot(contains(banned)));
      expect((story.body ?? '').toLowerCase(), isNot(contains(banned)));
    }
    expect(find.text('SONUS HOT 100'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('NUMBER ONE'), findsOneWidget);
    expect(find.text('${story.publisher.handle} · 3h'), findsOneWidget);
  });

  testWidgets('Moment posts fit a 320 px screen at large text', (tester) async {
    final controller = await _controller(
      artists: [_artist(portraitPath: '/art/artist_1.jpg')],
      albums: [_album(id: 'album_1')],
      moments: [
        _momentEvent(
          id: 'final-peak',
          scope: ChartMomentScope.finalized,
          type: ChartMomentEventType.newPeak,
          currentRank: 3,
          currentPeakRank: 3,
          artistId: 'artist_1',
        ),
      ],
    );

    await _pumpPage(
      tester,
      controller,
      size: const Size(320, 2400),
      textScale: 2,
    );
    await tester.tap(find.text('Moments'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byType(MomentPostCard));
    expect(card.right, lessThanOrEqualTo(320));
    for (final link in ['song', 'album', 'artist']) {
      final size = tester.getSize(_postPart(link));
      expect(size.height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('provisional live facts are not published as news', (
    tester,
  ) async {
    final controller = await _controller(
      moments: [
        _momentEvent(
          id: 'live-peak',
          scope: ChartMomentScope.live,
          type: ChartMomentEventType.newPeak,
          currentRank: 3,
          currentPeakRank: 3,
          occurredAt: DateTime.utc(2026, 9, 29, 14),
        ),
      ],
    );

    await _pumpPage(tester, controller);

    await tester.tap(find.text('Moments'));
    await tester.pump();

    // The permanent chart tells this as it happens; a provisional weekly
    // fact would only repeat it.
    expect(controller.momentStories, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('charts-moments-empty')),
      findsOneWidget,
    );
  });

  testWidgets('empty Moments feed has its own empty state', (tester) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    await tester.tap(find.text('Moments'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('charts-moments-empty')),
      findsOneWidget,
    );
    expect(find.text('No Moments yet'), findsOneWidget);

    expect(find.byKey(const ValueKey<String>('charts-empty')), findsNothing);
  });

  testWidgets('switching back to Charts restores chart controls', (
    tester,
  ) async {
    final controller = await _controller(
      moments: [
        _momentEvent(
          id: 'moment',
          scope: ChartMomentScope.finalized,
          type: ChartMomentEventType.newPeak,
          currentRank: 3,
          currentPeakRank: 3,
        ),
      ],
    );

    await _pumpPage(tester, controller);

    await tester.tap(find.text('Moments'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('charts-moments-feed')),
      findsOneWidget,
    );

    await tester.tap(find.text('Charts'));
    await tester.pump();

    expect(controller.isShowingCharts, isTrue);

    expect(
      find.byKey(const ValueKey<String>('charts-type-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('charts-week-navigation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('charts-size-selector')),
      findsOneWidget,
    );

    expect(
      find.byKey(const ValueKey<String>('charts-moments-feed')),
      findsNothing,
    );
  });
  testWidgets('missing controller renders initializing state', (tester) async {
    await tester.pumpWidget(
      Provider<ChartsController?>.value(
        value: null,
        child: MaterialApp(home: Scaffold(body: ChartsPage())),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('charts-initializing')),
      findsOneWidget,
    );
  });

  testWidgets('F-Q26: Moments shows a dot and says "new stories" until it '
      'is opened', (tester) async {
    final store = MemoryMomentsLastSeenStore.at(DateTime.utc(2026, 9, 1));
    final controller = await _controller(
      momentsLastSeen: store,
      moments: [
        _momentEvent(
          id: 'final-peak',
          scope: ChartMomentScope.finalized,
          type: ChartMomentEventType.newPeak,
          currentRank: 3,
          currentPeakRank: 3,
        ),
      ],
    );
    final semantics = tester.ensureSemantics();

    // 320 px wide at twice the text size.
    await _pumpPage(
      tester,
      controller,
      size: const Size(320, 2400),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);

    final dot = find.byKey(const ValueKey<String>('charts-moments-new-dot'));
    expect(dot, findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('new stories')), findsOneWidget);

    await tester.tap(find.text('Moments'));
    await tester.pumpAndSettle();
    expect(dot, findsNothing);
    expect(
      store.seen?.occurredAtUtc,
      controller.momentStories.first.occurredAt.toUtc(),
    );

    await tester.tap(find.text('Charts'));
    await tester.pumpAndSettle();
    expect(dot, findsNothing);
    expect(find.bySemanticsLabel(RegExp('new stories')), findsNothing);
    semantics.dispose();
  });

  testWidgets('F-Q25: filters narrow the feed and can be cleared', (
    tester,
  ) async {
    final controller = await _controller(
      moments: [
        _momentEvent(
          id: 'final-peak',
          scope: ChartMomentScope.finalized,
          type: ChartMomentEventType.newPeak,
          currentRank: 3,
          currentPeakRank: 3,
        ),
      ],
    );
    final story = controller.momentStories.single;
    final other = MomentPublisher.values.firstWhere(
      (publisher) => publisher != story.publisher,
    );

    await _pumpPage(tester, controller);
    await tester.tap(find.text('Moments'));
    await tester.pumpAndSettle();

    // Charts 2.0 C1: one compact menu per filter.
    await tester.tap(
      find.byKey(const ValueKey<String>('charts-moments-filter-Publisher')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey<String>('charts-moments-filter-Publisher-${other.name}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(story.headline), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('charts-moments-filtered-empty')),
      findsOneWidget,
    );

    await tester.tap(find.text('Show all Moments'));
    await tester.pumpAndSettle();
    expect(find.text(story.headline), findsOneWidget);
  });

  group('SN-50 device polish: Moments filters', () {
    Future<ChartsController> withStory() => _controller(
      moments: [
        _momentEvent(
          id: 'final-peak',
          scope: ChartMomentScope.finalized,
          type: ChartMomentEventType.newPeak,
          currentRank: 3,
          currentPeakRank: 3,
        ),
      ],
    );

    Rect rectOf(WidgetTester tester, String key) =>
        tester.getRect(find.byKey(ValueKey<String>(key)));

    testWidgets('Category and Publisher sit side by side on a phone', (
      tester,
    ) async {
      final controller = await withStory();
      await _pumpPage(tester, controller, size: const Size(411, 1600));
      await tester.tap(find.text('Moments'));
      await tester.pumpAndSettle();

      final category = rectOf(tester, 'charts-moments-filter-Category');
      final publisher = rectOf(tester, 'charts-moments-filter-Publisher');
      expect(category.top, publisher.top);
      expect(publisher.left, greaterThan(category.right));
      expect(category.width, closeTo(publisher.width, 1));
      expect(
        find.byKey(const ValueKey<String>('charts-moments-filters-row')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('they stack at 320dp with 2x text', (tester) async {
      final controller = await withStory();
      await _pumpPage(
        tester,
        controller,
        size: const Size(320, 2400),
        textScale: 2,
      );
      await tester.tap(find.text('Moments'));
      await tester.pumpAndSettle();

      final category = rectOf(tester, 'charts-moments-filter-Category');
      final publisher = rectOf(tester, 'charts-moments-filter-Publisher');
      expect(publisher.top, greaterThanOrEqualTo(category.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long selection truncates, and filters still apply', (
      tester,
    ) async {
      final controller = await withStory();
      final story = controller.momentStories.single;
      await _pumpPage(tester, controller, size: const Size(360, 1600));
      await tester.tap(find.text('Moments'));
      await tester.pumpAndSettle();

      final longest = MomentCategory.values.reduce(
        (a, b) => a.label.length >= b.label.length ? a : b,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('charts-moments-filter-Category')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>('charts-moments-filter-Category-${longest.name}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.momentCategory, longest);
      expect(
        find.byKey(const ValueKey<String>('charts-moments-filters-row')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('charts-moments-filter-Category')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('charts-moments-filter-Category-null'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(story.headline), findsOneWidget);
    });

    testWidgets('the Archive keeps its week menu below them', (tester) async {
      final controller = await withStory();
      await _pumpPage(tester, controller, size: const Size(411, 1600));
      await tester.tap(find.text('Moments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();

      final category = rectOf(tester, 'charts-moments-filter-Category');
      final week = rectOf(tester, 'charts-moments-week');
      expect(week.top, greaterThanOrEqualTo(category.bottom));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('SN-50 device polish: a rising song shows how far it climbed '
      'beside its story', (tester) async {
    final controller = await _controller(
      moments: [
        _momentEvent(
          id: 'climb',
          scope: ChartMomentScope.allTime,
          type: ChartMomentEventType.rankRise,
          previousRank: 20,
          currentRank: 8,
        ),
      ],
    );
    final story = controller.momentStories.single;
    expect(story.climb, 12);

    final semantics = tester.ensureSemantics();
    await _pumpPage(tester, controller, size: const Size(411, 1600));
    await tester.tap(find.text('Moments'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey<String>('moment-post-climb-${story.id}')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Up 12 places')), findsWidgets);
    semantics.dispose();
  });

  testWidgets('F-Q25: older Moments load as the feed reaches its end', (
    tester,
  ) async {
    final controller = await _controller(
      momentPageSize: 1,
      moments: [
        for (var day = 1; day <= 4; day++)
          _momentEvent(
            id: 'debut-$day',
            scope: ChartMomentScope.allTime,
            type: ChartMomentEventType.debut,
            currentRank: 30,
            currentPeakRank: 30,
            occurredAt: DateTime(2026, 9, day, 12).toUtc(),
          ),
      ],
    );
    expect(controller.hasMoreMoments, isTrue);
    final firstPage = controller.momentStories.length;

    await _pumpPage(tester, controller);
    await tester.tap(find.text('Moments'));
    await tester.pumpAndSettle();

    expect(controller.hasMoreMoments, isFalse);
    expect(controller.momentStories.length, greaterThan(firstPage));
    expect(controller.momentStories, hasLength(4));
    expect(
      find.byKey(const ValueKey<String>('charts-moments-loading-more')),
      findsNothing,
    );
  });

  testWidgets('F-Q19/F-Q20: an SN-50 song story names every performer as '
      'text', (tester) async {
    final controller = await _controller(
      tracks: [
        LibraryTrack(
          songId: 'songs_1',
          title: 'Song 1',
          artistId: 'artist_1',
          artistName: 'Artist 1',
          albumId: 'album_1',
          albumTitle: 'Album 1',
          albumEditionId: 'edition_1',
          albumEditionTitle: 'Standard',
          albumEditionType: AlbumEditionType.standard,
          trackNumber: 1,
          durationSeconds: 180,
          isSingle: false,
          featuredArtists: const ['Guest One', 'Guest Two'],
          dateAdded: DateTime.utc(2026, 9, 1),
          isAvailable: true,
          filePath: 'C:/Music/song_1.mp3',
        ),
      ],
      moments: [
        _momentEvent(
          id: 'refined-debut',
          scope: ChartMomentScope.allTime,
          type: ChartMomentEventType.debut,
          currentRank: 30,
          currentPeakRank: 30,
          occurredAt: DateTime.utc(2026, 11, 3, 12),
        ),
      ],
    );

    await _pumpPage(tester, controller, size: const Size(320, 2400));
    await tester.tap(find.text('Moments'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Artist 1 Ft. Guest One, Guest Two'), findsOneWidget);
    expect(_postPart('credit'), findsOneWidget);
  });

  group('Charts 2.0 C1: Moments feed and archive', () {
    // "Now" is 28 Sep 2026: the week of 27 Sep is running; earlier weeks
    // are finalized.
    ChartMomentEvent archived(int week, {String? title, int day = 0}) =>
        _momentEvent(
          id: 'old-$week-$day',
          scope: ChartMomentScope.allTime,
          type: ChartMomentEventType.debut,
          currentRank: 20 + week,
          currentPeakRank: 20 + week,
          weekStartUtc: DateTime.utc(
            2026,
            9,
            20,
          ).subtract(Duration(days: 7 * week)),
          occurredAt: DateTime.utc(
            2026,
            9,
            21 + day,
            12,
          ).subtract(Duration(days: 7 * week)),
          title: title ?? 'Old Song $week-$day',
          entityId: 'songs_old_$week$day',
        );

    ChartMomentEvent running({String id = 'now'}) => _momentEvent(
      id: id,
      scope: ChartMomentScope.finalized,
      type: ChartMomentEventType.newPeak,
      currentRank: 3,
      currentPeakRank: 3,
      occurredAt: DateTime.utc(2026, 9, 28, 9),
    );

    testWidgets('a finalized week\'s stories move from Recent to the Archive', (
      tester,
    ) async {
      final controller = await _controller(
        moments: [
          running(),
          archived(0, title: 'Archived Hit'),
        ],
      );
      final current = controller.momentStories.firstWhere(
        (s) => !controller.isArchivedMoment(s),
      );
      final old = controller.momentStories.firstWhere(
        controller.isArchivedMoment,
      );

      await _pumpPage(tester, controller);
      await tester.tap(find.text('Moments'));
      await tester.pumpAndSettle();
      expect(find.text(current.headline), findsOneWidget);
      expect(find.text(old.headline), findsNothing);

      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(find.text(old.headline), findsOneWidget);
      expect(find.text(current.headline), findsNothing);
      expect(old.headline, isNotEmpty, reason: 'stored wording, unchanged');
    });

    testWidgets('the Archive reads every page and searches all of it', (
      tester,
    ) async {
      final controller = await _controller(
        momentPageSize: 1,
        moments: [
          running(),
          for (var week = 0; week < 6; week++) archived(week),
          archived(3, title: 'Needle In The Haystack', day: 2),
        ],
      );
      expect(controller.hasMoreMoments, isTrue, reason: 'paged reads');

      await _pumpPage(tester, controller);
      await tester.tap(find.text('Moments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();

      expect(controller.hasMoreMoments, isFalse, reason: 'every page read');
      expect(controller.sectionMomentStories, hasLength(7));

      await tester.enterText(
        find.byKey(const ValueKey<String>('charts-moments-search')),
        'needle haystack',
      );
      await tester.pumpAndSettle();
      expect(controller.sectionMomentStories, hasLength(1));
      expect(
        controller.sectionMomentStories.single.facts.title,
        'Needle In The Haystack',
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('charts-moments-search')),
        '',
      );
      await tester.pumpAndSettle();
      final weeks = controller.archivedMomentWeeks;
      expect(weeks, hasLength(6));
      expect(weeks.first.isAfter(weeks.last), isTrue, reason: 'newest first');

      await tester.tap(
        find.byKey(const ValueKey<String>('charts-moments-week')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'charts-moments-week-${weeks[3].millisecondsSinceEpoch}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.sectionMomentStories, hasLength(2));
      expect(controller.momentWeek, weeks[3]);
      expect(
        // Labels use the local date of the week's start.
        find.textContaining(
          RegExp(r'Week of \d+ Aug 2026'),
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a filter in Recent reads the whole collection', (
      tester,
    ) async {
      final controller = await _controller(
        momentPageSize: 1,
        moments: [
          running(),
          running(id: 'now-2'),
          for (var week = 0; week < 4; week++) archived(week),
        ],
      );
      final story = controller.momentStories.first;
      controller.selectMomentPublisher(story.publisher);
      await tester.runAsync(() => controller.loadAllMoments());
      expect(controller.hasMoreMoments, isFalse);
      expect(
        controller.sectionMomentStories.every(
          (s) =>
              s.publisher == story.publisher && !controller.isArchivedMoment(s),
        ),
        isTrue,
      );
    });

    testWidgets('nothing is drawn over the artwork; the facts sit below it', (
      tester,
    ) async {
      final controller = await _controller(moments: [running()]);
      final story = controller.momentStories.single;

      await _pumpPage(tester, controller);
      await tester.tap(find.text('Moments'));
      await tester.pumpAndSettle();

      final card = find.byKey(ValueKey<String>('moment-post-${story.id}'));
      expect(
        find.descendant(of: card, matching: find.byType(PositionedDirectional)),
        findsNothing,
      );
      final image = find.byKey(
        ValueKey<String>('moment-post-image-left-${story.id}'),
      );
      final status = find.byKey(
        ValueKey<String>('moment-post-status-${story.id}'),
      );
      final kicker = find.byKey(
        ValueKey<String>('moment-post-kicker-${story.id}'),
      );
      expect(status, findsOneWidget);
      expect(kicker, findsOneWidget);
      expect(
        tester.getTopLeft(status).dy,
        greaterThan(tester.getBottomLeft(image).dy),
      );
      expect(find.text('#3'), findsOneWidget);
    });

    testWidgets('a floating Back to top appears far down and returns', (
      tester,
    ) async {
      final controller = await _controller(
        moments: [
          for (var i = 0; i < 12; i++)
            _momentEvent(
              id: 'p$i',
              scope: ChartMomentScope.finalized,
              type: ChartMomentEventType.newPeak,
              currentRank: 3 + i,
              currentPeakRank: 3 + i,
              occurredAt: DateTime.utc(2026, 9, 28, 1 + i),
              title: 'Peak $i',
              entityId: 'songs_p$i',
            ),
        ],
      );
      await _pumpPage(tester, controller, size: const Size(400, 800));
      await tester.tap(find.text('Moments'));
      await tester.pumpAndSettle();

      final button = find.byKey(const ValueKey<String>('charts-scroll-to-top'));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(of: button, matching: find.byType(AnimatedOpacity)),
            )
            .opacity,
        0,
      );
      await tester.drag(
        find.byKey(const PageStorageKey<String>('charts-scroll')),
        const Offset(0, -2400),
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const PageStorageKey<String>('charts-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scrollable.position.pixels, 0);
    });

    for (final id in SonusThemeId.values) {
      testWidgets('${id.label}: sections, menus and search fit 320 dp at 2x '
          'text', (tester) async {
        final controller = await _controller(moments: [running(), archived(0)]);
        await _pumpPage(
          tester,
          controller,
          size: const Size(320, 1400),
          textScale: 2,
          theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
        );
        await tester.tap(find.text('Moments'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

Future<ChartsController> _controller({
  ChartSnapshot? live,
  List<ChartSnapshot> history = const [],
  List<LibraryTrack>? tracks,
  List<LibraryAlbum>? albums,
  List<LibraryArtist> artists = const [],
  List<ChartMomentEvent> moments = const [],
  ReleaseFormatsLoader? releaseFormats,
  DeluxeEditionsLoader? deluxeEditions,
  ThisWeekChartService? thisWeek,
  MomentsLastSeenStore? momentsLastSeen,
  int momentPageSize = ChartMomentFeedPager.defaultPageSize,
}) async {
  final resolvedLive =
      live ?? _snapshot(id: 'live', start: DateTime.utc(2026, 9, 27));

  final controller = ChartsController(
    allTimeCharts: _FakeAllTimeChartService(
      songs: resolvedLive,
      albums: _snapshot(
        id: 'albums',
        start: DateTime.utc(2026, 9, 27),
        chartType: ChartType.albums,
      ),
    ),
    finalization: _FakeChartFinalizationService(),
    charts: _FakeChartRepository(history: history),
    library: _FakeLibraryQueryRepository(
      tracks: tracks ?? [_track()],
      albums: albums ?? [_album()],
      artists: artists,
    ),
    moments: _FakeChartMomentRepository(events: moments),
    now: () => DateTime(2026, 9, 28, 12),
    releaseFormats: releaseFormats,
    deluxeEditions: deluxeEditions,
    thisWeekCharts: thisWeek,
    momentsLastSeen: momentsLastSeen,
    momentPageSize: momentPageSize,
    momentRules: () async =>
        ChartMomentRules(activatedAtUtc: DateTime.utc(2026, 11, 1)),
  );

  await controller.load();

  return controller;
}

Future<void> _pumpPage(
  WidgetTester tester,
  ChartsController controller, {
  ThemeData? theme,
  Size size = const Size(800, 1600),
  double textScale = 1,
  PlaybackCoordinator? playback,
  SongStatsLoader? songStats,
}) async {
  await tester.binding.setSurfaceSize(size);

  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<PlaybackCoordinator?>.value(value: playback),
        Provider<SongStatsLoader?>.value(value: songStats),
      ],
      child: ChangeNotifierProvider<ChartsController?>.value(
        value: controller,
        child: MaterialApp(
          theme: theme,
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: textScale,
            maxScaleFactor: textScale,
            child: child!,
          ),
          home: const Scaffold(body: ChartsPage()),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

/// A live songs chart with [count] positions; 101 and below are extended
/// standings without an official rank last week.
ChartSnapshot _rankedSnapshot(int count, {int from = 1}) {
  final start = DateTime.utc(2026, 9, 27);

  return ChartSnapshot(
    id: 'ranked-$count',
    chartType: ChartType.songs,
    weekStartUtc: start,
    weekEndUtc: start.add(const Duration(days: 7)),
    entries: [
      for (var rank = from; rank <= count; rank++)
        ChartEntry(
          entity: ChartEntitySnapshot(
            entityId: 'songs_$rank',
            title: 'Song $rank',
            artistName: 'Artist $rank',
            albumTitle: 'Album $rank',
          ),
          rank: rank,
          qualifiedStreamCount: 500 - rank,
          lastQualifiedAt: start.add(const Duration(days: 2)),
          previousFinalRank: rank <= 100 ? rank : null,
          peakRank: rank,
          peakAchievedAt: start,
          weeksOnChart: rank <= 100 ? 2 : 0,
          movement: rank <= 100 ? ChartMovement.same : ChartMovement.newEntry,
        ),
    ],
  );
}

LibraryTrack _track({
  bool isAvailable = true,
  bool isBlocked = false,
  String? filePath = 'C:/Music/song_1.mp3',
  String? versionLabel,
  List<String> featured = const [],
}) {
  return LibraryTrack(
    songId: 'songs_1',
    title: 'Song 1',
    artistId: 'artist_1',
    artistName: 'Artist 1',
    albumId: 'album_1',
    albumTitle: 'Album 1',
    albumEditionId: 'edition_1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: featured,
    versionLabel: versionLabel,
    dateAdded: DateTime.utc(2026, 9, 1),
    isAvailable: isAvailable,
    isSongBlocked: isBlocked,
    filePath: filePath,
  );
}

/// A part of the Moment post on screen, whatever its feed item id.
Finder _postPart(String part) => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('moment-post-$part-'),
);

LibraryArtist _artist({String? portraitPath}) {
  return LibraryArtist(
    artistId: 'artist_1',
    name: 'Artist 1',
    albumCount: 1,
    songCount: 1,
    dateAdded: DateTime.utc(2026, 9, 1),
    topArtistsArtworkPath: portraitPath,
  );
}

LibraryAlbum _album({String id = 'albums_1'}) {
  return LibraryAlbum(
    albumId: id,
    title: 'Album 1',
    artistId: 'artist_1',
    artistName: 'Artist 1',
    trackCount: 1,
    dateAdded: DateTime.utc(2026, 9, 1),
  );
}

ChartMomentEvent _momentEvent({
  required String id,
  required ChartMomentScope scope,
  required ChartMomentEventType type,
  int? previousRank,
  int? currentRank,
  int? previousPeakRank,
  int? currentPeakRank,
  int? threshold,
  int? milestoneValue,
  int? streams,
  String? artistId,
  DateTime? occurredAt,
  DateTime? weekStartUtc,
  String title = 'Song 1',
  String entityId = 'songs_1',
}) {
  final weekStart = weekStartUtc ?? DateTime.utc(2026, 9, 27);
  final at = occurredAt ?? DateTime.utc(2026, 10, 4, 1);

  return ChartMomentEvent(
    id: id,
    deduplicationKey: id,
    sourceId: 'source-$id',
    chartType: ChartType.songs,
    scope: scope,
    eventType: type,
    entity: ChartEntitySnapshot(
      entityId: entityId,
      title: title,
      artistId: artistId,
      artistName: 'Artist 1',
      albumTitle: 'Album 1',
    ),
    weekStartUtc: weekStart,
    weekEndUtc: weekStart.add(const Duration(days: 7)),
    occurredAt: at,
    createdAt: at,
    previousRank: previousRank,
    currentRank: currentRank,
    previousPeakRank: previousPeakRank,
    currentPeakRank: currentPeakRank,
    threshold: threshold,
    milestoneValue: milestoneValue,
    qualifiedStreamCount: streams,
  );
}

/// A finalized songs week of positions 1 to [ranks], each at its own rank.
/// The week in progress: #1 rose from #3, #2 led earlier in the week.
class _FakeThisWeekChartService implements ThisWeekChartService {
  @override
  Future<ProvisionalWeekChart> load({
    required ChartType chartType,
    required DateTime referenceLocal,
  }) async {
    final week = const ChartWeekResolver().resolve(referenceLocal);

    ChartEntry entry(String id, int rank, int previous) => ChartEntry(
      entity: ChartEntitySnapshot(
        entityId: id,
        title: 'Song ${id.split('_').last}',
        artistName: 'Artist 1',
        albumTitle: 'Album 1',
      ),
      rank: rank,
      qualifiedStreamCount: 30 - rank,
      lastQualifiedAt: week.startUtc,
      previousFinalRank: previous,
      peakRank: 1,
      peakAchievedAt: week.startUtc,
      weeksOnChart: 1,
      movement: rank < previous ? ChartMovement.up : ChartMovement.down,
    );

    return ProvisionalWeekChart(
      snapshot: ChartSnapshot(
        id: 'this-week',
        chartType: chartType,
        weekStartUtc: week.startUtc,
        weekEndUtc: week.endUtc,
        entries: [
          entry('songs_1', 1, 3),
          entry('songs_2', 2, 1),
          entry('songs_3', 3, 2),
        ],
      ),
      bestSoFarRanks: const {'songs_1': 1, 'songs_2': 1, 'songs_3': 2},
    );
  }
}

ChartSnapshot _finalizedWeek(DateTime start, {required int ranks}) {
  final end = start.add(const Duration(days: 7));

  return ChartSnapshot(
    id: 'week-${start.toIso8601String()}',
    chartType: ChartType.songs,
    weekStartUtc: start,
    weekEndUtc: end,
    finalizedAt: end,
    entries: [
      for (var rank = 1; rank <= ranks; rank++)
        _weeklyEntry('songs_$rank', rank: rank),
    ],
  );
}

ChartEntry _weeklyEntry(String id, {required int rank}) {
  return ChartEntry(
    entity: ChartEntitySnapshot(
      entityId: id,
      title: 'Song ${id.split('_').last}',
      artistName: 'Artist 1',
      albumTitle: 'Album 1',
    ),
    rank: rank,
    qualifiedStreamCount: 300 - rank,
    lastQualifiedAt: DateTime.utc(2026, 9, 15),
    peakRank: rank,
    peakAchievedAt: DateTime.utc(2026, 9, 15),
    weeksOnChart: rank <= 100 ? 1 : 0,
    movement: ChartMovement.newEntry,
  );
}

ChartSnapshot _snapshot({
  required String id,
  required DateTime start,
  ChartType chartType = ChartType.songs,
  bool finalized = false,
  String? title,
}) {
  return ChartSnapshot(
    id: id,
    chartType: chartType,
    weekStartUtc: start,
    weekEndUtc: start.add(const Duration(days: 7)),
    finalizedAt: finalized ? start.add(const Duration(days: 7)) : null,
    entries: [
      ChartEntry(
        entity: ChartEntitySnapshot(
          entityId: '${chartType.name}_1',
          title: title ?? (chartType == ChartType.songs ? 'Song 1' : 'Album 1'),
          artistName: 'Artist 1',
          albumTitle: 'Album 1',
        ),
        rank: 1,
        qualifiedStreamCount: 12,
        lastQualifiedAt: start.add(const Duration(days: 2)),
        previousFinalRank: 3,
        peakRank: 1,
        peakAchievedAt: start,
        weeksOnChart: 4,
        movement: ChartMovement.up,
      ),
    ],
  );
}

class _FakeChartMomentRepository implements ChartMomentRepository {
  _FakeChartMomentRepository({this.events = const []});

  final List<ChartMomentEvent> events;

  @override
  Future<void> saveAll(Iterable<ChartMomentEvent> events) async {}

  @override
  Future<bool> publishFinalizedForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required Iterable<ChartMomentEvent> events,
  }) async => false;

  @override
  Future<ChartMomentEvent?> getById(String id) async {
    for (final event in events) {
      if (event.id == id) {
        return event;
      }
    }

    return null;
  }

  @override
  Future<List<ChartMomentEvent>> getRecent({int? limit}) async {
    if (limit == null || events.length <= limit) {
      return List<ChartMomentEvent>.unmodifiable(events);
    }

    return events.take(limit).toList(growable: false);
  }

  @override
  Future<List<ChartMomentEvent>> getPage({
    ChartMomentPageCursor? before,
    required int limit,
  }) async => momentPageOf(events, before: before, limit: limit);
}

/// Serves the given snapshots' entries as the all-time charts.
class _FakeAllTimeChartService implements AllTimeChartService {
  _FakeAllTimeChartService({required this.songs, required this.albums});

  final ChartSnapshot songs;
  final ChartSnapshot albums;

  @override
  Future<AllTimeChart> load({
    required ChartType chartType,
    required DateTime referenceLocal,
    ChartViewSize viewSize = ChartViewSize.top100,
  }) async {
    final source = chartType == ChartType.songs ? songs : albums;

    return AllTimeChart(
      chartType: source.chartType,
      comparisonStartUtc: source.weekStartUtc,
      entries: source.entries,
    );
  }
}

class _FakeChartFinalizationService implements ChartFinalizationService {
  @override
  Future<List<ChartSnapshot>> finalizeCompletedWeeks({
    required DateTime referenceLocal,
  }) async {
    return const [];
  }

  @override
  Future<List<ChartSnapshot>> finalizePreviousCompletedWeek({
    required DateTime referenceLocal,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChartSnapshot>> reconcileCompletedWeek(ChartWeek week) {
    throw UnimplementedError();
  }
}

class _FakeChartRepository implements ChartRepository {
  _FakeChartRepository({this.history = const []});

  final List<ChartSnapshot> history;

  @override
  Future<List<ChartSnapshot>> getHistory(
    ChartType chartType, {
    int? limit,
  }) async {
    final matching = history
        .where((snapshot) => snapshot.chartType == chartType)
        .toList(growable: false);

    if (limit == null || matching.length <= limit) {
      return matching;
    }

    return matching.take(limit).toList(growable: false);
  }

  @override
  Future<ChartSnapshot?> getById(String id) async => null;

  @override
  Future<ChartSnapshot?> getForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
  }) async {
    return null;
  }

  @override
  Future<void> replaceSnapshot(ChartSnapshot snapshot) async {}
}

class _FakeLibraryQueryRepository implements LibraryQueryRepository {
  _FakeLibraryQueryRepository({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
  });

  final List<LibraryTrack> tracks;
  final List<LibraryAlbum> albums;
  final List<LibraryArtist> artists;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks;
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async {
    return tracks.take(limit).toList(growable: false);
  }

  @override
  Future<LibraryTrack?> getTrackById(String songId) async {
    for (final track in tracks) {
      if (track.songId == songId) {
        return track;
      }
    }

    return null;
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return tracks
        .where((track) => track.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
    return tracks
        .where((track) => track.albumId == albumId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return albums;
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async {
    return albums.take(limit).toList(growable: false);
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    for (final album in albums) {
      if (album.albumId == albumId) {
        return album;
      }
    }

    return null;
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    return albums
        .where((album) => album.artistId == artistId)
        .toList(growable: false);
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return artists;
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    return null;
  }
}

/// Records every call that would change the queue or what is playing.
class _RecordingPlaybackEngine implements PlaybackEngine {
  final List<String> calls = [];

  @override
  Stream<PlaybackState> get states => const Stream.empty();

  @override
  PlaybackState get currentState => const PlaybackState();

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async => calls.add('loadQueue');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seek(Duration position) async => calls.add('seek');

  @override
  Future<void> skipNext() async => calls.add('skipNext');

  @override
  Future<void> skipPrevious() async => calls.add('skipPrevious');

  @override
  Future<void> skipToIndex(int index) async => calls.add('skipToIndex');

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async =>
      calls.add('insertTrack');

  @override
  Future<void> appendTrack(PlaybackTrack track) async =>
      calls.add('appendTrack');

  @override
  Future<void> removeTrackAt(int index) async => calls.add('removeTrackAt');

  @override
  Future<void> moveTrack({
    required int oldIndex,
    required int newIndex,
  }) async => calls.add('moveTrack');

  @override
  Future<void> setShuffleEnabled(bool enabled) async =>
      calls.add('setShuffleEnabled');

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async =>
      calls.add('setRepeatMode');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> dispose() async {}
}

/// Song Stats for any song: no chart history or listening, optionally the
/// library [track].
class _FakeSongStatsLoader implements SongStatsLoader {
  _FakeSongStatsLoader({this.track});

  final LibraryTrack? track;
  final List<String> requested = [];

  @override
  Future<SongStats> load(String songId) async {
    requested.add(songId);
    return SongStats(
      identity: SongStatsIdentity(
        songId: songId,
        title: track?.displayTitle ?? songId,
        artistLine: track?.creditLine ?? '',
        status: SongStatsStatus.of(track),
        track: track,
      ),
      chart: SongChartHistory.none,
      listening: SongListeningStats(
        streams: 0,
        listened: Duration.zero,
        allPlays: 0,
        firstPlayedAt: null,
        lastPlayedAt: null,
        weeks: const [],
      ),
    );
  }
}
