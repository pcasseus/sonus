import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_theme.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period.dart';
import 'package:sonus_next/features/analytics/application/models/pulse/pulse_period_data.dart';
import 'package:sonus_next/features/analytics/application/services/pulse/pulse_entity_directory.dart';
import 'package:sonus_next/features/analytics/presentation/pulse/pulse_colors.dart';
import 'package:sonus_next/features/analytics/presentation/pulse/pulse_hero.dart';
import 'package:sonus_next/features/analytics/presentation/pulse/pulse_rankings.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

final period = PulsePeriod.month(2026, 10);

/// Eight tracks t1..t8: t1 has the most streams, t8 the most minutes.
/// t1, t2 by artist "a1" on release "lp"; t3 on Single "single".
PulsePeriodData data({PulsePeriod? at}) {
  final p = at ?? period;
  final tracks = <String, PulseMetrics>{};
  final last = <String, DateTime>{};
  final days = <String, Map<DateTime, PulseMetrics>>{};
  for (var i = 1; i <= 8; i++) {
    final m = PulseMetrics(
      listened: Duration(minutes: i == 8 ? 500 : 20 - i),
      streams: 10 - i,
      allPlays: 12 - i,
    );
    tracks['t$i'] = m;
    last['t$i'] = DateTime.utc(2026, 10, i);
    days['t$i'] = {DateTime(2026, 10, i): m};
  }
  PulseMetrics sum(Iterable<String> ids) => ids.fold(
    PulseMetrics.zero,
    (a, id) => PulseMetrics(
      listened: a.listened + tracks[id]!.listened,
      streams: a.streams + tracks[id]!.streams,
      allPlays: a.allPlays + tracks[id]!.allPlays,
    ),
  );
  final trackArtists = {
    for (var i = 1; i <= 8; i++) 't$i': i <= 2 ? 'a1' : 'a$i',
  };
  final trackReleases = {
    for (var i = 1; i <= 8; i++)
      't$i': i <= 2 ? 'lp' : (i == 3 ? 'single' : 'r$i'),
  };
  return PulsePeriodData(
    period: p,
    firstHistoryAt: DateTime(2026, 1, 1).toUtc(),
    totals: sum(tracks.keys),
    days: [
      for (final d in p.days)
        PulseDay(
          localDate: d,
          state: PulseDayState.recorded,
          metrics: d.day <= 8 ? tracks['t${d.day}']! : PulseMetrics.zero,
        ),
    ],
    hours: const [],
    previous: PulseComparison(
      period: p.previous,
      availability: PulseComparisonAvailability.notEnoughHistory,
      totals: null,
    ),
    samePeriodLastYear: PulseComparison(
      period: p.samePeriodLastYear,
      availability: PulseComparisonAvailability.notEnoughHistory,
      totals: null,
    ),
    behavior: null,
    entityTotals: {
      PulseEntityKind.track: tracks,
      PulseEntityKind.artist: {
        'a1': sum(['t1', 't2']),
        for (var i = 3; i <= 8; i++) 'a$i': tracks['t$i']!,
      },
      PulseEntityKind.release: {
        'lp': sum(['t1', 't2']),
        'single': tracks['t3']!,
        for (var i = 4; i <= 8; i++) 'r$i': tracks['t$i']!,
      },
    },
    entityLastActivity: {
      PulseEntityKind.track: last,
      PulseEntityKind.artist: {
        'a1': last['t2']!,
        for (var i = 3; i <= 8; i++) 'a$i': last['t$i']!,
      },
      PulseEntityKind.release: {
        'lp': last['t2']!,
        'single': last['t3']!,
        for (var i = 4; i <= 8; i++) 'r$i': last['t$i']!,
      },
    },
    entityDays: {
      PulseEntityKind.track: days,
      PulseEntityKind.artist: {
        'a1': {...days['t1']!, ...days['t2']!},
      },
      PulseEntityKind.release: {
        'lp': {...days['t1']!, ...days['t2']!},
      },
    },
    releasesOffRankings: const {'single'},
    trackArtists: trackArtists,
    trackReleases: trackReleases,
  );
}

LibraryTrack libraryTrack(String id) => LibraryTrack(
  songId: id,
  title: 'Song $id',
  artistId: 'a1',
  artistName: 'Artist One',
  albumId: 'lp',
  albumTitle: 'The LP',
  albumEditionId: 'standard',
  albumEditionTitle: 'Standard',
  albumEditionType: AlbumEditionType.standard,
  trackNumber: 1,
  durationSeconds: 180,
  isSingle: false,
  featuredArtists: const [],
  dateAdded: DateTime(2026),
  isAvailable: true,
  filePath: '/music/$id.mp3',
);

PulseEntityDirectory directory() => PulseEntityDirectory({
  for (var i = 1; i <= 8; i++)
    (PulseEntityKind.track, 't$i'): PulseEntityInfo(
      kind: PulseEntityKind.track,
      id: 't$i',
      title: 'Song t$i',
      subtitle: i <= 2 ? 'Artist One' : 'Artist $i',
      artworkPath: null,
      status: i == 2
          ? PulseEntityStatus.blocked
          : i == 5
          ? PulseEntityStatus.historical
          : PulseEntityStatus.current,
      track: i == 5 ? null : libraryTrack('t$i'),
      artistId: i <= 2 ? 'a1' : 'a$i',
      albumId: i <= 2 ? 'lp' : 'r$i',
    ),
  (PulseEntityKind.artist, 'a1'): const PulseEntityInfo(
    kind: PulseEntityKind.artist,
    id: 'a1',
    title: 'Artist One',
    subtitle: '2 songs · 1 release',
    artworkPath: null,
    status: PulseEntityStatus.current,
    artistId: 'a1',
  ),
  (PulseEntityKind.release, 'lp'): const PulseEntityInfo(
    kind: PulseEntityKind.release,
    id: 'lp',
    title: 'The LP',
    subtitle: 'Artist One',
    artworkPath: null,
    status: PulseEntityStatus.current,
    artistId: 'a1',
    albumId: 'lp',
  ),
});

class _Host extends StatefulWidget {
  const _Host({
    required this.kind,
    required this.accent,
    this.comparisonData,
    this.actions = const PulseRankingActions(),
    this.lifetime,
    this.focusLog,
  });

  final PulseEntityKind kind;
  final PulseAccentController accent;
  final PulsePeriodData? comparisonData;
  final PulseRankingActions actions;
  final Future<int?> Function(PulseEntityKind, String)? lifetime;
  final List<PulseItemFocus?>? focusLog;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  PulseItemFocus? focus;

  @override
  Widget build(BuildContext context) {
    final theme = SonusTheme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: PulseRankingCard(
        kind: widget.kind,
        data: data(),
        directory: directory(),
        palette: PulsePalette.resolve(
          colors: theme.colors,
          decoration: theme.decoration,
        ),
        accent: widget.accent,
        comparisonData: widget.comparisonData,
        comparisonTitle: 'September 2026',
        focus: focus,
        onFocusChanged: (f) {
          widget.focusLog?.add(f);
          setState(() => focus = f);
        },
        lifetimeStreams: widget.lifetime,
        actions: widget.actions,
        artworkPalette: SonusArtworkPalette(),
      ),
    );
  }
}

Widget app(
  Widget child, {
  SonusAppearanceSpec spec = const SonusAppearanceSpec(
    themeId: SonusThemeId.neonMixtape,
  ),
  double width = 400,
  double textScale = 1,
}) => MediaQuery(
  data: MediaQueryData(
    size: Size(width, 1600),
    textScaler: TextScaler.linear(textScale),
  ),
  child: MaterialApp(
    theme: SonusThemeFactory.build(spec),
    home: Scaffold(body: child),
  ),
);

void main() {
  late PulseAccentController accent;
  setUp(() => accent = PulseAccentController());

  testWidgets('Top 5 by default, Top 10 expands; ranks by Streams first', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(_Host(kind: PulseEntityKind.track, accent: accent)),
    );
    expect(find.text('Top tracks'), findsOneWidget);
    expect(find.textContaining('Song t'), findsNWidgets(5));
    expect(find.text('Song t1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pulse-top-track-10')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Song t'), findsNWidgets(8));
  });

  testWidgets('the metric menu re-ranks by Minutes or All plays', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(_Host(kind: PulseEntityKind.track, accent: accent)),
    );
    await tester.tap(find.byKey(const ValueKey('pulse-metric-track')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minutes').last);
    await tester.pumpAndSettle();
    final first = tester.getTopLeft(find.text('Song t8')).dy;
    final second = tester.getTopLeft(find.text('Song t1')).dy;
    expect(first, lessThan(second), reason: 't8 has the most minutes');
    expect(find.text('500 min'), findsOneWidget);
  });

  testWidgets('releases leave out Singles; artists credit the lead artist', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(_Host(kind: PulseEntityKind.release, accent: accent)),
    );
    expect(find.text('Top albums & EPs'), findsOneWidget);
    expect(find.text('The LP'), findsOneWidget);
    expect(find.textContaining('single'), findsNothing);
  });

  testWidgets('labels blacklisted and historical songs', (tester) async {
    await tester.pumpWidget(
      app(_Host(kind: PulseEntityKind.track, accent: accent)),
    );
    expect(find.text('BLACKLISTED'), findsOneWidget);
    expect(find.text('HISTORICAL'), findsOneWidget);
  });

  testWidgets('rank movement against an eligible comparison', (tester) async {
    // September: t2 was #1, t1 #2, t4 #4; t3 absent; others below.
    final before = data(at: period.previous);
    final shuffled = PulsePeriodData(
      period: before.period,
      firstHistoryAt: before.firstHistoryAt,
      totals: before.totals,
      days: before.days,
      hours: const [],
      previous: before.previous,
      samePeriodLastYear: before.samePeriodLastYear,
      behavior: null,
      entityTotals: {
        PulseEntityKind.track: {
          't2': const PulseMetrics(
            listened: Duration.zero,
            streams: 20,
            allPlays: 20,
          ),
          't1': const PulseMetrics(
            listened: Duration.zero,
            streams: 10,
            allPlays: 10,
          ),
          't9': const PulseMetrics(
            listened: Duration.zero,
            streams: 9,
            allPlays: 9,
          ),
          't4': const PulseMetrics(
            listened: Duration.zero,
            streams: 5,
            allPlays: 5,
          ),
        },
      },
      entityLastActivity: const {},
      entityDays: const {},
      releasesOffRankings: const {},
    );
    await tester.pumpWidget(
      app(
        _Host(
          kind: PulseEntityKind.track,
          accent: accent,
          comparisonData: shuffled,
        ),
      ),
    );
    expect(find.text('▲ 1'), findsOneWidget, reason: 't1: 2 → 1');
    expect(find.text('▼ 1'), findsOneWidget, reason: 't2: 1 → 2');
    expect(find.text('NEW'), findsNWidgets(2), reason: 't3 and t5');
    expect(find.text('='), findsOneWidget, reason: 't4 stays 4th');
  });

  testWidgets('opening a row shows its detail; actions use real services', (
    tester,
  ) async {
    final played = <List<String>>[];
    final openedArtists = <String>[];
    final openedReleases = <String>[];
    final focusLog = <PulseItemFocus?>[];
    await tester.pumpWidget(
      app(
        _Host(
          kind: PulseEntityKind.artist,
          accent: accent,
          focusLog: focusLog,
          lifetime: (kind, id) async => 1234,
          actions: PulseRankingActions(
            playTracks: (start, tracks) =>
                played.add([for (final t in tracks) t.songId]),
            openArtist: (id, name) => openedArtists.add('$id $name'),
            openRelease: (id, title) => openedReleases.add('$id $title'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pulse-row-artist-a1')));
    await tester.pumpAndSettle();

    expect(focusLog.single, isA<PulseItemFocus>());
    expect(find.text('In October 2026'), findsOneWidget);
    expect(find.text('1,234 lifetime streams'), findsOneWidget);
    expect(find.text('Top tracks'), findsOneWidget);
    expect(find.text('Releases'), findsOneWidget);
    expect(find.text('The LP'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pulse-detail-play')));
    expect(played, [
      ['t1'],
    ], reason: 't2 is blacklisted, so only t1 plays');
    await tester.tap(find.byKey(const ValueKey('pulse-detail-open-artist')));
    expect(openedArtists, ['a1 Artist One']);

    await tester.tap(find.byKey(const ValueKey('pulse-detail-close')));
    await tester.pumpAndSettle();
    expect(focusLog.last, isNull);
    expect(find.text('In October 2026'), findsNothing);
  });

  testWidgets('the trend is per day and adds up to the item\'s total', (
    tester,
  ) async {
    final trend = PulseItemDetail.trend(
      data(),
      PulseEntityKind.artist,
      'a1',
      PulseMeasure.streams,
    );
    expect(trend, hasLength(31));
    expect(trend.fold<num>(0, (a, t) => a + t.$2), 9 + 8);
    expect(trend[0], ('1', 9));
    expect(trend[1], ('2', 8));
  });

  testWidgets('a temporary accent: Reset colours returns the theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(_Host(kind: PulseEntityKind.track, accent: accent)),
    );
    await tester.tap(find.byKey(const ValueKey('pulse-row-track-t1')));
    await tester.pumpAndSettle();
    expect(find.text('Reset colours'), findsNothing);

    accent.apply(
      const SonusArtworkColors(
        accent: Color(0xFFFF7043),
        container: Color(0xFF3E1A10),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reset colours'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pulse-detail-reset-colours')));
    await tester.pumpAndSettle();
    expect(accent.isApplied, isFalse);
    expect(find.text('In October 2026'), findsOneWidget, reason: 'still open');

    await tester.tap(find.byKey(const ValueKey('pulse-detail-close')));
    await tester.pumpAndSettle();
    expect(accent.isApplied, isFalse);
  });

  testWidgets('screen readers hear rank, name, value and status', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      app(_Host(kind: PulseEntityKind.track, accent: accent)),
    );
    expect(
      find.bySemanticsLabel(
        'Rank 2, Song t2, Artist One, 8 streams, blacklisted',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  for (final id in SonusThemeId.values) {
    testWidgets('${id.label}: cards and an open detail render in every mode', (
      tester,
    ) async {
      var i = 0;
      for (final spec in [
        SonusAppearanceSpec(themeId: id),
        SonusAppearanceSpec(themeId: id, highContrast: true),
        SonusAppearanceSpec(
          themeId: id,
          decoration: SonusDecorationIntensity.off,
        ),
        SonusAppearanceSpec(themeId: id, lowEffects: true, reduceMotion: true),
      ]) {
        await tester.pumpWidget(
          KeyedSubtree(
            key: ValueKey(i++),
            child: app(
              _Host(kind: PulseEntityKind.artist, accent: accent),
              spec: spec,
              width: 320,
              textScale: i.isEven ? 2 : 1,
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('pulse-row-artist-a1')));
        await tester.pumpAndSettle();
        final top10 = find.byKey(const ValueKey('pulse-top-artist-10'));
        await tester.ensureVisible(top10);
        await tester.tap(top10);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
}
