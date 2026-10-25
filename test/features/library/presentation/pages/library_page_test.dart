import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/pages/library_page.dart';

void main() {
  group('LibraryPage', () {
    testWidgets(
      'shows stable library destination while repository is unavailable',
      (tester) async {
        await tester.pumpWidget(buildSubject(repository: null));

        expect(
          find.byKey(const ValueKey<String>('app-destination-library')),
          findsOneWidget,
        );

        expect(find.text('Loading library\u2026'), findsOneWidget);

        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('shows loading state while artists are loading', (
      tester,
    ) async {
      final completer = Completer<List<LibraryArtist>>();

      final repository = FakeLibraryQueryRepository(
        artistsLoader: () => completer.future,
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(const []);

      await tester.pump();
      await tester.pump();
    });

    testWidgets('shows empty state when there are no artists', (tester) async {
      final repository = FakeLibraryQueryRepository(artists: const []);

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('No artists yet'), findsOneWidget);
    });

    testWidgets('shows error state when artist loading fails', (tester) async {
      final repository = FakeLibraryQueryRepository(
        artistsError: StateError('artist load failed'),
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Could not load your artists.'), findsOneWidget);

      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('renders artists in a two-column grid', (tester) async {
      final repository = FakeLibraryQueryRepository(
        artists: [
          createArtist(
            artistId: 'artist-1',
            name: 'Taylor Swift',
            albumCount: 12,
            songCount: 150,
          ),
          createArtist(
            artistId: 'artist-2',
            name: 'Beyonc\u00e9',
            albumCount: 8,
            songCount: 94,
          ),
          createArtist(
            artistId: 'artist-3',
            name: 'SZA',
            albumCount: 2,
            songCount: 42,
          ),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('app-destination-library')),
        findsOneWidget,
      );

      expect(
        find.byKey(const PageStorageKey<String>('artists-grid')),
        findsOneWidget,
      );

      expect(find.text('Taylor Swift'), findsOneWidget);
      expect(find.text('Beyonc\u00e9'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('artist-album-count-artist-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('artist-song-count-artist-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('artist-album-count-artist-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('artist-song-count-artist-2')),
        findsOneWidget,
      );

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('SZA'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('artist-album-count-artist-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('artist-song-count-artist-3')),
        findsOneWidget,
      );

      final grid = tester.widget<SliverGrid>(
        find.byKey(const PageStorageKey<String>('artists-grid')),
      );

      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;

      expect(delegate.crossAxisCount, 2);
    });

    testWidgets('exposes singular album and song stat labels', (tester) async {
      final repository = FakeLibraryQueryRepository(
        artists: [
          createArtist(
            artistId: 'artist-1',
            name: 'Solo Artist',
            albumCount: 1,
            songCount: 1,
          ),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('artist-album-count-artist-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('artist-song-count-artist-1')),
        findsOneWidget,
      );
    });

    testWidgets('shows initials for artist cards', (tester) async {
      final repository = FakeLibraryQueryRepository(
        artists: [
          createArtist(artistId: 'artist-1', name: 'Taylor Swift'),
          createArtist(artistId: 'artist-2', name: 'SZA'),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('TS'), findsOneWidget);

      expect(find.text('S'), findsOneWidget);
    });

    testWidgets('ghosts artist whose only media is unavailable', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        artists: [
          createArtist(artistId: 'available-artist', name: 'Available Artist'),
          createArtist(artistId: 'missing-artist', name: 'Missing Artist'),
        ],
        tracks: [
          createTrack(songId: 'available-song', artistId: 'available-artist'),
          createTrack(
            songId: 'missing-song',
            artistId: 'missing-artist',
            filePath: '',
            isAvailable: false,
          ),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      expect(find.text('Available Artist'), findsOneWidget);
      expect(find.text('Missing Artist'), findsNothing);
      expect(find.text('1 artist in your library'), findsOneWidget);
    });

    testWidgets(
      'keeps album owner visible when available track has another primary artist',
      (tester) async {
        final repository = FakeLibraryQueryRepository(
          artists: [createArtist(artistId: 'album-owner', name: 'Album Owner')],
          albums: [
            createAlbum(albumId: 'owned-album', artistId: 'album-owner'),
          ],
          tracks: [
            createTrack(
              songId: 'other-primary-song',
              artistId: 'other-primary',
              albumId: 'owned-album',
            ),
          ],
        );

        await tester.pumpWidget(buildSubject(repository: repository));
        await tester.pumpAndSettle();

        expect(find.text('Album Owner'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('artist-open-album-owner')),
          findsOneWidget,
        );
      },
    );

    // SN-48I: nothing in the data marks an album as a soundtrack, cast or
    // group project, so performers on someone else's multi-artist album are
    // never hidden from the grid.
    testWidgets('keeps every performer on a multi-artist album visible', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = FakeLibraryQueryRepository(
        artists: [
          createArtist(artistId: 'cast', name: 'Fixture Cast'),
          createArtist(artistId: 'lead', name: 'Fixture Lead'),
          createArtist(artistId: 'rival', name: 'Fixture Rival'),
          createArtist(artistId: 'guest', name: 'Fixture Guest'),
        ],
        albums: [createAlbum(albumId: 'soundtrack', artistId: 'cast')],
        tracks: [
          createTrack(songId: 't1', artistId: 'lead', albumId: 'soundtrack'),
          createTrack(songId: 't2', artistId: 'rival', albumId: 'soundtrack'),
          createTrack(songId: 't3', artistId: 'guest', albumId: 'soundtrack'),
          createTrack(songId: 't4', artistId: 'cast', albumId: 'soundtrack'),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));
      await tester.pumpAndSettle();

      for (final name in [
        'Fixture Cast',
        'Fixture Lead',
        'Fixture Rival',
        'Fixture Guest',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('4 artists in your library'), findsOneWidget);
    });

    // Regression (SN-48I emulator QA): large counts overflowed the card's
    // stats row at 320dp with 2x text.
    testWidgets('artist cards fit 320dp at 2x text with large counts', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = FakeLibraryQueryRepository(
        artists: [
          createArtist(
            artistId: 'artist-1',
            name: 'The Extraordinarily Long Fixture Ensemble',
            albumCount: 12,
            songCount: 148,
          ),
        ],
      );

      await tester.pumpWidget(
        Provider<LibraryQueryRepository?>.value(
          value: repository,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(body: LibraryPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('artist-song-count-artist-1')),
        findsOneWidget,
      );
    });

    testWidgets('tapping an artist opens the artist profile', (tester) async {
      final repository = FakeLibraryQueryRepository(
        artists: [
          createArtist(
            artistId: 'artist-1',
            name: 'Test Artist',
            albumCount: 1,
            songCount: 1,
          ),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('artist-open-artist-1')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('artist-open-artist-1')),
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('artist-profile-page')),
        findsOneWidget,
      );
    });

    testWidgets('retry reloads artists after an error', (tester) async {
      var shouldFail = true;

      final repository = FakeLibraryQueryRepository(
        artistsLoader: () async {
          if (shouldFail) {
            throw StateError('failed');
          }

          return [createArtist(artistId: 'artist-1', name: 'Recovered Artist')];
        },
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Could not load your artists.'), findsOneWidget);

      shouldFail = false;

      await tester.tap(find.text('Try again'));

      await tester.pumpAndSettle();

      expect(find.text('Recovered Artist'), findsOneWidget);
    });
  });
}

Widget buildSubject({required LibraryQueryRepository? repository}) {
  return Provider<LibraryQueryRepository?>.value(
    value: repository,
    child: const MaterialApp(home: Scaffold(body: LibraryPage())),
  );
}

LibraryArtist createArtist({
  required String artistId,
  required String name,
  int albumCount = 0,
  int songCount = 0,
  DateTime? dateAdded,
}) {
  return LibraryArtist(
    artistId: artistId,
    name: name,
    albumCount: albumCount,
    songCount: songCount,
    dateAdded: dateAdded ?? DateTime(2026, 1, 1),
  );
}

LibraryAlbum createAlbum({
  String albumId = 'album-1',
  String artistId = 'artist-1',
}) {
  return LibraryAlbum(
    albumId: albumId,
    title: 'Test Album',
    artistId: artistId,
    artistName: 'Test Artist',
    trackCount: 1,
    dateAdded: DateTime(2026, 1, 1),
  );
}

LibraryTrack createTrack({
  String songId = 'song-1',
  String artistId = 'artist-1',
  String albumId = 'album-1',
  String? filePath,
  bool isAvailable = true,
}) {
  return LibraryTrack(
    songId: songId,
    title: 'Test Song',
    artistId: artistId,
    artistName: 'Test Artist',
    albumId: albumId,
    albumTitle: 'Test Album',
    albumEditionId: 'edition-1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.values.first,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime(2026, 1, 1),
    filePath: filePath ?? '/music/$songId.mp3',
    isAvailable: isAvailable,
    isSongBlocked: false,
  );
}

class FakeLibraryQueryRepository implements LibraryQueryRepository {
  FakeLibraryQueryRepository({
    this.artists = const [],
    this.albums = const [],
    this.tracks,
    this.artistsError,
    this.artistsLoader,
  });

  final List<LibraryArtist> artists;
  final List<LibraryAlbum> albums;
  final List<LibraryTrack>? tracks;
  final Object? artistsError;
  final Future<List<LibraryArtist>> Function()? artistsLoader;

  @override
  Future<List<LibraryArtist>> getArtists() async {
    final loader = artistsLoader;

    if (loader != null) {
      return loader();
    }

    final error = artistsError;

    if (error != null) {
      throw error;
    }

    return artists;
  }

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    final explicitTracks = tracks;

    if (explicitTracks != null) {
      return explicitTracks;
    }

    final loadedArtists = await getArtists();

    return loadedArtists
        .map(
          (artist) => createTrack(
            songId: 'song-${artist.artistId}',
            artistId: artist.artistId,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return albums;
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    return null;
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    return const [];
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async {
    return const [];
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    return null;
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async {
    return const [];
  }

  @override
  Future<LibraryTrack?> getTrackById(String songId) async {
    return null;
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
    return const [];
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return const [];
  }
}
