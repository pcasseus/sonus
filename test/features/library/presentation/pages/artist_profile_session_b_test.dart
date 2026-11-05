// SN-50 Session B: Artist Profile hero, release sections, Top Tracks,
// Collaborations and Collaborators. Fictional fixtures only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/core/design/sonus_theme_factory.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_tokens.dart';
import 'package:sonus_next/features/analytics/domain/repositories/qualified_play_repository.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/project_collaborator.dart';
import 'package:sonus_next/features/library/application/models/project_song_credit.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/domain/entities/library_organization.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
import 'package:sonus_next/features/library/domain/repositories/library_organization_repository.dart';
import 'package:sonus_next/features/library/presentation/pages/artist_profile_page.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';

import 'artist_profile_page_test.dart' as base;

void main() {
  Finder key(String value) => find.byKey(ValueKey<String>(value));

  Finder inside(String parent, Finder child) =>
      find.descendant(of: key(parent), matching: child);

  Future<void> pump(
    WidgetTester tester, {
    required LibraryQueryRepository repository,
    _Organization? organization,
    QualifiedPlayRepository? plays,
    PlaybackCoordinator? playbackCoordinator,
    SonusAppearanceSpec spec = const SonusAppearanceSpec(),
    Size size = const Size(411, 4000),
    double textScale = 1,
    String artistId = 'artist-1',
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      Provider<LibraryOrganizationService?>.value(
        value: LibraryOrganizationService(
          library: repository,
          collaborators: const _NoCredits(),
          organization: organization ?? _Organization(),
        ),
        child: base.buildSubject(
          repository: repository,
          qualifiedPlays: plays,
          playbackCoordinator: playbackCoordinator,
          theme: SonusThemeFactory.build(spec),
          appBuilder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: ArtistProfilePage(artistId: artistId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  base.FakeQualifiedPlayRepository streams(
    Map<String, int> counts, {
    String artistId = 'artist-1',
    String albumId = 'album-1',
  }) => base.FakeQualifiedPlayRepository([
    for (final MapEntry(key: id, value: count) in counts.entries)
      for (var i = 0; i < count; i++)
        base.qualifiedPlay(
          id,
          at: DateTime.utc(2026, 1, 1 + i),
          artistId: artistId,
          albumId: albumId,
        ),
  ]);

  group('release sections', () {
    /// One release of every kind the profile sorts, one song each.
    (_Repo, _Organization) everyShelf() {
      final releases = [
        _release('album', 'Fixture Album', released: DateTime(2024)),
        _release('inferred', 'Long Unstated', released: DateTime(2023)),
        _release('ost', 'Fixture Score', released: DateTime(2022)),
        _release('ep', 'Fixture EP', trackCount: 4),
        _release('single', 'Fixture Single', trackCount: 1),
        _release('live', 'Arena Night', trackCount: 2),
        _release('tape', 'Basement Tape', released: DateTime(2021)),
        _release('both', 'Bootleg Concert', released: DateTime(2025)),
        _release('demo', 'Demo Cut', trackCount: 2),
        _release('lost', 'Lost Files'),
      ];
      final repository = _Repo(
        library: releases,
        albums: releases,
        tracks: [
          for (final release in releases)
            base.createTrack(
              songId: 'song-${release.albumId}',
              albumId: release.albumId,
              albumTitle: release.title,
              isAvailable: release.albumId != 'lost',
              filePath: release.albumId == 'lost' ? '' : null,
            ),
        ],
      );
      final organization = _Organization(
        formats: {
          'album': ReleaseFormat.album,
          'ost': ReleaseFormat.album,
          'ep': ReleaseFormat.ep,
          'single': ReleaseFormat.single,
          'both': ReleaseFormat.album,
          'lost': ReleaseFormat.album,
        },
        live: {'live', 'both'},
        leaked: {'tape', 'both'},
        kinds: {'ost': ReleaseKind.soundtrack},
      );
      return (repository, organization);
    }

    testWidgets('run Albums, EPs, Singles, Live, Leaked, Needs Review, each '
        'release once (B-Q8/B-Q22, B-Q7)', (tester) async {
      final (repository, organization) = everyShelf();
      await pump(tester, repository: repository, organization: organization);

      final order = [
        for (final shelf in [
          'albums',
          'eps',
          'singles',
          'live',
          'leaked',
          'needs-review',
        ])
          tester.getTopLeft(key('artist-profile-$shelf')).dy,
      ];
      expect(order, [...order]..sort());
      for (final title in [
        'Fixture Album',
        'Long Unstated',
        'Fixture Score',
        'Fixture EP',
        'Fixture Single',
        'Arena Night',
        'Basement Tape',
        'Bootleg Concert',
        'Demo Cut',
        'Lost Files',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(
        inside('artist-profile-leaked', find.text('Bootleg Concert')),
        findsOneWidget,
      );
      expect(
        inside('artist-profile-needs-review', find.text('Demo Cut')),
        findsOneWidget,
      );
      expect(find.text('Needs Review'), findsOneWidget);
      expect(find.text('Other releases'), findsNothing);
    });

    testWidgets('cards say format, track count and only the indicators they '
        'need, in text (B-Q9, B-Q14, B-Q23, B-Q24, B-Q37)', (tester) async {
      final (repository, organization) = everyShelf();
      await pump(tester, repository: repository, organization: organization);

      void card(
        String id,
        List<String> texts, {
        List<String> absent = const [],
      }) {
        for (final text in texts) {
          expect(
            inside('artist-album-$id', find.text(text)),
            findsOneWidget,
            reason: '$id: $text',
          );
        }
        for (final text in absent) {
          expect(
            inside('artist-album-$id', find.text(text)),
            findsNothing,
            reason: '$id: no $text',
          );
        }
      }

      card('album', ['Album · 10 tracks'], absent: ['Format needs review']);
      // An unconfirmed format is no longer named on the card.
      card('inferred', ['Album · 10 tracks'], absent: ['Format needs review']);
      card('ost', ['Album · 10 tracks', 'Soundtrack']);
      card('ep', ['EP · 4 tracks']);
      card('single', ['Single · 1 track']);
      card('live', ['2 tracks'], absent: ['Live', 'Format needs review']);
      card('tape', ['Album · 10 tracks'], absent: ['Format needs review']);
      card('both', ['Album · 10 tracks', 'Live']);
      card('demo', ['2 tracks'], absent: ['Format needs review']);
      card('lost', ['Album · 10 tracks', 'Unavailable']);
    });

    testWidgets('every shelf fits 320dp at 2x text in all nine themes', (
      tester,
    ) async {
      for (final id in SonusThemeId.values) {
        final (repository, organization) = everyShelf();
        await pump(
          tester,
          repository: repository,
          organization: organization,
          spec: SonusAppearanceSpec(themeId: id),
          size: const Size(320, 9000),
          textScale: 2,
        );

        expect(tester.takeException(), isNull, reason: id.label);
        expect(find.text('Format needs review'), findsNothing);
      }
    });
  });

  group('hero', () {
    for (final (label, spec) in [
      (
        'Decoration Off',
        const SonusAppearanceSpec(decoration: SonusDecorationIntensity.off),
      ),
      (
        'High Contrast',
        const SonusAppearanceSpec(
          decoration: SonusDecorationIntensity.expressive,
          highContrast: true,
        ),
      ),
      (
        'Low Effects',
        const SonusAppearanceSpec(
          decoration: SonusDecorationIntensity.expressive,
          lowEffects: true,
        ),
      ),
    ]) {
      testWidgets('$label draws no gradient behind a hero without a banner '
          '(B-Q21)', (tester) async {
        await pump(tester, repository: _ownSongs(), spec: spec);

        expect(
          tester.widget(key('artist-profile-banner-fallback')),
          isA<ColoredBox>(),
        );
        expect(_gradients(tester), isEmpty);
      });
    }

    testWidgets('expressive decoration keeps the atmosphere gradient', (
      tester,
    ) async {
      await pump(
        tester,
        repository: _ownSongs(),
        spec: const SonusAppearanceSpec(
          decoration: SonusDecorationIntensity.expressive,
        ),
      );

      expect(
        tester.widget(key('artist-profile-banner-fallback')),
        isA<DecoratedBox>(),
      );
      expect(_gradients(tester), isNotEmpty);
    });

    testWidgets('a contributor on several projects names two, without counts '
        '(B-Q2)', (tester) async {
      final projects = [
        for (final name in ['Alpha Cast', 'Beta Cast', 'Gamma Cast'])
          _release(name, '$name Album', artistId: name, artistName: name),
      ];
      await pump(
        tester,
        artistId: 'guest-singer',
        repository: _Repo(
          library: projects,
          artist: base.createArtist(artistId: 'guest-singer', name: 'Guest'),
          tracks: [
            for (final project in projects)
              base.createTrack(
                songId: 'song-${project.albumId}',
                artistId: 'guest-singer',
                artistName: 'Guest',
                albumId: project.albumId,
              ),
          ],
        ),
      );

      final summary = tester.widget<Text>(key('artist-profile-summary'));
      expect(summary.data, 'On Alpha Cast, Beta Cast and others');
    });
  });

  group('Top Tracks', () {
    _Repo sevenSongs() => _ownSongs(
      tracks: [
        for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g'])
          base.createTrack(songId: id, title: 'Song $id'),
      ],
    );

    testWidgets('five rows, then See All ranks every streamed song and plays '
        'within that ranking (B-Q29/B-Q35)', (tester) async {
      final engine = base.FakePlaybackEngine();
      await pump(
        tester,
        repository: sevenSongs(),
        plays: streams({'a': 7, 'b': 6, 'c': 5, 'd': 4, 'e': 3, 'f': 2}),
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      expect(find.byKey(const ValueKey('artist-top-track-f')), findsNothing);
      await tester.tap(key('artist-profile-top-tracks-see-all'));
      await tester.pumpAndSettle();

      expect(key('artist-ranked-tracks-page'), findsOneWidget);
      for (final (index, id) in ['a', 'b', 'c', 'd', 'e', 'f'].indexed) {
        expect(
          find.byKey(ValueKey('artist-ranked-track-rank-$id')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(ValueKey('artist-ranked-track-rank-$id')),
              )
              .data,
          '${index + 1}',
        );
      }
      // Never streamed: not ranked, no count invented.
      expect(find.byKey(const ValueKey('artist-ranked-track-g')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('artist-ranked-track-f')));
      await tester.pump();
      expect(engine.lastLoadedTracks!.map((t) => t.songId), [
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
      ]);
      expect(engine.lastStartIndex, 5);
      await engine.dispose();
    });

    testWidgets('no See All when five or fewer songs are streamed', (
      tester,
    ) async {
      await pump(
        tester,
        repository: sevenSongs(),
        plays: streams({'a': 2, 'b': 1}),
      );

      expect(key('artist-profile-top-tracks-see-all'), findsNothing);
    });

    testWidgets('a row names a performer other than the owner and drops an '
        'album title equal to the song (B-Q16, B-Q20)', (tester) async {
      await pump(
        tester,
        repository: _ownSongs(
          tracks: [
            base.createTrack(
              songId: 'theirs',
              title: 'Villain Song',
              artistId: 'rival',
              artistName: 'Rival Fixture',
              albumTitle: 'Fixture Score',
            ),
            base.createTrack(
              songId: 'single',
              title: 'Same Name',
              albumTitle: 'Same Name',
            ),
          ],
        ),
        plays: streams({'theirs': 2, 'single': 1}),
      );

      expect(
        inside(
          'artist-top-track-theirs',
          find.text('2 streams • Rival Fixture • Fixture Score'),
        ),
        findsOneWidget,
      );
      expect(
        inside('artist-top-track-single', find.text('1 stream')),
        findsOneWidget,
      );
    });

    testWidgets('a song may be in both Top Tracks and Collaborations (B-Q17)', (
      tester,
    ) async {
      await pump(
        tester,
        repository: _ownSongs(
          tracks: [
            base.createTrack(
              songId: 'duet',
              title: 'Duet',
              albumId: 'their-album',
              albumTitle: 'Their Album',
            ),
          ],
        ),
        plays: streams({'duet': 3}, albumId: 'their-album'),
      );

      expect(
        find.byKey(const ValueKey('artist-top-track-duet')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('artist-track-duet')), findsOneWidget);
    });
  });

  group('song Leak label', () {
    testWidgets('shows only for a song flagged as a leak, never from its '
        'release (B-Q12/B-Q31)', (tester) async {
      final releases = [_release('tape', 'Basement Tape')];
      await pump(
        tester,
        repository: _Repo(
          library: releases,
          albums: releases,
          tracks: [
            base.createTrack(
              songId: 'flagged',
              albumId: 'tape',
              albumTitle: 'Basement Tape',
              isLeak: true,
            ),
            base.createTrack(
              songId: 'clean',
              albumId: 'tape',
              albumTitle: 'Basement Tape',
            ),
          ],
        ),
        organization: _Organization(leaked: {'tape'}),
        plays: streams({'flagged': 2, 'clean': 1}, albumId: 'tape'),
      );

      expect(
        inside(
          'artist-top-track-flagged',
          find.text('Leak • 2 streams • Basement Tape'),
        ),
        findsOneWidget,
      );
      expect(
        inside('artist-top-track-clean', find.text('1 stream • Basement Tape')),
        findsOneWidget,
      );
    });
  });

  group('Collaborations and Collaborators', () {
    /// The owner's album with a featured guest, a co-lead, an unverified
    /// name and another lead's song; plus a feature on someone else's song.
    _CreditRepo project() => _CreditRepo(
      artist: base.createArtist(),
      albums: [base.createAlbum()],
      mainTracks: [
        base.createTrack(songId: 'own', title: 'Own Song'),
        base.createTrack(
          songId: 'duet',
          title: 'Duet Abroad',
          albumId: 'their-album',
          albumTitle: 'Their Album',
        ),
      ],
      collaborationTracks: [
        base.createTrack(
          songId: 'feature',
          title: 'Guest Spot',
          artistId: 'pal',
          artistName: 'Pal Fixture',
          albumId: 'their-album',
          albumTitle: 'Their Album',
        ),
      ],
      allTracks: [
        base.createTrack(songId: 'own', title: 'Own Song'),
        base.createTrack(
          songId: 'theirs',
          title: 'Their Turn',
          artistId: 'pal',
          artistName: 'Pal Fixture',
        ),
      ],
      artists: [base.createArtist(artistId: 'pal', name: 'Pal Fixture')],
      credits: const [
        ProjectSongCredit(
          albumId: 'album-1',
          songId: 'own',
          artistId: 'artist-1',
          creditedName: 'Test Artist',
          role: SongArtistCreditRole.primary,
        ),
        ProjectSongCredit(
          albumId: 'album-1',
          songId: 'own',
          artistId: 'pal',
          creditedName: 'Pal Fixture',
          role: SongArtistCreditRole.featured,
        ),
        ProjectSongCredit(
          albumId: 'album-1',
          songId: 'own',
          creditedName: 'Unlinked Fixture',
          role: SongArtistCreditRole.guest,
        ),
        ProjectSongCredit(
          albumId: 'album-1',
          songId: 'theirs',
          artistId: 'pal',
          creditedName: 'Pal Fixture',
          role: SongArtistCreditRole.primary,
        ),
      ],
    );

    testWidgets('Collaborators lists featured, guest and unverified credits '
        'under the agreed subtitle (B-Q15, B-Q34, B-Q32)', (tester) async {
      await pump(tester, repository: project());

      expect(find.text('Artists who appear on these releases'), findsOneWidget);
      expect(
        inside('artist-collaborator-pal', find.text('Lead · 2 songs')),
        findsOneWidget,
      );
      expect(
        inside(
          'artist-collaborator-name-Unlinked Fixture',
          find.text('Guest · 1 song'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an unverified name is shown but opens nothing (B-Q33)', (
      tester,
    ) async {
      await pump(tester, repository: project());

      await tester.tap(key('artist-collaborator-name-Unlinked Fixture'));
      await tester.pumpAndSettle();
      expect(find.byType(ArtistProfilePage), findsOneWidget);

      await tester.tap(key('artist-collaborator-pal'));
      await tester.pumpAndSettle();
      expect(
        find.byType(ArtistProfilePage, skipOffstage: false),
        findsNWidgets(2),
      );
    });

    testWidgets('collaborator Play plays every credited contribution '
        '(B-Q26)', (tester) async {
      final engine = base.FakePlaybackEngine();
      await pump(
        tester,
        repository: project(),
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await tester.tap(key('artist-collaborator-play-pal'));
      await tester.pump();

      expect(engine.lastLoadedTracks!.map((t) => t.songId).toSet(), {
        'own',
        'theirs',
      });
      await engine.dispose();
    });

    testWidgets('a Collaboration plays within the Collaborations queue, '
        'featured songs included (B-Q27)', (tester) async {
      final engine = base.FakePlaybackEngine();
      await pump(
        tester,
        repository: project(),
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      // SN-51 C1: both songs are on one release, so they sit in its
      // group; the queue is still every collaboration.
      await tester.tap(key('artist-collaboration-group-their-album-header'));
      await tester.pumpAndSettle();
      await tester.tap(key('artist-track-feature'));
      await tester.pump();

      expect(engine.lastLoadedTracks!.map((t) => t.songId).toSet(), {
        'feature',
        'duet',
      });
      await engine.dispose();
    });

    testWidgets('Play All is the main catalogue, never featured-only songs '
        '(B-Q18)', (tester) async {
      final engine = base.FakePlaybackEngine();
      await pump(
        tester,
        repository: project(),
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await tester.tap(key('artist-profile-play-all-button'));
      await tester.pump();

      final queued = engine.lastLoadedTracks!.map((t) => t.songId).toSet();
      expect(queued, containsAll(['own', 'duet', 'theirs']));
      expect(queued, isNot(contains('feature')));
      await engine.dispose();
    });
  });
}

/// Every gradient painted on the page.
List<Gradient> _gradients(WidgetTester tester) => [
  for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)))
    if (box.decoration case BoxDecoration(:final gradient?)) gradient,
];

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
  dateAdded: DateTime(2026),
);

/// The artist's own album with [tracks] (one song by default).
_Repo _ownSongs({List<LibraryTrack>? tracks}) {
  final album = base.createAlbum();
  return _Repo(
    library: [album],
    albums: [album],
    tracks: tracks ?? [base.createTrack()],
  );
}

/// The profile page's fake, also listing every release in the library.
class _Repo extends base.FakeLibraryQueryRepository {
  _Repo({
    required this.library,
    LibraryArtist? artist,
    super.albums,
    super.tracks,
  }) : super(artist: artist ?? base.createArtist());

  final List<LibraryAlbum> library;

  @override
  Future<List<LibraryAlbum>> getAlbums() async => library;
}

/// A structured repository with song-level project credits.
class _CreditRepo extends base.FakeStructuredLibraryQueryRepository
    implements ProjectSongCreditQueryRepository {
  _CreditRepo({
    super.artist,
    super.albums,
    super.allTracks,
    super.mainTracks,
    super.collaborationTracks,
    super.artists,
    required this.credits,
  });

  final List<ProjectSongCredit> credits;

  @override
  Future<List<LibraryAlbum>> getAlbums() async => albums;

  @override
  Future<List<ProjectSongCredit>> getProjectSongCredits(String albumId) async =>
      [
        for (final credit in credits)
          if (credit.albumId == albumId) credit,
      ];
}

class _NoCredits implements ProjectCollaboratorQueryRepository {
  const _NoCredits();

  @override
  Future<List<ProjectCollaborator>> getProjectCollaborators({
    String? albumId,
  }) async => const [];
}

class _Organization implements LibraryOrganizationRepository {
  _Organization({
    this.formats = const {},
    this.live = const {},
    this.leaked = const {},
    this.kinds = const {},
  });

  final Map<String, ReleaseFormat> formats;
  final Set<String> live;
  final Set<String> leaked;
  final Map<String, ReleaseKind> kinds;

  static final DateTime _at = DateTime(2026);

  @override
  Future<List<AlbumReleaseFormat>> getFormats() async => [
    for (final MapEntry(key: albumId, value: format) in formats.entries)
      AlbumReleaseFormat(
        albumId: albumId,
        format: format,
        authority: ReleaseClassificationAuthority.manual,
        createdAt: _at,
        updatedAt: _at,
      ),
  ];

  @override
  Future<List<AlbumReleaseClassification>> getClassifications() async => [
    for (final MapEntry(key: albumId, value: kind) in kinds.entries)
      AlbumReleaseClassification(
        albumId: albumId,
        kind: kind,
        authority: ReleaseClassificationAuthority.manual,
        createdAt: _at,
        updatedAt: _at,
      ),
  ];

  @override
  Future<List<ArtistProjectAssignment>> getAssignments() async => const [];

  @override
  Future<List<AlbumLiveClassification>> getLiveClassifications() async => [
    for (final albumId in live)
      AlbumLiveClassification(
        albumId: albumId,
        isLive: true,
        authority: ReleaseClassificationAuthority.manual,
        createdAt: _at,
        updatedAt: _at,
      ),
  ];

  @override
  Future<List<AlbumLeakedClassification>> getLeakedClassifications() async => [
    for (final albumId in leaked)
      AlbumLeakedClassification(
        albumId: albumId,
        createdAt: _at,
        updatedAt: _at,
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
