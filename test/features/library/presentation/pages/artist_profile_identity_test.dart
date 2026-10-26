// SN-45 Artist Profile: identity, release sections and the compact toolbar
// title. Uses the profile page's own fakes plus a real
// LibraryOrganizationService over in-memory organization data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/project_collaborator.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/domain/repositories/library_organization_repository.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_profile_page.dart';

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
    String artistId = 'artist-1',
    String? projectArtistId,
    Size size = const Size(411, 2400),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final organization = LibraryOrganizationService(
      library: _AlbumsOnly(libraryAlbums),
      collaborators: _Credits(libraryAlbums, credits),
      organization: _Organization(formats),
    );
    await tester.pumpWidget(
      Provider<LibraryOrganizationService?>.value(
        value: organization,
        child: base.buildSubject(
          repository: repository,
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

  testWidgets('releases are newest first, split into Albums, EPs and '
      'Singles, with accurate counts', (tester) async {
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
    expect(key('artist-profile-other-releases'), findsOneWidget);
    expect(
      find.descendant(
        of: key('artist-profile-other-releases'),
        matching: find.text('Demo'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('3 albums • 1 EP • 1 single • 1 other release • 6 songs'),
      findsOneWidget,
    );

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
      size: const Size(411, 800),
    );

    double titleOpacity() => tester
        .widget<AnimatedOpacity>(key('artist-profile-toolbar-title'))
        .opacity;

    expect(titleOpacity(), 0, reason: 'the hero names the artist');
    await tester.drag(
      find.byKey(const PageStorageKey<String>('artist-profile-scroll')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    expect(titleOpacity(), 1);
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
    expect(find.text('On Descendants'), findsOneWidget);
    expect(find.text('On Descendants · 1 song'), findsOneWidget);
    expect(find.text('Isle Song'), findsOneWidget);
    expect(key('artist-profile-open-project-descendants'), findsOneWidget);
    for (final section in ['albums', 'eps', 'singles', 'collaborators']) {
      expect(key('artist-profile-$section'), findsNothing, reason: section);
    }
  });
}
