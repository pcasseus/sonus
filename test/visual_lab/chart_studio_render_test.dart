// App Update 1.3 Chart Studio: the real career chart (ChartsPage) rendered
// at Galaxy S26 Ultra logical size with generated artwork, collapsed and
// with an entry expanded, checked for layout in accessibility modes and
// written to review boards.
//
// Boards are written only with --dart-define=SONUS_LAB_OUT=<folder>
// (outside the repository). With SONUS_LAB_REFERENCE=<approved reference
// image> the reference is placed beside the renders. Titles follow the
// approved reference; every picture is generated, and every number is this
// fixture's own, not real chart data.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/charts/application/services/all_time_chart_service.dart';
import 'package:sonus_next/features/charts/domain/entities/all_time_chart.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/all_time_entry_stats.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/charts/domain/models/chart_type.dart';
import 'package:sonus_next/features/charts/domain/models/chart_view_size.dart';
import 'package:sonus_next/features/charts/domain/moments/chart_moment_rules.dart';
import 'package:sonus_next/features/charts/domain/services/all_time_history_replay.dart';
import 'package:sonus_next/features/charts/presentation/controllers/charts_controller.dart';
import 'package:sonus_next/features/charts/presentation/pages/charts_page.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
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

final DateTime _now = DateTime(2026, 11, 16, 12);
final DateTime _weekStart = DateTime.utc(2026, 11, 15);

/// (title, artist, album, single, current, last week, career peak).
const _songs = [
  ('angel wings', 'Madison Beer', 'locket', true, 1, 1, 1),
  ('Small Doses', 'Madison Beer', 'locket', false, 2, 3, 2),
  ('Housewife', 'Madison Beer', 'locket', false, 3, 2, 2),
  (
    'Sports Car | Nobody\'s Girl Outro [Live From The Sonus Session]',
    'Madison Beer',
    'locket',
    false,
    4,
    4,
    3,
  ),
  ('bad enough', 'Madison Beer', 'locket', false, 5, null, 5),
  ('free', 'Madison Beer', 'locket', false, 6, 9, 6),
  ('For All Eternity', 'Tate McRae', 'Anatomy of a Popstar', false, 7, 5, 4),
  ('Dead', 'Madison Beer', 'Dead', true, 8, 8, 8),
  ('Lush Life', 'Zara Larsson', 'So Good', false, 9, 12, 9),
  ('greedy', 'Tate McRae', 'THINK LATER', false, 10, 7, 3),
  ('Ruin My Life', 'Zara Larsson', 'Poster Girl', false, 11, 10, 10),
  ('Reckless', 'Madison Beer', 'Life Support', false, 12, 14, 11),
];

String _id(int i) => 'songs_${i + 1}';

ChartEntitySnapshot _entity(int i) => ChartEntitySnapshot(
  entityId: _id(i),
  title: _songs[i].$1,
  artistId: 'artist-${_songs[i].$2}',
  artistName: _songs[i].$2,
  albumTitle: _songs[i].$3,
);

ChartEntry _entry(int i) {
  final s = _songs[i];
  final previous = s.$6;
  return ChartEntry(
    entity: _entity(i),
    rank: s.$5,
    qualifiedStreamCount: 412 - i * 23,
    lastQualifiedAt: _weekStart.add(const Duration(hours: 20)),
    peakRank: s.$7,
    peakAchievedAt: DateTime.utc(2026, 10, 25),
    weeksOnChart: 6,
    previousFinalRank: previous,
    movement: previous == null
        ? ChartMovement.reentry
        : previous > s.$5
        ? ChartMovement.up
        : previous < s.$5
        ? ChartMovement.down
        : ChartMovement.same,
  );
}

/// Six finalized weeks; "bad enough" is absent from two of them.
List<ChartSnapshot> _history() {
  final weeks = <ChartSnapshot>[];
  for (var w = 0; w < 6; w++) {
    final start = DateTime.utc(2026, 10, 4).add(Duration(days: 7 * w));
    final order =
        [
          for (var i = 0; i < _songs.length; i++)
            if (!(i == 4 && (w == 2 || w == 5))) i,
        ]..sort(
          (a, b) => ((a * 7 + w * (a.isEven ? 3 : -2)) % 29).compareTo(
            (b * 7 + w * (b.isEven ? 3 : -2)) % 29,
          ),
        );
    weeks.add(
      ChartSnapshot(
        id: 'week-$w',
        chartType: ChartType.songs,
        weekStartUtc: start,
        weekEndUtc: start.add(const Duration(days: 7)),
        finalizedAt: start.add(const Duration(days: 7)),
        entries: [
          for (var r = 0; r < order.length; r++)
            ChartEntry(
              entity: _entity(order[r]),
              rank: r + 1,
              qualifiedStreamCount: 90 - r * 5,
              lastQualifiedAt: start.add(const Duration(days: 3)),
              peakRank: r + 1,
              peakAchievedAt: start,
              weeksOnChart: w + 1,
              movement: ChartMovement.same,
            ),
        ],
      ),
    );
  }
  return weeks;
}

class _AllTime implements AllTimeChartService {
  @override
  Future<AllTimeChart> load({
    required ChartType chartType,
    required DateTime referenceLocal,
    ChartViewSize viewSize = ChartViewSize.top100,
  }) async => AllTimeChart(
    chartType: chartType,
    comparisonStartUtc: _weekStart,
    entries: chartType == ChartType.songs
        ? [for (var i = 0; i < _songs.length; i++) _entry(i)]
        : const [],
    stats: {
      for (var i = 0; i < _songs.length; i++)
        _id(i): AllTimeEntryStats(
          streamsThisWeek: 40 - i * 2,
          streamsSameTimeLastWeek: i == 4 ? 0 : 38 - i,
          zones: ZoneWeeks({
            3: i < 3 ? 3 - i : 0,
            5: i < 5 ? 5 - i : 0,
            10: 6,
            25: 6,
          }),
        ),
    },
  );
}

LibraryTrack _track(int i, LabArtworkFiles art) {
  final s = _songs[i];
  return LibraryTrack(
    songId: _id(i),
    title: s.$1,
    artistId: 'artist-${s.$2}',
    artistName: s.$2,
    albumId: 'album-${s.$3}',
    albumTitle: s.$3,
    albumEditionId: 'edition-${s.$3}',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: i + 1,
    durationSeconds: 180,
    isSingle: s.$4,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 9, 1),
    isAvailable: true,
    filePath: 'C:/Music/${_id(i)}.mp3',
    // One song without artwork: the placeholder.
    artworkPath: i == 5
        ? null
        : art.cover(
            const ['hue_0', 'hue_1', 'hue_2', 'cool', 'warm', 'neutral'][i % 6],
          ),
  );
}

LibraryAlbum _album(String title) => LibraryAlbum(
  albumId: 'album-$title',
  title: title,
  artistId: 'artist',
  artistName: 'Artist',
  trackCount: 1,
  dateAdded: DateTime.utc(2026, 9, 1),
);

Future<ChartsController> _pump(
  WidgetTester tester, {
  SonusAppearanceSpec spec = const SonusAppearanceSpec(),
  LabDevice device = LabDevice.s26,
  Size? surface,
}) async {
  setDevice(tester, size: surface ?? device.size, ratio: device.ratio);
  final art = LabArtworkFiles.ensure();
  final controller = ChartsController(
    allTimeCharts: _AllTime(),
    finalization: page.ChartsTestFinalization(),
    charts: page.ChartsTestChartRepository(history: _history()),
    library: page.ChartsTestLibrary(
      tracks: [for (var i = 0; i < _songs.length; i++) _track(i, art)],
      albums: [
        for (final t in {for (final s in _songs) s.$3}) _album(t),
      ],
      artists: const [],
    ),
    moments: page.ChartsTestMoments(),
    now: () => _now,
    momentRules: () async =>
        ChartMomentRules(activatedAtUtc: DateTime.utc(2026, 11, 1)),
  );
  addTearDown(controller.dispose);
  await controller.load();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<PlaybackCoordinator?>.value(value: null),
        Provider<SongStatsLoader?>.value(value: null),
      ],
      child: ChangeNotifierProvider<ChartsController?>.value(
        value: controller,
        child: MaterialApp(
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

ScrollController _scrollOf(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.byType(CustomScrollView).first)
    .controller!;

/// Steps down the page until [target] is built (rows far below are not).
Future<void> _build(WidgetTester tester, Finder target) async {
  final scroll = _scrollOf(tester);
  while (target.evaluate().isEmpty &&
      scroll.offset < scroll.position.maxScrollExtent) {
    scroll.jumpTo(
      (scroll.offset + 300).clamp(0.0, scroll.position.maxScrollExtent),
    );
    await tester.pump();
  }
}

/// Scrolls the chart's first row to just under the top of the screen.
Future<void> _scrollToRows(WidgetTester tester) async {
  final first = _key('charts-entry-songs_1');
  await _build(tester, first);
  final scroll = _scrollOf(tester);
  final top = tester.getRect(first).top;
  scroll.jumpTo(
    (scroll.offset + top - 24).clamp(0.0, scroll.position.maxScrollExtent),
  );
  await settleLab(tester);
}

Future<void> _expand(WidgetTester tester, String id) async {
  final toggle = _key('charts-row-expand-$id');
  await _build(tester, toggle);
  await tester.ensureVisible(toggle);
  await tester.pump();
  await tester.tap(toggle);
  await settleLab(tester);
}

const _accessibility = <String, SonusAppearanceSpec>{
  'High contrast': SonusAppearanceSpec(highContrast: true),
  'Reduce motion': SonusAppearanceSpec(reduceMotion: true),
  'Low effects': SonusAppearanceSpec(lowEffects: true),
  'Decoration off': SonusAppearanceSpec(
    decoration: SonusDecorationIntensity.off,
  ),
};

void main() {
  setUpAll(loadBaselineFonts);

  group('layout', () {
    for (final device in [
      ...LabDevice.phones,
      LabDevice.s26.withText(1.3),
      LabDevice.s26.withText(2),
      const LabDevice('320x640', Size(320, 640), 3.0),
      const LabDevice('320x640', Size(320, 640), 3.0).withText(1.3),
    ]) {
      testWidgets('collapsed and expanded without overflow: ${device.name}', (
        tester,
      ) async {
        await _pump(tester, device: device);
        await _scrollToRows(tester);
        expect(tester.takeException(), isNull);
        await _expand(tester, 'songs_1');
        expect(tester.takeException(), isNull);
        await _expand(tester, 'songs_4');
        expect(tester.takeException(), isNull);
      });
    }
    for (final MapEntry(key: name, value: spec) in _accessibility.entries) {
      testWidgets('expanded without overflow: $name', (tester) async {
        await _pump(tester, spec: spec);
        await _scrollToRows(tester);
        await _expand(tester, 'songs_1');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group(
    'boards',
    skip: _out.isEmpty ? 'set --dart-define=SONUS_LAB_OUT' : null,
    () {
      testWidgets('Chart Studio', (tester) async {
        Directory(_out).createSync(recursive: true);
        Future<ui.Image> shot() async =>
            (await captureLab(tester, pixelRatio: 2)).$2;

        await _pump(tester);
        await _scrollToRows(tester);
        final collapsed = await shot();
        await _expand(tester, 'songs_1');
        final first = await shot();
        await _expand(tester, 'songs_4');
        final fourth = await shot();

        await _pump(tester, device: LabDevice.small.withText(1.3));
        await _scrollToRows(tester);
        await _expand(tester, 'songs_1');
        final small = await shot();

        await _pump(tester, spec: _accessibility['High contrast']!);
        await _scrollToRows(tester);
        await _expand(tester, 'songs_1');
        final contrast = await shot();

        final reference = <BoardCell>[];
        if (_reference.isNotEmpty && File(_reference).existsSync()) {
          final codec = await tester.runAsync(
            () => ui.instantiateImageCodec(File(_reference).readAsBytesSync()),
          );
          final frame = await tester.runAsync(codec!.getNextFrame);
          reference.add(BoardCell('Approved reference', frame!.image));
        }

        await writeBoard(
          tester,
          '$_out/chart_studio.png',
          'Chart Studio: career chart (S26 Ultra 384x832dp)',
          [
            [
              ...reference,
              BoardCell('Collapsed', collapsed),
              BoardCell('#1 expanded', first),
              BoardCell('#4 expanded (long title)', fourth),
            ],
            [
              BoardCell('360x780, 1.3x text, #1 expanded', small),
              BoardCell('High contrast, #1 expanded', contrast),
            ],
          ],
          cellHeight: 1664,
        );
      });
    },
  );
}
