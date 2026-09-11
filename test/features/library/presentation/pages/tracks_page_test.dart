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
import 'package:sonus_next/features/library/presentation/pages/tracks_page.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

void main() {
  group('TracksPage', () {
    testWidgets(
      'shows stable tracks destination while repository is unavailable',
      (tester) async {
        await tester.pumpWidget(buildSubject(repository: null));

        expect(
          find.byKey(const ValueKey<String>('app-destination-tracks')),
          findsOneWidget,
        );

        expect(find.text('Loading tracks…'), findsOneWidget);

        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('shows loading state while tracks are loading', (tester) async {
      final completer = Completer<List<LibraryTrack>>();

      final repository = FakeLibraryQueryRepository(
        tracksLoader: (_) => completer.future,
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('app-destination-tracks')),
        findsOneWidget,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(const []);

      await tester.pump();
      await tester.pump();
    });

    testWidgets('shows empty state when there are no tracks', (tester) async {
      final repository = FakeLibraryQueryRepository(tracks: const []);

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('No tracks yet'), findsOneWidget);

      expect(
        find.text('Import music to start building your library.'),
        findsOneWidget,
      );
    });

    testWidgets('shows error state when track loading fails', (tester) async {
      final repository = FakeLibraryQueryRepository(
        tracksError: StateError('track load failed'),
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Could not load your tracks.'), findsOneWidget);

      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('renders loaded tracks and their runtimes', (tester) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [
          createTrack(
            songId: 'song-1',
            title: 'First Song',
            artistName: 'First Artist',
            albumTitle: 'First Album',
            trackNumber: 1,
            durationSeconds: 245,
          ),
          createTrack(
            songId: 'song-2',
            title: 'Second Song',
            artistName: 'Second Artist',
            albumTitle: 'Second Album',
            trackNumber: 2,
            durationSeconds: 62,
          ),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('app-destination-tracks')),
        findsOneWidget,
      );

      expect(find.text('First Song'), findsOneWidget);
      expect(find.text('Second Song'), findsOneWidget);

      expect(find.text('First Artist • First Album'), findsOneWidget);
      expect(find.text('Second Artist • Second Album'), findsOneWidget);

      expect(find.text('4:05'), findsOneWidget);
      expect(find.text('1:02'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('tracks-order-dropdown')),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey<String>('tracks-shuffle-button')),
        findsOneWidget,
      );

      expect(
        find.byKey(const ValueKey<String>('tracks-play-all-button')),
        findsOneWidget,
      );
    });

    testWidgets('marks unavailable tracks as disabled', (tester) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [
          createTrack(songId: 'available', title: 'Available Song'),
          createTrack(
            songId: 'unavailable',
            title: 'Unavailable Song',
            isAvailable: false,
            filePath: null,
          ),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      final availableTile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('track-available')),
      );

      final unavailableTile = tester.widget<ListTile>(
        find.byKey(const ValueKey<String>('track-unavailable')),
      );

      expect(availableTile.enabled, isTrue);
      expect(unavailableTile.enabled, isFalse);

      expect(
        tester
            .widget<PopupMenuButton<dynamic>>(
              find.byKey(const ValueKey<String>('track-menu-unavailable')),
            )
            .enabled,
        isFalse,
      );
    });

    testWidgets('changing order reloads tracks using selected order', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        tracks: [createTrack(songId: 'song-1', title: 'Song')],
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(repository.requestedOrders, [LibraryTrackOrder.title]);

      await tester.tap(
        find.byKey(const ValueKey<String>('tracks-order-dropdown')),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Artist name').last);

      await tester.pumpAndSettle();

      expect(repository.requestedOrders, [
        LibraryTrackOrder.title,
        LibraryTrackOrder.artist,
      ]);
    });

    testWidgets('retry reloads tracks after an error', (tester) async {
      var shouldFail = true;

      final repository = FakeLibraryQueryRepository(
        tracksLoader: (_) async {
          if (shouldFail) {
            throw StateError('failed');
          }

          return [createTrack(songId: 'song-1', title: 'Recovered Song')];
        },
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Could not load your tracks.'), findsOneWidget);

      shouldFail = false;

      await tester.tap(find.text('Try again'));

      await tester.pumpAndSettle();

      expect(find.text('Recovered Song'), findsOneWidget);
    });
  });
}

Widget buildSubject({required LibraryQueryRepository? repository}) {
  final engine = NoOpPlaybackEngine();

  final coordinator = PlaybackCoordinator(engine: engine);

  return MultiProvider(
    providers: [
      Provider<LibraryQueryRepository?>.value(value: repository),
      Provider<PlaybackCoordinator>.value(value: coordinator),
    ],
    child: const MaterialApp(home: Scaffold(body: TracksPage())),
  );
}

LibraryTrack createTrack({
  required String songId,
  required String title,
  String artistId = 'artist-1',
  String artistName = 'Artist',
  String albumId = 'album-1',
  String albumTitle = 'Album',
  String albumEditionId = 'edition-1',
  String albumEditionTitle = 'Standard',
  int trackNumber = 1,
  int durationSeconds = 180,
  bool isSingle = false,
  List<String> featuredArtists = const [],
  DateTime? dateAdded,
  String? filePath = '/music/song.mp3',
  bool isAvailable = true,
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: artistId,
    artistName: artistName,
    albumId: albumId,
    albumTitle: albumTitle,
    albumEditionId: albumEditionId,
    albumEditionTitle: albumEditionTitle,
    albumEditionType: AlbumEditionType.values.first,
    trackNumber: trackNumber,
    durationSeconds: durationSeconds,
    isSingle: isSingle,
    featuredArtists: featuredArtists,
    dateAdded: dateAdded ?? DateTime(2026, 1, 1),
    filePath: filePath,
    isAvailable: isAvailable,
  );
}

class FakeLibraryQueryRepository implements LibraryQueryRepository {
  FakeLibraryQueryRepository({
    this.tracks = const [],
    this.tracksError,
    this.tracksLoader,
  });

  final List<LibraryTrack> tracks;
  final Object? tracksError;

  final Future<List<LibraryTrack>> Function(LibraryTrackOrder order)?
  tracksLoader;

  final List<LibraryTrackOrder> requestedOrders = [];

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    requestedOrders.add(order);

    final loader = tracksLoader;

    if (loader != null) {
      return loader(order);
    }

    final error = tracksError;

    if (error != null) {
      throw error;
    }

    return tracks;
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
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

class NoOpPlaybackEngine implements PlaybackEngine {
  @override
  Stream<PlaybackState> get states => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}
