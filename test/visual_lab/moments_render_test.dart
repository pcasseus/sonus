// App Update 1.1: the real Moments feed (ChartsPage in Moments) and the
// expanded story, rendered with generated artwork at Galaxy S26 Ultra
// logical size, checked for layout (no overflow, every format present) in
// every accessibility mode, and written to review boards.
//
// Boards are written only with --dart-define=SONUS_LAB_OUT=<folder>
// (outside the repository). With SONUS_LAB_REFERENCE=<approved hybrid
// image> a side-by-side comparison board is written too. Fixture names
// follow the approved mockup; every picture is generated, and the facts
// are this fixture's own, not real chart data.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/core/design/sonus_typography.dart';
import 'package:sonus_next/features/charts/application/services/moment_chart_journey_service.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_event_type.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_scope.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_history_replay.dart';
import 'package:sonus_next/features/charts/domain/services/chart_ranking_engine.dart';
import 'package:sonus_next/features/charts/presentation/controllers/charts_controller.dart';
import 'package:sonus_next/features/charts/presentation/models/charts_presentation_mode.dart';
import 'package:sonus_next/features/charts/presentation/pages/charts_page.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/song_stats/application/song_stats_service.dart';

import '../features/charts/presentation/pages/charts_page_test.dart' as page;
import '../support/device_layout.dart';
import 'support/lab_board.dart';
import 'support/lab_harness.dart';

const String _out = String.fromEnvironment('SONUS_LAB_OUT');
const String _reference = String.fromEnvironment('SONUS_LAB_REFERENCE');

Finder _key(String key) => find.byKey(ValueKey<String>(key));

final DateTime _now = DateTime(2026, 11, 6, 12);

ChartEntitySnapshot _song(String id, String title, String artist) =>
    ChartEntitySnapshot(
      entityId: id,
      title: title,
      artistId: 'artist-$artist',
      artistName: _artistNames[artist]!,
      albumTitle: 'Album',
    );

const _artistNames = {
  'madison': 'Madison Beer',
  'tate': 'Tate McRae',
  'zara': 'Zara Larsson',
};

ChartMomentEvent _event(
  ChartMomentEventType type,
  ChartEntitySnapshot entity, {
  required Duration ago,
  String? source,
  ChartType chart = ChartType.songs,
  int? previousRank,
  int? currentRank,
  int? threshold,
  int? previousPeakRank,
  int? milestone,
  int streams = 64,
  ChartEntitySnapshot? related,
}) {
  final at = _now.subtract(ago).toUtc();
  final key =
      'alltime|${chart.name}|${type.name}|${entity.entityId}|'
      '${source ?? at.millisecondsSinceEpoch}|${threshold ?? ''}';
  return ChartMomentEvent(
    id: key,
    deduplicationKey: key,
    sourceId: source ?? 'play-${at.millisecondsSinceEpoch}',
    chartType: chart,
    scope: ChartMomentScope.allTime,
    eventType: type,
    entity: entity,
    relatedEntity: related,
    weekStartUtc: DateTime(2026, 11, 1).toUtc(),
    weekEndUtc: DateTime(2026, 11, 8).toUtc(),
    occurredAt: at,
    createdAt: at,
    previousRank: previousRank,
    currentRank: currentRank,
    threshold: threshold,
    previousPeakRank: previousPeakRank,
    currentPeakRank: currentRank,
    qualifiedStreamCount: streams,
    milestoneValue: milestone,
  );
}

class _Fixture {
  _Fixture() : art = LabArtworkFiles.ensure();

  final LabArtworkFiles art;

  late final angel = _song('song-angel', 'angel wings', 'madison');
  late final housewife = _song('song-housewife', 'Housewife', 'tate');
  late final bitter = _song('song-bitter', 'bittersweet', 'madison');
  late final exes = _song('song-exes', 'exes', 'tate');
  late final yes = _song('song-yes', 'yes baby', 'madison');
  late final midnight = const ChartEntitySnapshot(
    entityId: 'album-midnight',
    title: 'Midnight Sun (Girls Trip Deluxe)',
    artistId: 'artist-zara',
    artistName: 'Zara Larsson',
  );
  late final locket = const ChartEntitySnapshot(
    entityId: 'album-locket',
    title: 'locket',
    artistId: 'artist-madison',
    artistName: 'Madison Beer',
  );

  List<ChartMomentEvent> get events => [
    // A Feature Story: back to #1, passing the verified leader.
    _event(
      ChartMomentEventType.returnToNumberOne,
      angel,
      ago: const Duration(hours: 2),
      source: 'play-angel',
      previousRank: 2,
      currentRank: 1,
      threshold: 1,
      previousPeakRank: 1,
      related: housewife,
    ),
    // A Chart Bulletin on the album chart.
    _event(
      ChartMomentEventType.rankRise,
      midnight,
      chart: ChartType.albums,
      ago: const Duration(hours: 11),
      source: 'play-midnight',
      previousRank: 14,
      currentRank: 12,
      previousPeakRank: 9,
    ),
    // A breakthrough chart move: climb, first Top 25, new peak.
    for (final type in [
      ChartMomentEventType.rankRise,
      ChartMomentEventType.newPeak,
    ])
      _event(
        type,
        bitter,
        ago: const Duration(hours: 26),
        source: 'play-bitter',
        previousRank: 37,
        currentRank: 23,
        previousPeakRank: 30,
      ),
    _event(
      ChartMomentEventType.firstThresholdEntry,
      bitter,
      ago: const Duration(hours: 26),
      source: 'play-bitter',
      previousRank: 37,
      currentRank: 23,
      threshold: 25,
      previousPeakRank: 30,
    ),
    // A Milestone Spotlight: 50 streams.
    _event(
      ChartMomentEventType.lifetimeStreamMilestone,
      locket,
      chart: ChartType.albums,
      ago: const Duration(hours: 30),
      source: 'play-locket',
      currentRank: 4,
      previousRank: 4,
      milestone: 50,
      streams: 50,
    ),
    // A #1 hold (Spotlight).
    _event(
      ChartMomentEventType.numberOneDayHold,
      housewife,
      ago: const Duration(hours: 36),
      source: 'day:2026-11-04',
      previousRank: 1,
      currentRank: 1,
      threshold: 1,
      previousPeakRank: 1,
      milestone: 6,
      streams: 140,
    ),
    // A Hot 100 exit, still on Bubbling Under.
    _event(
      ChartMomentEventType.thresholdExit,
      exes,
      ago: const Duration(hours: 50),
      source: 'exit:play-x:song-exes',
      previousRank: 100,
      currentRank: 101,
      threshold: 100,
      previousPeakRank: 41,
      milestone: 18,
    ),
    // A Hot 100 debut (bulletin).
    _event(
      ChartMomentEventType.debut,
      yes,
      ago: const Duration(hours: 60),
      source: 'play-yes',
      currentRank: 94,
    ),
  ];

  LibraryTrack _track(ChartEntitySnapshot s, String album, String? art) =>
      LibraryTrack(
        songId: s.entityId,
        title: s.title,
        artistId: s.artistId!,
        artistName: s.artistName,
        albumId: album,
        albumTitle: album,
        albumEditionId: '$album-standard',
        albumEditionTitle: 'Standard',
        albumEditionType: AlbumEditionType.standard,
        trackNumber: 1,
        durationSeconds: 200,
        isSingle: false,
        featuredArtists: const [],
        dateAdded: DateTime.utc(2026, 9, 1),
        isAvailable: true,
        filePath: 'C:/Music/${s.entityId}.mp3',
        artworkPath: art,
      );

  List<LibraryTrack> get tracks => [
    _track(angel, 'album-locket', art.cover('hue_0')),
    _track(housewife, 'album-tate', art.cover('warm')),
    _track(bitter, 'album-locket', art.cover('hue_0')),
    _track(exes, 'album-tate', art.cover('warm')),
    _track(yes, 'album-locket', art.cover('hue_0')),
  ];

  List<LibraryAlbum> get albums => [
    LibraryAlbum(
      albumId: 'album-locket',
      title: 'locket',
      artistId: 'artist-madison',
      artistName: 'Madison Beer',
      trackCount: 15,
      dateAdded: DateTime.utc(2026, 9, 1),
      artworkPath: art.cover('hue_0'),
    ),
    LibraryAlbum(
      albumId: 'album-midnight',
      title: 'Midnight Sun (Girls Trip Deluxe)',
      artistId: 'artist-zara',
      artistName: 'Zara Larsson',
      trackCount: 20,
      dateAdded: DateTime.utc(2026, 9, 1),
      artworkPath: art.cover('hue_2'),
    ),
    LibraryAlbum(
      albumId: 'album-tate',
      title: "So Close To What",
      artistId: 'artist-tate',
      artistName: 'Tate McRae',
      trackCount: 12,
      dateAdded: DateTime.utc(2026, 9, 1),
      artworkPath: art.cover('warm'),
    ),
  ];

  List<LibraryArtist> get artists => [
    for (final (id, variant) in [
      ('madison', LabVariant.warm),
      ('tate', LabVariant.neutral),
      ('zara', LabVariant.cool),
    ])
      LibraryArtist(
        artistId: 'artist-$id',
        name: _artistNames[id]!,
        albumCount: 1,
        songCount: 3,
        dateAdded: DateTime.utc(2026, 9, 1),
        topArtistsArtworkPath: art.portrait(variant),
      ),
  ];

  /// A journey replayed from fixture plays by the real all-time replay:
  /// "angel wings" climbs past "Housewife" to #1 over eight days.
  Future<MomentChartJourney?> journey(ChartType type, String id) async {
    final events = <ChartRankingEvent>[];
    var n = 0;
    void play(String entity, DateTime day, int times) {
      for (var i = 0; i < times; i++) {
        events.add(
          ChartRankingEvent(
            entityId: entity,
            qualifiedAt: day.add(Duration(minutes: 10 * n)).toUtc(),
            sourceEventId: 'p${n++}',
          ),
        );
      }
    }

    final start = DateTime(2026, 10, 29, 9);
    for (var i = 0; i < 10; i++) {
      play('song-filler-$i', start, 20 - i);
    }
    play('song-housewife', start, 30);
    play('song-angel', start, 12);
    for (var d = 1; d <= 8; d++) {
      final day = DateTime(2026, 10, 29 + d, 9);
      play('song-housewife', day, 3);
      play('song-angel', day, d < 3 ? 4 : 9);
    }
    final result = const AllTimeHistoryReplay().run(
      events: events,
      referenceLocal: _now,
      collectAchievements: false,
      collectDayStandings: {id},
    );
    return MomentChartJourney(
      chartType: type,
      entityId: id,
      days: result.dayStandings[id] ?? const [],
      totals: result.daysOf(id),
      peakRank: result.trackedPeaks[id],
      firstChartedAt: result.trackedFirstCharted[id],
      currentRank: result.trackedRanks[id],
    );
  }
}

Future<ChartsController> _controller(_Fixture f) async {
  final controller = ChartsController(
    allTimeCharts: page.ChartsTestAllTime(
      songs: page.chartsTestSnapshot(
        id: 'songs',
        start: DateTime.utc(2026, 11, 1),
      ),
      albums: page.chartsTestSnapshot(
        id: 'albums',
        start: DateTime.utc(2026, 11, 1),
        chartType: ChartType.albums,
      ),
    ),
    finalization: page.ChartsTestFinalization(),
    charts: page.ChartsTestChartRepository(),
    library: page.ChartsTestLibrary(
      tracks: f.tracks,
      albums: f.albums,
      artists: f.artists,
    ),
    moments: page.ChartsTestMoments(events: f.events),
    now: () => _now,
    momentRules: () async => ChartMomentRules(
      devicePolishFromUtc: DateTime.utc(2026, 11, 1),
      chronicleFromUtc: DateTime.utc(2026, 11, 1),
    ),
  );
  await controller.load();
  controller.selectPresentationMode(ChartsPresentationMode.moments);
  return controller;
}

Future<ChartsController> _pump(
  WidgetTester tester,
  _Fixture f, {
  SonusAppearanceSpec spec = const SonusAppearanceSpec(),
  LabDevice device = LabDevice.s26,
  Size? surface,
}) async {
  setDevice(tester, size: surface ?? device.size, ratio: device.ratio);
  final controller = await _controller(f);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<PlaybackCoordinator?>.value(value: null),
        Provider<SongStatsLoader?>.value(value: null),
        Provider<MomentJourneyLoader?>.value(value: f.journey),
      ],
      child: ChangeNotifierProvider<ChartsController?>.value(
        value: controller,
        child: MaterialApp(
          // A new app per pump: an earlier story route never stays open.
          key: UniqueKey(),
          debugShowCheckedModeBanner: false,
          theme: labTheme(spec),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => RepaintBoundary(
            key: labCaptureKey,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(device.textScale)),
              child: child!,
            ),
          ),
          home: const Scaffold(body: ChartsPage()),
        ),
      ),
    ),
  );
  await settleLab(tester);
  return controller;
}

Future<void> _openFeature(WidgetTester tester) async {
  final open = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('moment-post-open-') &&
        (w.key! as ValueKey<String>).value.contains('play-angel'),
  );
  await tester.ensureVisible(open.first);
  await tester.tap(open.first);
  await settleLab(tester);
}

const _modes = <String, SonusAppearanceSpec>{
  'Default': SonusAppearanceSpec(),
  'Phone appearance (Concrete & Spray, Street Bold, Expressive, High contrast)':
      SonusAppearanceSpec(
        themeId: SonusThemeId.concreteSpray,
        typography: SonusTypographyPreset.streetBold,
        decoration: SonusDecorationIntensity.expressive,
        highContrast: true,
      ),
  'High contrast': SonusAppearanceSpec(highContrast: true),
  'Bold text': SonusAppearanceSpec(boldText: true),
  'Low effects': SonusAppearanceSpec(lowEffects: true),
  'Reduce motion': SonusAppearanceSpec(reduceMotion: true),
  'Decoration off': SonusAppearanceSpec(
    decoration: SonusDecorationIntensity.off,
  ),
};

void main() {
  setUpAll(loadBaselineFonts);
  final f = _Fixture();

  group('the Moments feed', () {
    testWidgets('shows a Feature Story, Bulletins and Spotlights', (
      tester,
    ) async {
      await _pump(tester, f, surface: const Size(384, 3400));

      expect(_key('charts-moments-eyebrow'), findsOneWidget);
      expect(find.text('Moments'), findsWidgets);
      expect(find.text('Your chart story, in real time.'), findsOneWidget);
      expect(find.text('FEATURE STORY'), findsOneWidget);
      expect(find.text('BREAKTHROUGH'), findsOneWidget);
      expect(find.text('#1 HOLD'), findsOneWidget);
      expect(find.text('MILESTONE'), findsOneWidget);
      expect(find.text('CHART EXIT'), findsOneWidget);
      expect(find.text('6 DAYS AT #1'), findsOneWidget);
      expect(find.text('18 DAYS ON HOT 100'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final device in [
      LabDevice.small,
      LabDevice.s26,
      LabDevice.large,
      LabDevice.s26.withText(1.3),
      LabDevice.s26.withText(2.0),
    ]) {
      for (final MapEntry(key: name, value: spec) in _modes.entries) {
        testWidgets('lays out without overflow: ${device.name}, $name', (
          tester,
        ) async {
          await _pump(
            tester,
            f,
            spec: spec,
            device: device,
            surface: Size(device.size.width, 4200),
          );
          expect(tester.takeException(), isNull);
          await _openFeature(tester);
          expect(tester.takeException(), isNull);
          expect(find.text('Chart Journey'), findsOneWidget);
        });
      }
    }

    testWidgets('every theme renders the feed', (tester) async {
      for (final theme in SonusThemeId.values) {
        await _pump(
          tester,
          f,
          spec: SonusAppearanceSpec(themeId: theme),
          surface: const Size(384, 3400),
        );
        expect(tester.takeException(), isNull, reason: theme.label);
      }
    });
  });

  group('the expanded story', () {
    testWidgets('shows facts, a verified journey and working links', (
      tester,
    ) async {
      await _pump(tester, f, surface: const Size(384, 2600));
      await _openFeature(tester);

      expect(find.text('Current Rank'), findsOneWidget);
      expect(find.text('Movement'), findsOneWidget);
      expect(find.text('Chart Journey'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'moment-story-journey-',
              ),
        ),
        findsOneWidget,
      );
      expect(find.text('Total Days on Chart'), findsOneWidget);
      expect(find.text('Related'), findsOneWidget);
      expect(_key('moment-story-related-Artist'), findsOneWidget);
      expect(_key('moment-story-related-Album'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group(
    'boards',
    skip: _out.isEmpty ? 'set --dart-define=SONUS_LAB_OUT' : null,
    () {
      testWidgets('feed, story, accessibility and themes', (tester) async {
        Directory(_out).createSync(recursive: true);

        // Feed: the S26 viewport and the whole feed.
        await _pump(tester, f);
        final viewport = (await captureLab(tester, pixelRatio: 2)).$2;
        await _pump(tester, f, surface: const Size(384, 2900));
        final whole = (await captureLab(tester, pixelRatio: 2)).$2;
        await _pump(
          tester,
          f,
          spec: _modes.values.elementAt(1),
          surface: const Size(384, 2900),
        );
        final phone = (await captureLab(tester, pixelRatio: 2)).$2;
        await writeBoard(
          tester,
          '$_out/au11_moments_feed.png',
          'Moments feed (S26 Ultra 384x832dp)',
          [
            [
              BoardCell('S26 viewport', viewport),
              BoardCell('Whole feed', whole),
              BoardCell("Phone's appearance (High contrast)", phone),
            ],
          ],
          cellHeight: 1700,
        );

        // Expanded story: top and scrolled.
        await _pump(tester, f, surface: const Size(384, 832));
        await _openFeature(tester);
        final storyTop = (await captureLab(tester, pixelRatio: 2)).$2;
        await _pump(tester, f, surface: const Size(384, 2100));
        await _openFeature(tester);
        final storyWhole = (await captureLab(tester, pixelRatio: 2)).$2;
        await _pump(
          tester,
          f,
          spec: _modes.values.elementAt(1),
          surface: const Size(384, 2100),
        );
        await _openFeature(tester);
        final storyHc = (await captureLab(tester, pixelRatio: 2)).$2;
        await writeBoard(
          tester,
          '$_out/au11_moments_story.png',
          'Expanded story and Chart Journey',
          [
            [
              BoardCell('S26 viewport', storyTop),
              BoardCell('Whole story', storyWhole),
              BoardCell("Phone's appearance (High contrast)", storyHc),
            ],
          ],
          cellHeight: 1700,
        );

        // Accessibility modes and text sizes.
        final cells = <BoardCell>[];
        for (final MapEntry(key: name, value: spec) in _modes.entries.skip(2)) {
          await _pump(tester, f, spec: spec);
          cells.add(
            BoardCell(name, (await captureLab(tester, pixelRatio: 2)).$2),
          );
        }
        for (final scale in [1.3, 2.0]) {
          await _pump(tester, f, device: LabDevice.s26.withText(scale));
          cells.add(
            BoardCell(
              'Text ${scale}x',
              (await captureLab(tester, pixelRatio: 2)).$2,
            ),
          );
        }
        await writeBoard(
          tester,
          '$_out/au11_moments_accessibility.png',
          'Accessibility modes',
          [cells.sublist(0, 4), cells.sublist(4)],
        );

        // Every theme.
        final themes = <BoardCell>[];
        for (final theme in SonusThemeId.values) {
          await _pump(tester, f, spec: SonusAppearanceSpec(themeId: theme));
          themes.add(
            BoardCell(
              theme.label,
              (await captureLab(tester, pixelRatio: 2)).$2,
            ),
          );
        }
        await writeBoard(
          tester,
          '$_out/au11_moments_themes.png',
          'All nine themes',
          [themes.sublist(0, 5), themes.sublist(5)],
        );

        // Side by side with the approved hybrid reference.
        if (_reference.isNotEmpty) {
          final ref = await loadImageFile(tester, _reference);
          if (ref != null) {
            await writeBoard(
              tester,
              '$_out/au11_moments_vs_reference.png',
              'Approved hybrid (left) vs Flutter render',
              [
                [
                  BoardCell('Approved hybrid reference', ref),
                  BoardCell('Feed (S26)', viewport),
                  BoardCell('Story (S26)', storyTop),
                ],
              ],
              cellHeight: 1500,
            );
          }
        }
      });
    },
  );
}
