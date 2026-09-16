import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
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

class FakeLibraryQueryRepository implements LibraryQueryRepository {
  FakeLibraryQueryRepository({
    this.artists = const [],
    this.artistsError,
    this.artistsLoader,
  });

  final List<LibraryArtist> artists;
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
    return const [];
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return const [];
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
