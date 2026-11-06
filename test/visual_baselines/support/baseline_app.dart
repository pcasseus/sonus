// The app as the protected baselines render it: the real shell (Sonus bar
// and tabs), the real playback host and mini-player, the real Home and
// Library pages, real Roboto and Material Icons, generated artwork, and the
// Galaxy S26 Ultra's measured size and insets. Only the data sources are
// fixtures; no production code is replaced.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_artwork_palette.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/home/application/models/home_popular_track.dart';
import 'package:sonus_next/features/home/application/models/home_snapshot.dart';
import 'package:sonus_next/features/home/application/models/home_top_artist.dart';
import 'package:sonus_next/features/home/application/services/home_data_service.dart';
import 'package:sonus_next/features/home/presentation/controllers/home_controller.dart';
import 'package:sonus_next/features/home/presentation/pages/home_page.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/models/artist_library_statistics.dart';
import 'package:sonus_next/features/library/presentation/models/artist_profile_sections.dart';
import 'package:sonus_next/features/library/presentation/pages/library_page.dart';
import 'package:sonus_next/features/library/presentation/services/artist_library_statistics_service.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/player/presentation/controllers/lyrics_controller.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';
import 'package:sonus_next/features/shell/domain/models/app_destination.dart';
import 'package:sonus_next/features/shell/presentation/pages/app_shell_page.dart';
import 'package:sonus_next/features/shell/presentation/widgets/playback_host.dart';

import '../../features/library/presentation/pages/library_page_test.dart'
    as library_fixtures;
import '../../support/device_layout.dart';
import 'generated_artwork.dart';

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

/// One combination of device, appearance and playback a baseline is
/// recorded in.
@immutable
class BaselineScenario {
  const BaselineScenario(
    this.name, {
    this.size = s26UltraSize,
    this.ratio = goldenRatio,
    this.spec = const SonusAppearanceSpec(),
    this.textScale = 1,
    this.withTrack = true,
  });

  /// File-name part of the golden, e.g. `s26_track`.
  final String name;
  final Size size;
  final double ratio;
  final SonusAppearanceSpec spec;
  final double textScale;

  /// Whether a song is queued, so the mini-player shows.
  final bool withTrack;
}

/// Golden images are rendered at this density rather than the phone's
/// 2.8125: layout is in logical pixels, so the geometry is identical, and
/// each image is about a quarter of the size (the repository is public and
/// keeps every approved image in its history). Geometry assertions use the
/// real density.
const double goldenRatio = 1.5;

/// The standard matrix: the S26 Ultra with and without the mini-player,
/// the second theme (Monochrome), High contrast, enlarged text, and the
/// two other representative phone sizes.
const List<BaselineScenario> standardScenarios = [
  BaselineScenario('s26_track'),
  BaselineScenario('s26_no_track', withTrack: false),
  BaselineScenario(
    's26_monochrome',
    spec: SonusAppearanceSpec(themeId: SonusThemeId.monochrome),
  ),
  BaselineScenario(
    's26_high_contrast',
    spec: SonusAppearanceSpec(highContrast: true),
  ),
  BaselineScenario('s26_text_1_3', textScale: 1.3),
  BaselineScenario('360x780_track', size: Size(360, 780)),
  BaselineScenario('412x915_track', size: Size(412, 915)),
];

/// The theme the app builds for [spec], drawing its text in the real
/// Roboto, including the Sonus text-style extension.
ThemeData baselineTheme(SonusAppearanceSpec spec) {
  final base = SonusThemeFactory.build(spec);
  final text = base.textTheme.apply(fontFamily: realRobotoFamily);
  TextStyle? roboto(TextStyle? style) =>
      style?.copyWith(fontFamily: realRobotoFamily);
  return base.copyWith(
    textTheme: text,
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: roboto(base.appBarTheme.titleTextStyle),
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelStyle: roboto(base.tabBarTheme.labelStyle),
      unselectedLabelStyle: roboto(base.tabBarTheme.unselectedLabelStyle),
    ),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: realRobotoFamily),
    extensions: [
      for (final extension in base.extensions.values)
        extension is SonusTextStyles
            ? SonusTextStyles.fromTextTheme(text)
            : extension,
    ],
  );
}

/// The fixture library: 60 artists (enough for several Roster pages),
/// three in four with generated portraits, ranked in order.
class BaselineLibrary {
  BaselineLibrary(this.art)
    : artists = [
        for (var i = 0; i < 60; i++)
          LibraryArtist(
            artistId: 'artist-$i',
            name:
                _artistNames[i % _artistNames.length] +
                (i < _artistNames.length
                    ? ''
                    : ' ${i ~/ _artistNames.length + 1}'),
            albumCount: 1 + i % 4,
            songCount: 6 + (i * 7) % 40,
            dateAdded: DateTime.utc(2026, 9, 1 + i % 28),
            topArtistsArtworkPath: art.portraitFor(i),
            headerArtworkPath: art.portraitFor(i),
          ),
      ];

  final BaselineArtworkFiles art;
  final List<LibraryArtist> artists;

  late final List<LibraryAlbum> albums = [
    for (var i = 0; i < 8; i++)
      LibraryAlbum(
        albumId: 'album-$i',
        title: _albumTitles[i],
        artistId: artists[i].artistId,
        artistName: artists[i].name,
        trackCount: 8 + i,
        dateAdded: DateTime.utc(2026, 10, 20 - i),
        artworkPath: art.coverFor(i),
      ),
  ];

  LibraryTrack track(int i) => LibraryTrack(
    songId: 'song-$i',
    title: _songTitles[i % _songTitles.length],
    artistId: artists[i].artistId,
    artistName: artists[i].name,
    albumId: albums[i % albums.length].albumId,
    albumTitle: albums[i % albums.length].title,
    albumEditionId: 'edition-$i',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1 + i,
    durationSeconds: 150 + i * 13,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 10, 1),
    isAvailable: true,
    filePath: 'C:/Music/song-$i.mp3',
    artworkPath: albums[i % albums.length].artworkPath,
  );

  late final ArtistLibraryStatisticsSnapshot statistics =
      ArtistLibraryStatisticsSnapshot([
        for (final (i, artist) in artists.indexed)
          ArtistLibraryStatistics(
            artist: artist,
            rank: i < 50 ? i + 1 : null,
            qualifiedStreams: i < 50 ? 900 - i * 17 : 0,
            listened: Duration(minutes: i < 50 ? 1200 - i * 23 : 0),
            topTrack: i < 50
                ? ArtistTopTrack(track: track(i % 8), streamCount: 120 - i)
                : null,
          ),
      ]);

  late final HomeSnapshot home = HomeSnapshot(
    recentlyAddedAlbums: albums,
    weeklyPopularTracks: [
      for (var i = 0; i < 6; i++)
        HomePopularTrack(
          track: track(i),
          rank: i + 1,
          qualifiedStreamCount: 40 - i * 5,
        ),
    ],
    weeklyTopArtists: [
      for (var i = 0; i < 6; i++)
        HomeTopArtist(
          artist: artists[i],
          rank: i + 1,
          qualifiedStreamCount: 60 - i * 7,
          weeklyListeningDuration: Duration(minutes: 200 - i * 25),
        ),
    ],
  );

  /// The queued song: cool cover, paused at 1:12 of 3:30.
  PlaybackTrack get playingTrack => PlaybackTrack(
    songId: 'song-0',
    title: 'Glass Horizon',
    artistId: artists[0].artistId,
    artistName: artists[0].name,
    albumId: albums[0].albumId,
    albumTitle: albums[0].title,
    filePath: 'C:/Music/song-0.mp3',
    duration: const Duration(minutes: 3, seconds: 30),
    artworkPath: art.path(BaselineArtwork.coolCover),
  );
}

const _artistNames = [
  'Ada Lune',
  'Ben Vale',
  'Cora Bright',
  'Dax Rivers',
  'Echo Park',
  'Fern Ito',
  'Gale Monroe',
  'Halo North',
  'Iris Kane',
  'Jett Sol',
  'Kira Moss',
  'Leon Ardent',
];

const _albumTitles = [
  'Glass Horizon',
  'Ember Season',
  'Quiet Machines',
  'Low Tide',
  'Northern Lights',
  'Paper Suns',
  'Velvet Hours',
  'Static Bloom',
];

const _songTitles = [
  'Glass Horizon',
  'Afterglow',
  'Slow Motion',
  'City Rain',
  'Gold Line',
  'Outrun',
  'Satellite',
  'Midnight Drive',
];

/// A playback engine that reports one fixed state and does nothing else.
class FixtureEngine implements PlaybackEngine {
  FixtureEngine(PlaybackTrack? track)
    : currentState = track == null
          ? const PlaybackState()
          : PlaybackState(
              queue: PlaybackQueue(tracks: [track], currentIndex: 0),
              status: PlaybackStatus.paused,
              position: const Duration(minutes: 1, seconds: 12),
              duration: track.duration,
            );

  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  final PlaybackState currentState;

  @override
  Future<void> dispose() async {
    if (!_states.isClosed) await _states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixtureHomeData implements HomeDataService {
  _FixtureHomeData(this.snapshot);

  final HomeSnapshot snapshot;

  @override
  int get sectionLimit => 6;

  @override
  Future<HomeSnapshot> load({required DateTime referenceLocal}) async =>
      snapshot;
}

class _FixtureStatistics implements ArtistLibraryStatisticsService {
  _FixtureStatistics(this.snapshot);

  final ArtistLibraryStatisticsSnapshot snapshot;

  @override
  Future<ArtistLibraryStatisticsSnapshot> load() async => snapshot;
}

/// Pumps the shell for [scenario] and opens [destination] (Home or
/// Library), with artwork decoded and colours extracted.
Future<BaselineLibrary> pumpBaselineApp(
  WidgetTester tester,
  BaselineScenario scenario, {
  AppDestination destination = AppDestination.home,
}) async {
  final art = BaselineArtworkFiles.ensure();
  final library = BaselineLibrary(art);
  setDevice(tester, size: scenario.size, ratio: scenario.ratio);

  // Artwork colours cannot be extracted inside the fake async zone: warm
  // the shared palette (which every protected screen reads) for real first.
  await tester.runAsync(() async {
    for (final path in art.allPaths) {
      await SonusArtworkPalette.shared.colorsFor(
        path,
        brightness: Brightness.dark,
      );
    }
  });

  final engine = FixtureEngine(
    scenario.withTrack ? library.playingTrack : null,
  );
  final coordinator = PlaybackCoordinator(engine: engine);
  final playback = PlaybackStateController(coordinator: coordinator);
  addTearDown(engine.dispose);
  final home = HomeController(
    service: _FixtureHomeData(library.home),
    now: () => DateTime(2026, 10, 28, 12),
  );
  await tester.runAsync(home.load);
  final navigatorKey = GlobalKey<NavigatorState>();
  final routes = PlaybackHostRouteObserver();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<PlaybackCoordinator>.value(value: coordinator),
        ChangeNotifierProvider<PlaybackStateController>.value(value: playback),
        ChangeNotifierProvider<LyricsController?>.value(value: null),
        ChangeNotifierProvider<HomeController?>.value(value: home),
        Provider<LibraryQueryRepository?>.value(
          value: library_fixtures.FakeLibraryQueryRepository(
            artists: library.artists,
            albums: library.albums,
          ),
        ),
        Provider<ArtistLibraryStatisticsService?>.value(
          value: _FixtureStatistics(library.statistics),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: baselineTheme(scenario.spec),
        themeAnimationDuration: Duration.zero,
        navigatorKey: navigatorKey,
        navigatorObservers: [routes],
        builder: (context, navigator) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scenario.textScale)),
          child: PlaybackHost(
            navigatorKey: navigatorKey,
            routes: routes,
            child: navigator!,
          ),
        ),
        home: AppShellPage(
          pageBuilder: (destination) => switch (destination) {
            AppDestination.home => const HomePage(),
            AppDestination.library => const LibraryPage(),
            _ => Center(child: Text('${destination.label} page')),
          },
        ),
      ),
    ),
  );
  await settleArtwork(tester);
  if (destination != AppDestination.home) {
    await openTab(tester, destination);
  }
  return library;
}

/// Brings the tab for [destination] into view and opens it.
Future<void> openTab(WidgetTester tester, AppDestination destination) async {
  final tab = byKey('app-tab-${destination.name}');
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await settleArtwork(tester);
}

/// Lets real file reads and image decoding finish, then settles the frame.
///
/// Image loads started while pumping belong to the fake async zone: their
/// results are delivered as microtasks there, so awaiting them inside
/// `runAsync` would deadlock. Instead real time is allowed to pass (the
/// engine reads and decodes meanwhile) and a pump then delivers the results.
/// Repeated, because a decoded picture can bring further pictures into view.
Future<void> settleArtwork(WidgetTester tester) async {
  await tester.pumpAndSettle();
  for (var round = 0; round < 8; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// The geometry matrix, at each phone's real density: the S26 Ultra and
/// two other representative sizes, with and without the mini-player, at
/// normal and enlarged (1.3x) text.
List<BaselineScenario> geometryScenarios({bool withoutTrack = true}) => [
  for (final (size, ratio) in const [
    (s26UltraSize, s26UltraRatio),
    (Size(412, 915), 2.625),
    (Size(360, 780), 3.0),
  ])
    for (final track in [true, if (withoutTrack) false])
      for (final text in const [1.0, 1.3])
        BaselineScenario(
          '${size.width.toInt()}x${size.height.toInt()}'
          '_${track ? 'track' : 'no_track'}_text_$text',
          size: size,
          ratio: ratio,
          withTrack: track,
          textScale: text,
        ),
];
