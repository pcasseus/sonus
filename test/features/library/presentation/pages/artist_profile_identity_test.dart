// SN-45 Artist Profile: identity, release sections and the compact toolbar
// title. Uses the profile page's own fakes plus a real
// LibraryOrganizationService over in-memory organization data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/library/domain/repositories/song_single_presentation_repository.dart';
import 'package:sonus_next/features/library/domain/repositories/song_repository.dart';
import 'package:sonus_next/features/library/domain/entities/song_single_presentation.dart';
import 'package:sonus_next/features/library/domain/entities/release_date.dart';
import 'package:sonus_next/features/library/application/services/song_single_presentation_service.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/project_collaborator.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/domain/repositories/library_organization_repository.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_profile_page.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/song_stats/presentation/song_stats_page.dart';

import 'artist_profile_page_test.dart' as base;

class _Credits implements ProjectCollaboratorQueryRepository {
  _Credits(this.albums, this.credits);

  final List<LibraryAlbum> albums;
  final List<ProjectCollaborator> credits;

  Future<List<LibraryAlbum>> getAlbums() async => albums;

  @override
  Future<List<ProjectCollaborator>> getProjectCollaborators({
    String? albumId,
  }) async => [
    for (final credit in credits)
      if (albumId == null || credit.albumId == albumId) credit,
  ];
}

class _AlbumsOnly implements LibraryQueryRepository {
  _AlbumsOnly(this.albums);

  final List<LibraryAlbum> albums;

  @override
  Future<List<LibraryAlbum>> getAlbums() async => albums;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Organization implements LibraryOrganizationRepository {
  _Organization(this.formats);

  final Map<String, ReleaseFormat> formats;

  @override
  Future<List<AlbumReleaseFormat>> getFormats() async => [
    for (final MapEntry(key: albumId, value: format) in formats.entries)
      AlbumReleaseFormat(
        albumId: albumId,
        format: format,
        authority: ReleaseClassificationAuthority.manual,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
  ];

  @override
  Future<List<AlbumReleaseClassification>> getClassifications() async =>
      const [];

  @override
  Future<List<ArtistProjectAssignment>> getAssignments() async => const [];

  final Map<String, AlbumLiveClassification> lives = {};

  @override
  Future<List<AlbumLiveClassification>> getLiveClassifications() async =>
      lives.values.toList();

  @override
  Future<List<AlbumLeakedClassification>> getLeakedClassifications() async =>
      const [];

  @override
  Future<void> saveLiveClassification(AlbumLiveClassification live) async =>
      lives[live.albumId] = live;

  @override
  Future<void> deleteLiveClassification(String albumId) async =>
      lives.remove(albumId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The profile page's fake, also listing every release in the library.
class _Repo extends base.FakeLibraryQueryRepository {
  _Repo({
    required this.library,
    super.artist,
    super.albums,
    super.tracks,
    super.allTracks,
  });

  final List<LibraryAlbum> library;

  @override
  Future<List<LibraryAlbum>> getAlbums() async => library;
}

LibraryAlbum _release(
  String id,
  String title, {
  String artistId = 'artist-1',
  String artistName = 'Test Artist',
  DateTime? released,
  int trackCount = 10,
}) => LibraryAlbum(
  albumId: id,
  title: title,
  artistId: artistId,
  artistName: artistName,
  trackCount: trackCount,
  releaseDate: released,
  dateAdded: DateTime(2026, 1, 1),
);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required _Repo repository,
    required List<LibraryAlbum> libraryAlbums,
    List<ProjectCollaborator> credits = const [],
    Map<String, ReleaseFormat> formats = const {},
    Set<String> live = const {},
    String artistId = 'artist-1',
    String? projectArtistId,
    Size size = const Size(411, 2400),
    QualifiedPlayRepository? qualifiedPlays,
    PlaybackCoordinator? playbackCoordinator,
    Map<String, SongSinglePresentation> singles = const {},
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final organization = LibraryOrganizationService(
      library: _AlbumsOnly(libraryAlbums),
      collaborators: _Credits(libraryAlbums, credits),
      organization: _Organization(formats)
        ..lives.addAll({
          for (final albumId in live)
            albumId: AlbumLiveClassification(
              albumId: albumId,
              isLive: true,
              authority: ReleaseClassificationAuthority.manual,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
        }),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<LibraryOrganizationService?>.value(value: organization),
          Provider<SongSinglePresentationService?>.value(
            value: SongSinglePresentationService(
              presentations: _Singles(singles),
              songs: _NoSongs(),
            ),
          ),
        ],
        child: base.buildSubject(
          repository: repository,
          qualifiedPlays: qualifiedPlays,
          playbackCoordinator: playbackCoordinator,
          home: ArtistProfilePage(
            artistId: artistId,
            projectArtistId: projectArtistId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey<String>(value));

  testWidgets('REF-16: a song marked as a single on an album joins the '
      'Singles section once, as itself; a Single release is not repeated', (
    tester,
  ) async {
    final releases = [
      _release('album', 'Long Player', released: DateTime(2024, 6, 21)),
      _release(
        'single',
        'Lead Single',
        released: DateTime(2024, 5, 1),
        trackCount: 1,
      ),
    ];
    await pump(
      tester,
      repository: _Repo(
        library: releases,
        artist: base.createArtist(albumCount: 2, songCount: 3),
        albums: releases,
        tracks: [
          base.createTrack(
            songId: 'hit',
            title: 'Album Hit',
            albumId: 'album',
            isSingle: true,
          ),
          base.createTrack(songId: 'deep', title: 'Deep Cut', albumId: 'album'),
          base.createTrack(
            songId: 'lead',
            title: 'Lead Single',
            albumId: 'single',
            isSingle: true,
          ),
        ],
      ),
      libraryAlbums: releases,
      formats: {'single': ReleaseFormat.single, 'album': ReleaseFormat.album},
    );

    final singles = key('artist-profile-singles');
    expect(singles, findsOneWidget);
    expect(
      find.descendant(of: singles, matching: find.text('Album Hit')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: singles, matching: find.text('Deep Cut')),
      findsNothing,
    );
    // The Single release shows as its card only; its song is not listed
    // again.
    expect(
      find.descendant(of: singles, matching: find.text('Lead Single')),
      findsOneWidget,
    );
  });

  // App Update 1.3 (REF-1.3-04): a Single's own cover and date, and only
  // in the Singles section.
  testWidgets('a Single card shows its own cover', (tester) async {
    final releases = [
      _release('album', 'Long Player', released: DateTime(2024, 6, 21)),
    ];
    await pump(
      tester,
      repository: _Repo(
        library: releases,
        artist: base.createArtist(albumCount: 1, songCount: 2),
        albums: releases,
        tracks: [
          base.createTrack(
            songId: 'hit',
            title: 'Album Hit',
            albumId: 'album',
            isSingle: true,
          ),
          base.createTrack(songId: 'deep', title: 'Deep Cut', albumId: 'album'),
        ],
      ),
      libraryAlbums: releases,
      formats: {'album': ReleaseFormat.album},
      singles: {
        'hit': SongSinglePresentation(
          songId: 'hit',
          releaseDate: ReleaseDate.of(2024, 4),
          artworkId: 'art-hit',
          artworkPath: '/art/hit-single.png',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      },
    );

    final artwork = find.descendant(
      of: key('artist-single-song-artwork-hit'),
      matching: find.byType(Image),
    );
    expect(
      ((tester.widget<Image>(artwork).image as ResizeImage).imageProvider
              as FileImage)
          .file
          .path,
      '/art/hit-single.png',
    );
  });

  // App Update 1.3 (post-preview correction): a song marked as a Single
  // is a release-style card in the Singles rail, ordered by its own date.
  group('Singles rail', () {
    final releases = [
      _release('album', 'Long Player', released: DateTime(2024, 6, 21)),
      _release(
        'r-2025',
        '15 Minutes',
        released: DateTime(2025, 1, 10),
        trackCount: 1,
      ),
      _release(
        'r-2023',
        'I Have Never Felt More Alive',
        released: DateTime(2023, 2, 1),
        trackCount: 1,
      ),
    ];
    final formats = {
      'album': ReleaseFormat.album,
      'r-2025': ReleaseFormat.single,
      'r-2023': ReleaseFormat.single,
    };

    SongSinglePresentation single(
      String songId, {
      ReleaseDate? date,
      String? cover,
    }) => SongSinglePresentation(
      songId: songId,
      releaseDate: date,
      artworkId: cover == null ? null : 'art-$songId',
      artworkPath: cover,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    Future<void> pumpRail(
      WidgetTester tester, {
      bool isSingle = true,
      String title = 'bittersweet',
      Map<String, SongSinglePresentation>? singles,
      Size size = const Size(411, 2400),
    }) => pump(
      tester,
      size: size,
      repository: _Repo(
        library: releases,
        artist: base.createArtist(albumCount: 3, songCount: 4),
        albums: releases,
        tracks: [
          base.createTrack(
            songId: 'hit',
            title: title,
            albumId: 'album',
            isSingle: isSingle,
          ),
          base.createTrack(songId: 'deep', title: 'Deep Cut', albumId: 'album'),
          base.createTrack(
            songId: 'min',
            title: '15 Minutes',
            albumId: 'r-2025',
          ),
          base.createTrack(
            songId: 'alive',
            title: 'I Have Never Felt More Alive',
            albumId: 'r-2023',
          ),
        ],
      ),
      libraryAlbums: releases,
      formats: formats,
      singles:
          singles ??
          {
            'hit': single(
              'hit',
              date: ReleaseDate.of(2024, 4),
              cover: '/art/hit-single.png',
            ),
          },
    );

    final cardKey = RegExp(r'^artist-(album|single-song)-(?!artwork-)');

    // The rail's cards, left to right.
    List<String> railOrder(WidgetTester tester) {
      final rail = find.descendant(
        of: key('artist-profile-singles'),
        matching: key('artist-profile-albums-grid'),
      );
      final keys = [
        for (final element
            in find
                .descendant(
                  of: rail,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget.key is ValueKey<String> &&
                        cardKey.hasMatch(
                          (widget.key! as ValueKey<String>).value,
                        ),
                  ),
                )
                .evaluate())
          (element.widget.key! as ValueKey<String>).value,
      ];
      keys.sort(
        (a, b) => tester
            .getTopLeft(key(a))
            .dx
            .compareTo(tester.getTopLeft(key(b)).dx),
      );
      return keys;
    }

    testWidgets('the Single is a card in the rail, placed by its own date, '
        'with "Single · 1 track"; no song row', (tester) async {
      await pumpRail(tester);

      expect(railOrder(tester), [
        'artist-album-r-2025',
        'artist-single-song-hit',
        'artist-album-r-2023',
      ]);
      final card = key('artist-single-song-hit');
      expect(
        find.descendant(of: card, matching: find.text('bittersweet')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Single · 1 track')),
        findsOneWidget,
      );
      // The same card size as the releases beside it.
      expect(tester.getSize(card), tester.getSize(key('artist-album-r-2025')));
      // No song rows in Singles; the album keeps its other songs.
      expect(
        find.descendant(
          of: key('artist-profile-singles'),
          matching: find.byType(ListTile),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: key('artist-profile-singles'),
          matching: find.text('Deep Cut'),
        ),
        findsNothing,
      );
    });

    testWidgets('no cover and no date: the usual artwork, after the dated '
        'releases', (tester) async {
      await pumpRail(tester, singles: const {});
      expect(
        find.descendant(
          of: key('artist-single-song-artwork-hit'),
          matching: find.byIcon(Icons.album_rounded),
        ),
        findsOneWidget,
      );
      expect(railOrder(tester), [
        'artist-album-r-2025',
        'artist-album-r-2023',
        'artist-single-song-hit',
      ]);
    });

    testWidgets("tapping the card opens the song's Song Stats", (tester) async {
      await pumpRail(tester);
      await tester.ensureVisible(key('artist-single-song-hit'));
      await tester.tap(key('artist-single-song-hit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SongStatsPage), findsOneWidget);
      expect(
        tester.widget<SongStatsPage>(find.byType(SongStatsPage)).songId,
        'hit',
      );
    });

    testWidgets('Single switched off: the card leaves the rail; switched '
        'back on, it returns with its kept presentation', (tester) async {
      final kept = {
        'hit': single('hit', date: ReleaseDate.of(2024, 4), cover: '/a.png'),
      };
      await pumpRail(tester, isSingle: false, singles: kept);
      expect(key('artist-single-song-hit'), findsNothing);
      expect(railOrder(tester), ['artist-album-r-2025', 'artist-album-r-2023']);

      await pumpRail(tester, singles: kept);
      expect(railOrder(tester), [
        'artist-album-r-2025',
        'artist-single-song-hit',
        'artist-album-r-2023',
      ]);
    });

    testWidgets('a long title at 320 px and 2x text fits and is read as '
        'one card', (tester) async {
      final handle = tester.ensureSemantics();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpRail(
        tester,
        size: const Size(320, 2400),
        title: 'A very long single title that will never fit on one card',
      );

      expect(tester.takeException(), isNull);
      expect(
        find.bySemanticsLabel(
          RegExp('A very long single title.*Single · 1 track', dotAll: true),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  testWidgets('releases are newest first, split into Albums, EPs and '
      'Singles, with no catalog-count line', (tester) async {
    final releases = [
      _release('a-2020', 'Old Album', released: DateTime(2020, 3, 1)),
      _release('a-none', 'Undated Album'),
      _release('a-2024', 'New Album', released: DateTime(2024, 6, 21)),
      _release('ep-2023', 'An EP', released: DateTime(2023, 1, 1)),
      _release(
        's-2025',
        '15 Minutes',
        released: DateTime(2025, 1, 10),
        trackCount: 1,
      ),
      _release('demo', 'Demo', trackCount: 2),
    ];
    await pump(
      tester,
      repository: _Repo(
        library: releases,
        artist: base.createArtist(albumCount: 6, songCount: 6),
        albums: releases,
        tracks: [
          for (final r in releases)
            base.createTrack(songId: 'song-${r.albumId}', albumId: r.albumId),
        ],
      ),
      libraryAlbums: releases,
      formats: {'ep-2023': ReleaseFormat.ep, 's-2025': ReleaseFormat.single},
    );

    expect(key('artist-profile-albums'), findsOneWidget);
    expect(key('artist-profile-eps'), findsOneWidget);
    expect(key('artist-profile-singles'), findsOneWidget);
    // A short release with no stated format is not guessed to be anything.
    expect(key('artist-profile-needs-review'), findsOneWidget);
    expect(
      find.descendant(
        of: key('artist-profile-needs-review'),
        matching: find.text('Demo'),
      ),
      findsOneWidget,
    );
    // SN-50 B-Q1: the hero no longer counts the catalog.
    expect(key('artist-profile-summary'), findsNothing);

    double left(String title) => tester.getTopLeft(find.text(title).first).dx;
    double top(String title) => tester.getTopLeft(find.text(title).first).dy;
    // Within Albums: 2024, then 2020, then the undated one.
    final order = ['New Album', 'Old Album', 'Undated Album'];
    for (var i = 0; i + 1 < order.length; i++) {
      final a = order[i];
      final b = order[i + 1];
      expect(
        top(a) < top(b) || (top(a) == top(b) && left(a) < left(b)),
        isTrue,
        reason: '$a before $b',
      );
    }
    // A Single is never listed as an Album.
    expect(
      find.descendant(
        of: key('artist-profile-albums'),
        matching: find.text('15 Minutes'),
      ),
      findsNothing,
    );
  });

  testWidgets('SN-49: live releases have one Live section, each labelled '
      'with its format, and are counted once', (tester) async {
    final releases = [
      _release('studio', 'Studio Album', released: DateTime(2024)),
      _release('concert', 'Live at the Arena', released: DateTime(2025)),
      _release(
        'session',
        'Acoustic Session',
        released: DateTime(2023),
        trackCount: 3,
      ),
      _release('tv', 'One Song Live', released: DateTime(2022), trackCount: 1),
    ];
    await pump(
      tester,
      repository: _Repo(
        library: releases,
        artist: base.createArtist(albumCount: 4, songCount: 15),
        albums: releases,
        tracks: [
          for (final r in releases)
            base.createTrack(songId: 'song-${r.albumId}', albumId: r.albumId),
        ],
      ),
      libraryAlbums: releases,
      formats: {'session': ReleaseFormat.ep, 'tv': ReleaseFormat.single},
      live: {'concert', 'session', 'tv'},
    );

    expect(key('artist-profile-live'), findsOneWidget);
    expect(key('artist-profile-eps'), findsNothing);
    expect(key('artist-profile-singles'), findsNothing);
    for (final title in ['Live at the Arena', 'Acoustic Session']) {
      expect(find.text(title), findsOneWidget, reason: 'listed once');
      expect(
        find.descendant(
          of: key('artist-profile-live'),
          matching: find.text(title),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: key('artist-profile-albums'),
        matching: find.text('Studio Album'),
      ),
      findsOneWidget,
    );
    for (final label in [
      'Album · 10 tracks',
      'EP · 3 tracks',
      'Single · 1 track',
    ]) {
      expect(
        find.descendant(
          of: key('artist-profile-live'),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(key('artist-profile-summary'), findsNothing);
    // Live comes after the formats.
    expect(
      tester.getTopLeft(key('artist-profile-albums')).dy <
          tester.getTopLeft(key('artist-profile-live')).dy,
      isTrue,
    );
  });

  testWidgets('the toolbar names the artist only after the hero scrolls away', (
    tester,
  ) async {
    final releases = [
      for (var i = 0; i < 12; i++)
        _release('album-$i', 'Album $i', released: DateTime(2010 + i)),
    ];
    await pump(
      tester,
      repository: _Repo(
        library: releases,
        artist: base.createArtist(albumCount: 12, songCount: 12),
        albums: releases,
        tracks: [
          for (final r in releases)
            base.createTrack(songId: 'song-${r.albumId}', albumId: r.albumId),
        ],
      ),
      libraryAlbums: releases,
      // Short enough that the page scrolls the hero away (the releases
      // are a single carousel row now).
      size: const Size(411, 400),
    );

    double titleOpacity() => tester
        .widget<AnimatedOpacity>(key('artist-profile-toolbar-title'))
        .opacity;

    expect(titleOpacity(), 0, reason: 'the hero names the artist');
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(
                  const PageStorageKey<String>('artist-profile-scroll'),
                ),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    await tester.drag(
      find.byKey(const PageStorageKey<String>('artist-profile-scroll')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    expect(
      position.pixels,
      greaterThan(0),
      reason: 'max ${position.maxScrollExtent}',
    );
    expect(
      titleOpacity(),
      1,
      reason: "pixels ${position.pixels} max ${position.maxScrollExtent}",
    );
  });

  testWidgets('a contributor sees where it appears, never a catalog', (
    tester,
  ) async {
    final project = _release(
      'descendants',
      'Descendants',
      artistId: 'descendants',
      artistName: 'Descendants',
      released: DateTime(2015, 7, 31),
    );
    await pump(
      tester,
      artistId: 'mitchell',
      projectArtistId: 'descendants',
      repository: _Repo(
        library: [project],
        artist: base.createArtist(
          artistId: 'mitchell',
          name: 'Mitchell Hope',
          albumCount: 0,
          songCount: 1,
        ),
        tracks: [
          base.createTrack(
            songId: 'isle',
            title: 'Isle Song',
            artistId: 'mitchell',
            artistName: 'Mitchell Hope',
            albumId: 'descendants',
            albumTitle: 'Descendants',
          ),
        ],
        allTracks: const [],
      ),
      libraryAlbums: [project],
      credits: const [
        ProjectCollaborator(
          albumId: 'descendants',
          artistId: 'mitchell',
          artistName: 'Mitchell Hope',
          roles: {SongArtistCreditRole.primary},
          songCount: 1,
        ),
      ],
    );

    expect(key('artist-profile-appearance-descendants'), findsOneWidget);
    // SN-50 B-Q2: the hero keeps the project, without a count.
    expect(
      tester.widget<Text>(key('artist-profile-summary')).data,
      'On Descendants',
    );
    expect(find.text('On Descendants'), findsNWidgets(2));
    expect(find.text('Isle Song'), findsOneWidget);
    expect(key('artist-profile-open-project-descendants'), findsOneWidget);
    for (final section in ['albums', 'eps', 'singles', 'collaborators']) {
      expect(key('artist-profile-$section'), findsNothing, reason: section);
    }
  });

  testWidgets('SN-50 B-Q30: Play on a contributor plays its songs on the '
      'project, not a catalog of its own', (tester) async {
    final descendants = _release(
      'descendants',
      'Descendants',
      artistId: 'descendants',
      artistName: 'Descendants',
      released: DateTime(2015, 7, 31),
    );
    final zombies = _release(
      'zombies',
      'Zombies',
      artistId: 'zombies',
      artistName: 'Zombies',
      released: DateTime(2018, 2, 16),
    );
    final engine = base.FakePlaybackEngine();
    addTearDown(engine.dispose);
    await pump(
      tester,
      artistId: 'mitchell',
      projectArtistId: 'descendants',
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      repository: _Repo(
        library: [descendants, zombies],
        artist: base.createArtist(
          artistId: 'mitchell',
          name: 'Mitchell Hope',
          albumCount: 0,
          songCount: 3,
        ),
        tracks: [
          base.createTrack(
            songId: 'isle',
            title: 'Isle Song',
            artistId: 'mitchell',
            artistName: 'Mitchell Hope',
            albumId: 'descendants',
            albumTitle: 'Descendants',
          ),
          base.createTrack(
            songId: 'did-i-mention',
            title: 'Did I Mention',
            artistId: 'mitchell',
            artistName: 'Mitchell Hope',
            albumId: 'descendants',
            albumTitle: 'Descendants',
          ),
          base.createTrack(
            songId: 'elsewhere',
            title: 'Elsewhere',
            artistId: 'mitchell',
            artistName: 'Mitchell Hope',
            albumId: 'zombies',
            albumTitle: 'Zombies',
          ),
        ],
        allTracks: const [],
      ),
      libraryAlbums: [descendants, zombies],
      credits: const [
        ProjectCollaborator(
          albumId: 'descendants',
          artistId: 'mitchell',
          artistName: 'Mitchell Hope',
          roles: {SongArtistCreditRole.primary},
          songCount: 2,
        ),
        ProjectCollaborator(
          albumId: 'zombies',
          artistId: 'mitchell',
          artistName: 'Mitchell Hope',
          roles: {SongArtistCreditRole.primary},
          songCount: 1,
        ),
      ],
    );

    await tester.tap(key('artist-profile-play-all-button'));
    await tester.pumpAndSettle();

    expect(
      {for (final track in engine.lastLoadedTracks!) track.songId},
      {'isle', 'did-i-mention'},
    );
  });

  testWidgets('a soundtrack says why its artist total leaves out an '
      "independent artist's songs", (tester) async {
    final project = _release(
      'descendants',
      'Descendants',
      artistId: 'descendants',
      artistName: 'Descendants',
    );
    final solo = _release(
      'bloodshot',
      'Bloodshot',
      artistId: 'dove',
      artistName: 'Dove Cameron',
    );
    await pump(
      tester,
      artistId: 'descendants',
      repository: _Repo(
        library: [project, solo],
        artist: base.createArtist(
          artistId: 'descendants',
          name: 'Descendants',
          albumCount: 1,
          songCount: 2,
        ),
        albums: [project],
        tracks: [
          base.createTrack(
            songId: 'evil',
            title: 'Evil Like Me',
            artistId: 'dove',
            artistName: 'Dove Cameron',
            albumId: 'descendants',
            albumTitle: 'Descendants',
          ),
          base.createTrack(
            songId: 'mention',
            title: 'Did I Mention',
            artistId: 'mitchell',
            artistName: 'Mitchell Hope',
            albumId: 'descendants',
            albumTitle: 'Descendants',
          ),
        ],
      ),
      libraryAlbums: [project, solo],
      credits: const [
        ProjectCollaborator(
          albumId: 'descendants',
          artistId: 'mitchell',
          artistName: 'Mitchell Hope',
          roles: {SongArtistCreditRole.primary},
          songCount: 1,
        ),
        ProjectCollaborator(
          albumId: 'descendants',
          artistId: 'dove',
          artistName: 'Dove Cameron',
          roles: {SongArtistCreditRole.primary},
          songCount: 1,
        ),
      ],
      qualifiedPlays: base.FakeQualifiedPlayRepository([
        for (var i = 0; i < 3; i++) ...[
          base.qualifiedPlay('evil', artistId: 'dove', albumId: 'descendants'),
          base.qualifiedPlay(
            'mention',
            artistId: 'mitchell',
            albumId: 'descendants',
          ),
        ],
      ]),
    );

    // Mitchell Hope's three count for the soundtrack; Dove Cameron's three
    // count for her, and the Top Tracks heading says so.
    expect(find.textContaining('3 streams'), findsWidgets);
    expect(
      find.text(
        'Your most streamed songs. Streams of songs by Dove Cameron '
        "count toward Dove Cameron's own artist total, not the one above.",
      ),
      findsOneWidget,
    );
  });
}

class _Singles implements SongSinglePresentationRepository {
  _Singles(this.rows);

  final Map<String, SongSinglePresentation> rows;

  @override
  Future<SongSinglePresentation?> getBySongId(String songId) async =>
      rows[songId];

  @override
  Future<Map<String, SongSinglePresentation>> getAll() async => rows;

  @override
  Future<void> save(SongSinglePresentation presentation) async =>
      throw StateError('read only');

  @override
  Future<void> clear(String songId) async => throw StateError('read only');
}

class _NoSongs implements SongRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('not used: $invocation');
}
