import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/pages/album_profile_page.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/charts/application/services/chart_finalization_service.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/domain/entities/all_time_chart.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_moment_repository.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_repository.dart';
import 'package:sonus_next/features/charts/domain/models/chart_week.dart';
import 'package:sonus_next/features/charts/presentation/controllers/charts_controller.dart';
import 'package:sonus_next/features/charts/presentation/news/moment_post_card.dart';
import 'package:sonus_next/features/charts/presentation/pages/charts_page.dart';

void main() {
  testWidgets('renders branded Hot 100 controls and the all-time chart', (
    tester,
  ) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    expect(find.text('SONUS'), findsOneWidget);
    expect(find.text('Hot 100'), findsOneWidget);

    expect(find.text('Songs'), findsWidgets);
    expect(find.text('Albums'), findsOneWidget);

    expect(find.text('Top 10'), findsOneWidget);
    expect(find.text('Top 25'), findsOneWidget);
    expect(find.text('Top 50'), findsOneWidget);
    expect(find.text('Top 75'), findsOneWidget);
    expect(find.text('Top 100'), findsOneWidget);
    expect(find.text('Top 200'), findsOneWidget);

    expect(find.text('ALL TIME'), findsOneWidget);
    expect(find.text('All time'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
    expect(find.textContaining('Last week'), findsNothing);
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Artist 1 • Album 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('charts-spotlight-songs_1')),
      findsOneWidget,
    );
    expect(find.text('LIFETIME STREAMS'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('ALL-TIME PEAK'), findsOneWidget);
    expect(find.text('#1'), findsWidgets);
    expect(find.text('WEEKLY CHANGE'), findsOneWidget);
    expect(find.text('WEEKS IN TOP 3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('charts-movement-legend')),
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
    expect(find.text('ALL TIME'), findsNothing);
  });

  testWidgets('album segment switches chart type', (tester) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    await tester.tap(find.text('Albums'));
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

  testWidgets('live song tap opens chart track actions', (tester) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    await tester.tap(
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

  testWidgets('historical song row remains display-only', (tester) async {
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
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('charts-entry-songs_1')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsNothing);
    expect(find.text('Add to queue'), findsNothing);
  });
  testWidgets('blocked live song stays visible but is not interactive', (
    tester,
  ) async {
    final controller = await _controller(tracks: [_track(isBlocked: true)]);

    await _pumpPage(tester, controller);

    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('BLACKLISTED'), findsOneWidget);

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
    expect(find.text('UNAVAILABLE'), findsOneWidget);

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
    expect(find.text('Artist 1 • Album 1'), findsOneWidget);
    expect(find.text('HISTORICAL'), findsOneWidget);

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
    expect(find.text('Artist 1'), findsOneWidget);

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
  testWidgets('Top 200 explains extended standings', (tester) async {
    final controller = await _controller();

    await _pumpPage(tester, controller);

    await tester.tap(find.byKey(const ValueKey<String>('charts-size-200')));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('charts-extended-notice')),
      findsOneWidget,
    );

    expect(
      find.text(
        'Top 100 is the official chart. Positions 101\u2013200 are extended standings.',
      ),
      findsOneWidget,
    );
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
          0,
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

    testWidgets('a labelled boundary separates #100 from extended #101', (
      tester,
    ) async {
      final controller = await _controller(
        live: _rankedSnapshot(102, from: 99),
      );

      await _pumpPage(tester, controller);

      const divider = ValueKey<String>('charts-extended-divider');
      expect(find.text('Extended standings · 101–200'), findsOneWidget);

      final dividerTop = tester.getTopLeft(find.byKey(divider)).dy;
      final official = find.byKey(
        const ValueKey<String>('charts-entry-songs_100'),
      );
      final extended = find.byKey(
        const ValueKey<String>('charts-entry-songs_101'),
      );

      expect(tester.getBottomLeft(official).dy, lessThanOrEqualTo(dividerTop));
      expect(tester.getTopLeft(extended).dy, greaterThan(dividerTop));

      // Official entries are never badged as extended, and extended ones are.
      expect(
        find.byKey(const ValueKey<String>('charts-extended-songs_100')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('charts-extended-songs_101')),
        findsOneWidget,
      );
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
        final controller = await _controller(live: _rankedSnapshot(3));

        await _pumpPage(
          tester,
          controller,
          theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
          size: const Size(320, 2400),
          textScale: 2,
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Hot 100'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('charts-entry-songs_1')),
          findsOneWidget,
        );
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

    expect(find.text('Song 1 reaches a new peak of #3'), findsOneWidget);
    expect(find.text('Song 1 earns a new weekly peak of #3.'), findsOneWidget);
    expect(find.text('WEEKLY HOT 100 · FINAL'), findsOneWidget);
    expect(find.text('Sonus Daily'), findsOneWidget);
    expect(find.text('NEW PEAK'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('HOT 100 #3'), findsOneWidget);
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

    expect(_postPart('portrait'), findsOneWidget);
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
    expect(
      _postPart('portrait'),
      findsNothing,
      reason: 'without a portrait the artwork fills the collage',
    );
  });

  testWidgets('an all-time Moment says all-time, never weekly', (tester) async {
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

    expect(find.text('Song 1 takes #1 all-time'), findsOneWidget);
    expect(
      find.text(
        'Song 1 tops the all-time Sonus Hot 100 for the first time with 42 lifetime streams.',
      ),
      findsOneWidget,
    );
    expect(find.text('ALL-TIME HOT 100'), findsOneWidget);
    expect(find.text('ALL-TIME #1'), findsOneWidget);
    expect(find.text('NUMBER ONE'), findsOneWidget);
    expect(find.text('@sonusdaily · 3h'), findsOneWidget);
    expect(find.textContaining('weekly'), findsNothing);
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

  testWidgets('LIVE Moment uses provisional presentation', (tester) async {
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

    expect(find.text('Song 1 reaches a new peak of #3'), findsOneWidget);
    expect(
      find.text('Song 1 rises to #3 on this week’s Sonus Hot 100.'),
      findsOneWidget,
    );
    expect(find.text('WEEKLY HOT 100 · THIS WEEK'), findsOneWidget);
    expect(find.text('HOT 100 #3'), findsOneWidget);
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
}

Future<ChartsController> _controller({
  ChartSnapshot? live,
  List<ChartSnapshot> history = const [],
  List<LibraryTrack>? tracks,
  List<LibraryAlbum>? albums,
  List<LibraryArtist> artists = const [],
  List<ChartMomentEvent> moments = const [],
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
}) async {
  await tester.binding.setSurfaceSize(size);

  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ChangeNotifierProvider<ChartsController?>.value(
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
    featuredArtists: const [],
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
}) {
  final weekStart = DateTime.utc(2026, 9, 27);
  final at = occurredAt ?? DateTime.utc(2026, 10, 4, 1);

  return ChartMomentEvent(
    id: id,
    deduplicationKey: id,
    sourceId: 'source-$id',
    chartType: ChartType.songs,
    scope: scope,
    eventType: type,
    entity: ChartEntitySnapshot(
      entityId: 'songs_1',
      title: 'Song 1',
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

ChartSnapshot _snapshot({
  required String id,
  required DateTime start,
  ChartType chartType = ChartType.songs,
  bool finalized = false,
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
          title: chartType == ChartType.songs ? 'Song 1' : 'Album 1',
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
  Future<void> replaceFinalizedForWeek({
    required ChartType chartType,
    required DateTime weekStartUtc,
    required Iterable<ChartMomentEvent> events,
  }) async {}

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
