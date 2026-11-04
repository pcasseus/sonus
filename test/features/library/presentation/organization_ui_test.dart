import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/project_collaborator.dart';
import 'package:sonus_next/features/library/application/models/project_song_credit.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/presentation/models/artist_profile_sections.dart';
import 'package:sonus_next/features/library/presentation/pages/library_page.dart';
import 'package:sonus_next/features/library/presentation/widgets/library_view_switch.dart';
import 'package:sonus_next/features/library/presentation/widgets/artist_profile/artist_library_placement_sheet.dart';

import 'pages/library_page_test.dart' as lib;

// Soundtrack collaborators and reversible Library organization (UI).
void main() {
  group('credited collaborators', () {
    ProjectSongCredit credit(
      String album,
      String song,
      String artist,
      SongArtistCreditRole role,
    ) => ProjectSongCredit(
      albumId: album,
      songId: song,
      artistId: artist,
      creditedName: 'Name $artist',
      role: role,
    );

    test('lists every credited performer once, by role, then songs', () {
      final tracks = [
        for (final id in ['a1', 'a2', 'b1', 'b2', 'b3', 's1'])
          lib.createTrack(songId: id, artistId: 'owner', albumId: 'ost'),
      ];
      final result = ArtistProfileSections.creditedCollaborators(
        ownerArtistId: 'owner',
        credits: [
          credit('ost', 'a1', 'owner', SongArtistCreditRole.primary),
          credit('ost', 'a1', 'lead-a', SongArtistCreditRole.primary),
          credit('ost', 'a2', 'lead-a', SongArtistCreditRole.primary),
          for (final song in ['b1', 'b2', 'b3'])
            credit('ost', song, 'lead-b', SongArtistCreditRole.primary),
          credit('ost', 'b1', 'guest', SongArtistCreditRole.featured),
          // Merged across the owner's projects.
          credit('sequel', 's1', 'lead-a', SongArtistCreditRole.coPrimary),
        ],
        projectTracks: tracks,
        tracksById: {for (final track in tracks) track.songId: track},
        artistsById: const {},
      );

      expect(
        [for (final c in result) c.artistId],
        [
          'lead-a', // primary, 3 songs
          'lead-b', // primary, 3 songs
          'guest', // featured
        ],
      );
      expect(result.first.displaySongCount, 3);
      expect(result.first.roles, {
        SongArtistCreditRole.primary,
        SongArtistCreditRole.coPrimary,
      });
      expect(result.last.leadRole, SongArtistCreditRole.featured);
      expect([for (final t in result.last.tracks) t.songId], ['b1']);
    });
  });

  group('Library list', () {
    Future<void> pumpLibrary(
      WidgetTester tester,
      LibraryOrganizationService organization,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<LibraryQueryRepository?>.value(
              value: lib.FakeLibraryQueryRepository(
                artists: [
                  lib.createArtist(artistId: 'lead', name: 'Lead Artist'),
                  lib.createArtist(artistId: 'cast', name: 'Cast Member'),
                ],
              ),
            ),
            Provider<LibraryOrganizationService?>.value(value: organization),
          ],
          child: MaterialApp(
            theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
            home: const Scaffold(
              body: LibraryPage(initialView: LibraryView.filmReel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a grouped performer leaves the list, and says where', (
      tester,
    ) async {
      await pumpLibrary(tester, _FakeOrganization(grouped: {'cast': 'ost'}));

      expect(find.text('Lead Artist'), findsOneWidget);
      expect(find.text('Cast Member'), findsNothing);
      // A plain count of the artists listed; no note about grouping.
      expect(find.text('1 artist'), findsOneWidget);
      expect(find.textContaining('listed under a project'), findsNothing);
    });

    testWidgets('everyone is shown when organization cannot be read', (
      tester,
    ) async {
      await pumpLibrary(tester, _FakeOrganization(failLoad: true));

      expect(find.text('Lead Artist'), findsOneWidget);
      expect(find.text('Cast Member'), findsOneWidget);
    });
  });

  group('Library placement sheet', () {
    Future<_FakeOrganization> pumpSheet(
      WidgetTester tester, {
      Map<String, String> grouped = const {},
      Set<String> manual = const {},
      ProjectAssignmentRefusal? refusal,
    }) async {
      final service = _FakeOrganization(
        grouped: grouped,
        manual: manual,
        refusal: refusal,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: SonusThemeFactory.build(const SonusAppearanceSpec()),
          home: Scaffold(
            body: ArtistLibraryPlacementSheet(
              artistId: 'cast',
              artistName: 'Cast Member',
              service: service,
              library: _FakeAlbums(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return service;
    }

    Finder key(String value) => find.byKey(ValueKey<String>(value));

    testWidgets('assigning previews first and acts only on confirm', (
      tester,
    ) async {
      final service = await pumpSheet(tester);

      expect(
        find.text(
          'Shown as its own artist, because it has releases of its own.',
        ),
        findsOneWidget,
      );
      await tester.tap(key('artist-placement-project-ost'));
      await tester.pumpAndSettle();

      expect(key('artist-placement-preview'), findsOneWidget);
      expect(find.textContaining('3 songs on Movie OST'), findsOneWidget);
      expect(service.calls, isEmpty);

      await tester.tap(key('artist-placement-confirm'));
      await tester.pumpAndSettle();
      expect(service.calls, ['assign cast ost']);
    });

    testWidgets('a refused assignment explains why and changes nothing', (
      tester,
    ) async {
      final service = await pumpSheet(
        tester,
        refusal: ProjectAssignmentRefusal.ownsAlbums,
      );

      await tester.tap(key('artist-placement-project-ost'));
      await tester.pumpAndSettle();

      expect(key('artist-placement-refused'), findsOneWidget);
      expect(find.textContaining('albums of their own'), findsOneWidget);
      expect(service.calls, isEmpty);
    });

    testWidgets('an automatic grouping can be undone per artist', (
      tester,
    ) async {
      final service = await pumpSheet(tester, grouped: {'cast': 'ost'});

      expect(find.textContaining('Listed under Movie OST'), findsOneWidget);
      await tester.tap(key('artist-placement-own'));
      await tester.pumpAndSettle();
      expect(service.calls, ['own cast']);
    });

    testWidgets('the user\'s own choice can be undone', (tester) async {
      final service = await pumpSheet(
        tester,
        grouped: {'cast': 'ost'},
        manual: {'cast'},
      );

      expect(find.textContaining('(your choice)'), findsOneWidget);
      await tester.tap(key('artist-placement-undo'));
      await tester.pumpAndSettle();
      expect(service.calls, ['clear cast']);
    });
  });
}

/// Organization with artist -> project groupings; [manual] marks the
/// user's own choices.
class _FakeOrganization implements LibraryOrganizationService {
  _FakeOrganization({
    this.grouped = const {},
    this.manual = const {},
    this.refusal,
    this.failLoad = false,
  });

  final Map<String, String> grouped;
  final Set<String> manual;
  final ProjectAssignmentRefusal? refusal;
  final bool failLoad;
  final List<String> calls = [];

  @override
  Future<ArtistLibraryOrganization> load() async {
    if (failLoad) throw StateError('unreadable');
    return ArtistLibraryOrganization(
      placements: {
        for (final MapEntry(key: artist, value: album) in grouped.entries)
          artist: ArtistLibraryPlacement(
            artistId: artist,
            reason: manual.contains(artist)
                ? ArtistPlacementReason.manual
                : ArtistPlacementReason.automatic,
            projectAlbumId: album,
            projectAlbumIds: [album],
            isShown: false,
          ),
      },
      classifications: const {},
    );
  }

  @override
  ProjectCollaboratorQueryRepository get collaborators => _FakeCredits();

  @override
  Future<ProjectAssignmentPreview> previewAssignment({
    required String artistId,
    required String albumId,
  }) async => ProjectAssignmentPreview(
    artistId: artistId,
    albumId: albumId,
    songsOnProject: 3,
    songsElsewhere: 0,
    refusal: refusal,
  );

  @override
  Future<ProjectAssignmentPreview> assignToProject({
    required String artistId,
    required String albumId,
  }) async {
    calls.add('assign $artistId $albumId');
    return previewAssignment(artistId: artistId, albumId: albumId);
  }

  @override
  Future<void> showAsOwnArtist(String artistId) async =>
      calls.add('own $artistId');

  @override
  Future<void> clearAssignment(String artistId) async =>
      calls.add('clear $artistId');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCredits implements ProjectCollaboratorQueryRepository {
  @override
  Future<List<ProjectCollaborator>> getProjectCollaborators({
    String? albumId,
  }) async => const [
    ProjectCollaborator(
      albumId: 'ost',
      artistId: 'cast',
      artistName: 'Cast Member',
      roles: {SongArtistCreditRole.primary},
      songCount: 3,
    ),
  ];
}

class _FakeAlbums extends lib.FakeLibraryQueryRepository {
  _FakeAlbums()
    : super(
        albums: [
          LibraryAlbum(
            albumId: 'ost',
            title: 'Movie OST',
            artistId: 'studio',
            artistName: 'Film Studio',
            trackCount: 9,
            dateAdded: DateTime(2026, 1, 1),
          ),
        ],
      );
}
