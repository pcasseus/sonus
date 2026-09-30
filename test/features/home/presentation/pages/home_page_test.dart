import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/home/application/models/home_popular_track.dart';
import 'package:sonus_next/features/home/application/models/home_snapshot.dart';
import 'package:sonus_next/features/home/application/models/home_top_artist.dart';
import 'package:sonus_next/features/home/application/services/home_data_service.dart';
import 'package:sonus_next/features/home/presentation/controllers/home_controller.dart';
import 'package:sonus_next/features/home/presentation/pages/home_page.dart';
import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';

void main() {
  testWidgets('renders populated Home sections', (tester) async {
    final controller = await _loadedController(_snapshot());

    await _pumpHome(tester, controller);

    expect(find.text('Popular This Week'), findsOneWidget);
    expect(find.text('Top Artists'), findsOneWidget);
    expect(find.text('Recently Added'), findsOneWidget);
    expect(find.text('New Albums'), findsOneWidget);

    expect(
      find.byKey(const ValueKey<String>('home-popular-track-song_popular')),
      findsOneWidget,
    );

    expect(
      find.byKey(const ValueKey<String>('home-top-artist-artist_1')),
      findsOneWidget,
    );

    expect(
      find.byKey(const ValueKey<String>('home-recent-track-song_recent')),
      findsOneWidget,
    );

    expect(
      find.byKey(const ValueKey<String>('home-new-album-album_1')),
      findsOneWidget,
    );
  });

  testWidgets(
    'popular track tap opens context instead of immediately playing',
    (tester) async {
      final controller = await _loadedController(_snapshot());

      await _pumpHome(tester, controller);

      await tester.tap(
        find.byKey(const ValueKey<String>('home-popular-track-song_popular')),
      );

      await tester.pumpAndSettle();

      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Play next'), findsOneWidget);
      expect(find.text('Add to queue'), findsOneWidget);
      expect(find.text('Add to playlist'), findsOneWidget);
      expect(find.text('Go to album'), findsOneWidget);
      expect(find.text('Go to artist'), findsOneWidget);
    },
  );

  testWidgets('blocked recently added track remains visible and disabled', (
    tester,
  ) async {
    final controller = await _loadedController(
      _snapshot(
        recentTrack: _track(
          id: 'song_blocked',
          title: 'Blocked Song',
          blocked: true,
        ),
      ),
    );

    await _pumpHome(tester, controller);

    final blockedTrack = find.byKey(
      const ValueKey<String>('home-recent-track-song_blocked'),
    );

    expect(blockedTrack, findsOneWidget);
    expect(find.byIcon(Icons.block_rounded), findsOneWidget);

    await tester.tap(blockedTrack);
    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsNothing);
    expect(find.text('Add to queue'), findsNothing);
  });

  testWidgets('renders empty state', (tester) async {
    final controller = await _loadedController(
      const HomeSnapshot(
        recentlyAddedTracks: [],
        recentlyAddedAlbums: [],
        weeklyPopularTracks: [],
        weeklyTopArtists: [],
      ),
    );

    await _pumpHome(tester, controller);

    expect(find.text('Your Home is empty'), findsOneWidget);
  });

  testWidgets('Top Artists artwork prefers dedicated artwork', (tester) async {
    final controller = await _loadedController(
      _snapshot(
        artist: _artist(
          topArtistsArtworkPath: 'C:/Music/top-artists.jpg',
          headerArtworkPath: 'C:/Music/header.jpg',
        ),
      ),
    );

    await _pumpHome(tester, controller);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('home-top-artist-artwork-artist_1')),
    );

    final provider = image.image as FileImage;

    expect(
      provider.file.path.replaceAll('\\', '/'),
      contains('top-artists.jpg'),
    );
  });

  testWidgets('Top Artists artwork falls back to header artwork', (
    tester,
  ) async {
    final controller = await _loadedController(
      _snapshot(artist: _artist(headerArtworkPath: 'C:/Music/header-only.jpg')),
    );

    await _pumpHome(tester, controller);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('home-top-artist-artwork-artist_1')),
    );

    final provider = image.image as FileImage;

    expect(
      provider.file.path.replaceAll('\\', '/'),
      contains('header-only.jpg'),
    );
  });

  testWidgets('New Albums card uses album artwork path', (tester) async {
    final controller = await _loadedController(
      _snapshot(album: _album(artworkPath: 'C:/Music/album-cover.jpg')),
    );

    await _pumpHome(tester, controller);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey<String>('home-new-album-artwork-album_1')),
    );

    final provider = image.image as FileImage;

    expect(
      provider.file.path.replaceAll('\\', '/'),
      contains('album-cover.jpg'),
    );
  });
  testWidgets('shows loading state during initial load', (tester) async {
    final completer = Completer<HomeSnapshot>();

    final service = _FakeHomeDataService(pendingResult: completer.future);

    final controller = HomeController(
      service: service,
      now: () => DateTime(2026, 9, 28, 12),
    );

    final load = controller.load();

    await _pumpHome(tester, controller, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(
      const HomeSnapshot(
        recentlyAddedTracks: [],
        recentlyAddedAlbums: [],
        weeklyPopularTracks: [],
        weeklyTopArtists: [],
      ),
    );

    await load;
    await tester.pumpAndSettle();
  });

  testWidgets('shows initial error state and retries successfully', (
    tester,
  ) async {
    final service = _FakeHomeDataService(error: StateError('Home failed'));

    final controller = HomeController(
      service: service,
      now: () => DateTime(2026, 9, 28, 12),
    );

    await controller.load();
    await _pumpHome(tester, controller);

    expect(find.text('Home could not be loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    service.error = null;
    service.snapshot = _snapshot();

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Popular This Week'), findsOneWidget);
    expect(find.text('Home could not be loaded.'), findsNothing);
  });

  testWidgets('refresh failure preserves existing content and shows banner', (
    tester,
  ) async {
    final service = _FakeHomeDataService(snapshot: _snapshot());

    final controller = HomeController(
      service: service,
      now: () => DateTime(2026, 9, 28, 12),
    );

    await controller.load();

    service.error = StateError('Refresh failed');

    await controller.refresh();
    await _pumpHome(tester, controller);

    expect(find.text('Popular This Week'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('home-popular-track-song_popular')),
      findsOneWidget,
    );

    expect(find.text('Home could not refresh.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

Future<HomeController> _loadedController(HomeSnapshot snapshot) async {
  final controller = HomeController(
    service: _FakeHomeDataService(snapshot: snapshot),
    now: () => DateTime(2026, 9, 28, 12),
  );

  await controller.load();

  return controller;
}

Future<void> _pumpHome(
  WidgetTester tester,
  HomeController controller, {
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));

  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ChangeNotifierProvider<HomeController?>.value(
      value: controller,
      child: const MaterialApp(home: Scaffold(body: HomePage())),
    ),
  );

  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

HomeSnapshot _snapshot({
  LibraryTrack? recentTrack,
  LibraryArtist? artist,
  LibraryAlbum? album,
}) {
  final popularTrack = _track(id: 'song_popular', title: 'Popular Song');

  final resolvedRecentTrack =
      recentTrack ?? _track(id: 'song_recent', title: 'Recent Song');

  final resolvedArtist = artist ?? _artist();
  final resolvedAlbum = album ?? _album();

  return HomeSnapshot(
    recentlyAddedTracks: [resolvedRecentTrack],
    recentlyAddedAlbums: [resolvedAlbum],
    weeklyPopularTracks: [
      HomePopularTrack(track: popularTrack, rank: 1, qualifiedStreamCount: 12),
    ],
    weeklyTopArtists: [
      HomeTopArtist(
        artist: resolvedArtist,
        rank: 1,
        qualifiedStreamCount: 12,
        weeklyListeningDuration: const Duration(hours: 2, minutes: 15),
      ),
    ],
  );
}

LibraryTrack _track({
  required String id,
  required String title,
  bool blocked = false,
}) {
  return LibraryTrack(
    songId: id,
    title: title,
    artistId: 'artist_1',
    artistName: 'Artist 1',
    albumId: 'album_1',
    albumTitle: 'Album 1',
    albumEditionId: 'edition_1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 9, 28),
    isAvailable: true,
    isSongBlocked: blocked,
    filePath: 'C:/Music/$id.mp3',
  );
}

LibraryArtist _artist({
  String? topArtistsArtworkPath,
  String? headerArtworkPath,
}) {
  return LibraryArtist(
    artistId: 'artist_1',
    name: 'Artist 1',
    albumCount: 1,
    songCount: 2,
    dateAdded: DateTime.utc(2026, 9, 28),
    topArtistsArtworkPath: topArtistsArtworkPath,
    headerArtworkPath: headerArtworkPath,
  );
}

LibraryAlbum _album({String? artworkPath}) {
  return LibraryAlbum(
    albumId: 'album_1',
    title: 'Album 1',
    artistId: 'artist_1',
    artistName: 'Artist 1',
    trackCount: 2,
    dateAdded: DateTime.utc(2026, 9, 28),
    artworkPath: artworkPath,
  );
}

class _FakeHomeDataService implements HomeDataService {
  _FakeHomeDataService({HomeSnapshot? snapshot, this.error, this.pendingResult})
    : snapshot =
          snapshot ??
          const HomeSnapshot(
            recentlyAddedTracks: [],
            recentlyAddedAlbums: [],
            weeklyPopularTracks: [],
            weeklyTopArtists: [],
          );

  HomeSnapshot snapshot;
  Object? error;
  Future<HomeSnapshot>? pendingResult;

  int callCount = 0;

  @override
  int get sectionLimit => 6;

  @override
  Future<HomeSnapshot> load({required DateTime referenceLocal}) async {
    callCount++;

    final pendingResult = this.pendingResult;

    if (pendingResult != null) {
      return pendingResult;
    }

    final error = this.error;

    if (error != null) {
      throw error;
    }

    return snapshot;
  }
}
