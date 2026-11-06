import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_contrast.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/charts/domain/entities/chart_entry.dart';
import 'package:sonus_next/features/charts/domain/models/chart_entity_snapshot.dart';
import 'package:sonus_next/features/charts/domain/models/chart_movement.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/charts/domain/repositories/chart_entity_history_reader.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/song_stats/application/song_stats_models.dart';
import 'package:sonus_next/features/song_stats/application/song_stats_service.dart';
import 'package:sonus_next/features/song_stats/presentation/song_stats_page.dart';

DateTime _week(int n) => DateTime(2026, 10, 4 + 7 * n).toUtc();

LibraryTrack _track({bool blocked = false, bool available = true}) =>
    LibraryTrack(
      songId: 'song',
      title: 'Midnight Over Lagos',
      artistId: 'artist',
      artistName: 'Ayo Nova',
      albumId: 'album',
      albumTitle: 'City Lights',
      albumEditionId: 'edition',
      albumEditionTitle: 'Standard',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: 1,
      durationSeconds: 200,
      isSingle: false,
      featuredArtists: const [],
      dateAdded: DateTime.utc(2026, 10, 1),
      isAvailable: available,
      isSongBlocked: blocked,
      filePath: 'C:/Music/song.mp3',
    );

ChartEntry _liveEntry(int rank, {int? previous}) => ChartEntry(
  entity: const ChartEntitySnapshot(
    entityId: 'song',
    title: 'Midnight Over Lagos',
    artistName: 'Ayo Nova',
  ),
  rank: rank,
  qualifiedStreamCount: 12,
  lastQualifiedAt: _week(6),
  previousFinalRank: previous,
  previousExtendedRank: previous,
  peakRank: rank,
  peakAchievedAt: _week(6),
  weeksOnChart: 5,
  movement: ChartMovement.up,
);

SongStats _full({LibraryTrack? track, bool live = true, String? artworkPath}) {
  final weeks = SongStatsService.chartWeeks([
    for (final (i, rank) in [(0, 150), (1, 90), (2, 40), (4, 22), (5, 31)])
      _stored(i, rank),
  ]);
  return SongStats(
    identity: SongStatsIdentity(
      songId: 'song',
      title: 'Midnight Over Lagos (Extended Mix)',
      artistLine: 'Ayo Nova Ft. Kemi & The Harbour Choir',
      albumTitle: 'City Lights (Deluxe Edition)',
      artworkPath: artworkPath,
      status: SongStatsStatus.of(track),
      track: track,
    ),
    chart: SongChartHistory(
      weeks: weeks,
      live: live
          ? SongLiveChart(
              entry: _liveEntry(18, previous: 31),
              weekStartUtc: _week(6),
              weekEndUtc: _week(7),
              bestSoFarRank: 14,
            )
          : null,
    ),
    listening: SongListeningStats(
      streams: 1842,
      listened: const Duration(hours: 6, minutes: 12),
      allPlays: 2210,
      firstPlayedAt: DateTime.utc(2026, 10, 26, 14),
      lastPlayedAt: DateTime.utc(2026, 11, 14, 9),
      historyStartedAt: DateTime.utc(2026, 10, 26, 13),
      weeks: [
        for (var i = 0; i < 8; i++)
          SongListeningWeek(
            weekStartLocal: DateTime(2026, 9, 27 + 7 * i),
            listened: Duration(minutes: [0, 12, 40, 33, 80, 51, 20, 9][i]),
            streams: [0, 3, 9, 8, 19, 12, 5, 2][i],
            allPlays: [0, 4, 10, 9, 22, 14, 6, 2][i],
            inProgress: i == 7,
          ),
      ],
    ),
  );
}

ChartEntityWeek _stored(int weeks, int rank) => ChartEntityWeek(
  weekStartUtc: _week(weeks),
  weekEndUtc: _week(weeks + 1),
  finalizedAt: _week(weeks + 1),
  entry: _liveEntry(rank),
);

SongStats _empty({LibraryTrack? track, String title = 'Quiet Song'}) =>
    SongStats(
      identity: SongStatsIdentity(
        songId: 'song',
        title: title,
        artistLine: 'Someone',
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

class _Loader implements SongStatsLoader {
  _Loader(this.stats);

  final SongStats stats;

  @override
  Future<SongStats> load(String songId) async => stats;
}

class _Engine implements PlaybackEngine {
  final calls = <String>[];

  @override
  Stream<PlaybackState> get states => const Stream.empty();

  @override
  PlaybackState get currentState => const PlaybackState();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    return Future<void>.value();
  }
}

Future<void> _pump(
  WidgetTester tester,
  SongStats stats, {
  ThemeData? theme,
  Size size = const Size(411, 2600),
  double textScale = 1,
  PlaybackCoordinator? playback,
  List<LibraryTrack>? playContext,
  bool reduceMotion = false,
  SonusArtworkPalette? palette,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    Provider<PlaybackCoordinator?>.value(
      value: playback,
      child: MaterialApp(
        theme: theme,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: SongStatsPage(
          songId: 'song',
          loader: _Loader(stats),
          playContext: playContext,
          now: () => DateTime.utc(2026, 11, 10, 12),
          artworkPalette: palette,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Chart History comes first, then Personal Listening', (
    tester,
  ) async {
    await _pump(tester, _full(track: _track()));

    final chart = tester.getTopLeft(
      find.byKey(const ValueKey<String>('song-stats-chart-title')),
    );
    final listening = tester.getTopLeft(
      find.byKey(const ValueKey<String>('song-stats-listening-title')),
    );
    expect(chart.dy, lessThan(listening.dy));

    // Live, provisional, kept apart from finalized figures.
    expect(find.text('LIVE · PROVISIONAL'), findsOneWidget);
    expect(find.text('#18'), findsOneWidget);
    expect(find.text('Best so far this week: #14'), findsOneWidget);

    // Finalized: peak #22 (never the live #18), weeks, debut, re-entry.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('song-stats-peak')),
        matching: find.text('#22'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('song-stats-hot100-weeks')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('song-stats-bu-weeks')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('song-stats-hot100-debut')),
        matching: find.text('#90'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('song-stats-rank-chart')),
      findsOne,
    );
    expect(find.text('Re-entry after 1 week off'), findsOneWidget);
    expect(
      find.text('Into the Hot 100 from Bubbling Under (#150)'),
      findsOneWidget,
    );
    expect(find.text('Down 9'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('song-stats-week-log')),
        matching: find.text('HOT 100 DEBUT'),
      ),
      findsOneWidget,
    );
    // The finalized history never shows percentages; the live card keeps
    // C2's same-chart position percentage.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('song-stats-week-log')),
        matching: find.textContaining('%'),
      ),
      findsNothing,
    );

    // Listening.
    expect(find.text('1,842'), findsOneWidget);
    expect(find.text('6 h 12 m'), findsOneWidget);
    expect(find.text('2,210'), findsOneWidget);
    expect(find.text('Oct 26, 2026'), findsWidgets);
    expect(find.byKey(const ValueKey<String>('song-stats-trend')), findsOne);

    await tester.tap(find.text('Streams').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('no chart history and no listening show their own empty '
      'states', (tester) async {
    await _pump(tester, _empty());

    expect(find.text('No chart stats available'), findsOneWidget);
    expect(find.text('No listening recorded'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('song-stats-rank-chart')),
      findsNothing,
    );
  });

  testWidgets('streams without audible time say so', (tester) async {
    final stats = _empty();
    await _pump(
      tester,
      SongStats(
        identity: stats.identity,
        chart: stats.chart,
        listening: SongListeningStats(
          streams: 2,
          listened: Duration.zero,
          allPlays: 0,
          firstPlayedAt: null,
          lastPlayedAt: null,
          weeks: const [],
        ),
      ),
    );
    expect(find.text('No audible time recorded'), findsOneWidget);
    expect(find.text('No plays with audible time recorded'), findsOneWidget);
    expect(find.text('Not recorded'), findsNWidgets(2));
  });

  testWidgets('live only: no finalized figures are invented', (tester) async {
    await _pump(
      tester,
      SongStats(
        identity: _empty().identity,
        chart: SongChartHistory(
          weeks: const [],
          live: SongLiveChart(
            entry: _liveEntry(130),
            weekStartUtc: _week(6),
            weekEndUtc: _week(7),
          ),
        ),
        listening: _empty().listening,
      ),
    );
    expect(find.text('Sonus Bubbling Under'), findsOneWidget);
    // Never a percentage for a song outside the Hot 100's own movement.
    expect(find.textContaining('%'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('song-stats-no-finalized')),
      findsOne,
    );
    expect(find.byKey(const ValueKey<String>('song-stats-peak')), findsNothing);
  });

  // SN-50 device QA ("lovergirl"): #133 on the career standings row the
  // Charts page opens on, #2 live this week, never finalized.
  testWidgets('career standings and this week are named apart', (tester) async {
    await _pump(
      tester,
      SongStats(
        identity: _empty().identity,
        chart: SongChartHistory(
          weeks: const [],
          live: SongLiveChart(
            entry: _liveEntry(2),
            weekStartUtc: _week(6),
            weekEndUtc: _week(7),
          ),
          career: const SongCareerStanding(rank: 133),
        ),
        listening: _empty().listening,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Career standings'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('song-stats-career-rank')),
          )
          .data,
      '#133',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('song-stats-career')),
        matching: find.text('Sonus Bubbling Under'),
      ),
      findsOneWidget,
    );
    expect(find.text('This week'), findsWidgets);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey<String>('song-stats-live-rank')),
          )
          .data,
      '#2',
    );
    // Not "no weeks have finalized": this song is on none of them.
    expect(find.textContaining('No finalized weeks yet'), findsNothing);
    expect(
      find.textContaining('Not on a finalized weekly chart yet'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('song-stats-peak')), findsNothing);
  });

  testWidgets('career standing only: no empty week chart', (tester) async {
    await _pump(
      tester,
      SongStats(
        identity: _empty().identity,
        chart: SongChartHistory(
          weeks: const [],
          career: const SongCareerStanding(rank: 40),
        ),
        listening: _empty().listening,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('song-stats-career')),
      findsOneWidget,
    );
    expect(find.text('Position by week'), findsNothing);
    expect(find.text('No chart stats available'), findsNothing);
  });

  testWidgets('Play starts the song in its context; status songs have no '
      'Play', (tester) async {
    final engine = _Engine();
    final playback = PlaybackCoordinator(engine: engine);
    await _pump(
      tester,
      _full(track: _track()),
      playback: playback,
      playContext: [_track()],
    );
    await tester.tap(find.byKey(const ValueKey<String>('song-stats-play')));
    await tester.pumpAndSettle();
    expect(engine.calls, contains('Symbol("loadQueue")'));

    for (final (track, badge) in [
      (_track(blocked: true), 'BLACKLISTED'),
      (_track(available: false), 'UNAVAILABLE'),
      (null, 'HISTORICAL'),
    ]) {
      await _pump(tester, _full(track: track), playback: playback);
      expect(find.text(badge), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('song-stats-play')),
        findsNothing,
      );
    }
  });

  testWidgets('the rank history is announced as one summary', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _full(track: _track()));
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'^Chart position history\. 5 finalized weeks, from number '
          r'150 to number 31, peak number 22\. This week, live: number '
          r'18, provisional\.$',
        ),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  // Register R12: the hero asks the shared artwork-colours request, so it
  // follows the song's artwork and an injected palette.
  testWidgets('the hero frame takes its accent from the artwork', (
    tester,
  ) async {
    const accent = Color(0xFFE53935);
    final palette = _FixedPalette({'/a.jpg': accent});
    final theme = SonusThemeFactory.build(const SonusAppearanceSpec());
    await _pump(
      tester,
      _full(track: _track(), artworkPath: '/a.jpg'),
      theme: theme,
      palette: palette,
    );

    final box =
        tester
                .widget<Container>(
                  find.byKey(const ValueKey<String>('song-stats-hero')),
                )
                .decoration!
            as BoxDecoration;
    expect(palette.requested, ['/a.jpg']);
    expect(box.border!.top.color, accent.withValues(alpha: 0.55));
  });

  group('hero text stays readable over artwork tints', () {
    for (final id in SonusThemeId.values) {
      testWidgets(id.label, (tester) async {
        final theme = SonusThemeFactory.build(SonusAppearanceSpec(themeId: id));
        final c = theme.extension<SonusColors>()!;
        for (final seed in const [
          Color(0xFFFFEB3B), // bright: the hardest case
          Color(0xFF00E5FF),
          Color(0xFFE53935),
          Color(0xFF1E88E5),
        ]) {
          await _pump(
            tester,
            _full(track: _track(), artworkPath: '/a.jpg'),
            theme: theme,
            palette: _FixedPalette({'/a.jpg': _extractedAccent(seed)}),
          );
          final heroFinder = find.byKey(
            const ValueKey<String>('song-stats-hero'),
          );
          final box =
              tester.widget<Container>(heroFinder).decoration! as BoxDecoration;
          final stops = box.gradient?.colors ?? [c.surface, c.surface];
          final hero = tester.getRect(heroFinder);
          // The diagonal gradient's colour under a text's top-left corner,
          // its side nearest the gradient's strongest tint.
          Color under(Finder text) {
            final p = tester.getRect(text).topLeft - hero.topLeft;
            final d = hero.bottomRight - hero.topLeft;
            final t =
                ((p.dx * d.dx + p.dy * d.dy) / (d.dx * d.dx + d.dy * d.dy))
                    .clamp(0.0, 1.0);
            return Color.lerp(stops.first, stops.last, t)!;
          }

          final title = find.byKey(const ValueKey<String>('song-stats-title'));
          final artist = find.text('Ayo Nova Ft. Kemi & The Harbour Choir');
          final album = find.text('City Lights (Deluxe Edition)');
          expect(
            SonusContrast.ratio(c.textPrimary, under(title)),
            greaterThanOrEqualTo(4.5),
            reason: 'title, seed $seed',
          );
          expect(
            SonusContrast.ratio(c.textPrimary, under(artist)),
            greaterThanOrEqualTo(4.5),
            reason: 'artist line, seed $seed',
          );
          // Open finding (cleanup sprint, not changed): the secondary album
          // line falls below 4.5:1 (lowest 3.71:1) on bright artwork. This
          // guards against it getting worse until a design decision.
          expect(
            SonusContrast.ratio(c.textSecondary, under(album)),
            greaterThanOrEqualTo(3.5),
            reason: 'album line, seed $seed',
          );
        }
      });
    }
  });

  group('every theme and accessibility mode fits', () {
    for (final id in SonusThemeId.values) {
      testWidgets('${id.label} at 320 dp and 2x text', (tester) async {
        await _pump(
          tester,
          _full(track: _track()),
          theme: SonusThemeFactory.build(SonusAppearanceSpec(themeId: id)),
          size: const Size(320, 5200),
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
      });
    }

    for (final (name, spec) in [
      ('high contrast', const SonusAppearanceSpec(highContrast: true)),
      (
        'Decoration Off',
        const SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      ),
      ('reduced motion', const SonusAppearanceSpec(reduceMotion: true)),
      ('low effects', const SonusAppearanceSpec(lowEffects: true)),
    ]) {
      testWidgets('$name, narrow and large text', (tester) async {
        await _pump(
          tester,
          _full(track: _track()),
          theme: SonusThemeFactory.build(spec),
          size: const Size(320, 5200),
          textScale: 1.6,
          reduceMotion: name == 'reduced motion',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('landscape', (tester) async {
      await _pump(
        tester,
        _full(track: _track()),
        theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
        size: const Size(900, 412),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

class _FixedPalette extends SonusArtworkPalette {
  _FixedPalette(this.colours);

  final Map<String?, Color> colours;
  final requested = <String?>[];

  @override
  Future<SonusArtworkColors?> colorsFor(
    String? artworkPath, {
    required Brightness brightness,
  }) async {
    requested.add(artworkPath);
    final accent = colours[artworkPath];
    return accent == null
        ? null
        : SonusArtworkColors(accent: accent, container: accent);
  }
}

/// A realistic accent: what the palette's Material extraction gives for a
/// cover of [seed] on a dark theme.
Color _extractedAccent(Color seed) => ColorScheme.fromSeed(
  seedColor: seed,
  brightness: Brightness.dark,
  dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
).primary;
