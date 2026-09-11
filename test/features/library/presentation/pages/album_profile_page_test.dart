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
import 'package:sonus_next/features/library/presentation/pages/album_profile_page.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

void main() {
  group('AlbumProfilePage', () {
    testWidgets('shows stable page while repository is unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(buildSubject(repository: null));

      expect(
        find.byKey(const ValueKey<String>('album-profile-page')),
        findsOneWidget,
      );

      expect(find.text('Loading album...'), findsOneWidget);
    });

    testWidgets('shows loading state while album is loading', (tester) async {
      final completer = Completer<LibraryAlbum?>();

      final repository = FakeLibraryQueryRepository(
        albumLoader: (_) => completer.future,
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(null);

      await tester.pump();
      await tester.pump();
    });

    testWidgets('shows album profile content', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(
          genre: 'Pop',
          releaseDate: DateTime(2026, 4, 12),
          primaryEditionTitle: 'Standard',
        ),
        tracks: [
          createTrack(
            songId: 'song-1',
            title: 'First Song',
            trackNumber: 1,
            durationSeconds: 180,
          ),
          createTrack(
            songId: 'song-2',
            title: 'Second Song',
            trackNumber: 2,
            durationSeconds: 245,
          ),
        ],
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Test Album'), findsWidgets);

      expect(find.text('Test Artist'), findsOneWidget);

      expect(find.text('2 tracks'), findsOneWidget);

      expect(find.text('Pop • 2026 • Standard'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('album-profile-tracks-list')),
        findsOneWidget,
      );

      expect(find.text('First Song'), findsOneWidget);

      expect(find.text('Second Song'), findsOneWidget);

      expect(find.text('3:00'), findsOneWidget);

      expect(find.text('4:05'), findsOneWidget);
    });

    testWidgets('shows empty track state', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(trackCount: 0),
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('No tracks yet'), findsOneWidget);
    });

    testWidgets('shows album not found state', (tester) async {
      final repository = FakeLibraryQueryRepository();

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Album not found'), findsOneWidget);
    });

    testWidgets('shows error state when loading fails', (tester) async {
      final repository = FakeLibraryQueryRepository(
        albumError: StateError('failed'),
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Could not load this album.'), findsOneWidget);

      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('retry reloads profile after failure', (tester) async {
      var shouldFail = true;

      final repository = FakeLibraryQueryRepository(
        albumLoader: (_) async {
          if (shouldFail) {
            throw StateError('failed');
          }

          return createAlbum(title: 'Recovered Album');
        },
      );

      await tester.pumpWidget(buildSubject(repository: repository));

      await tester.pumpAndSettle();

      expect(find.text('Could not load this album.'), findsOneWidget);

      shouldFail = false;

      await tester.tap(find.text('Try again'));

      await tester.pumpAndSettle();

      expect(find.text('Recovered Album'), findsWidgets);
    });

    testWidgets('play button plays album tracks', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1', title: 'First Song'),
          createTrack(songId: 'song-2', title: 'Second Song'),
        ],
      );

      final engine = FakePlaybackEngine();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.pumpAndSettle();

      final playButton = find.byKey(
        const ValueKey<String>('album-profile-play-all-button'),
      );

      expect(playButton, findsOneWidget);

      await tester.tap(playButton);

      await tester.pump();

      expect(engine.loadQueueCallCount, 1);

      expect(engine.lastLoadedTracks!.map((track) => track.songId), [
        'song-1',
        'song-2',
      ]);

      expect(engine.lastStartIndex, 0);

      expect(engine.lastAutoPlay, isTrue);

      await engine.dispose();
    });

    testWidgets('shuffle button updates playback shuffle state', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack()],
      );

      final engine = FakePlaybackEngine();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.pumpAndSettle();

      final shuffleButton = find.byKey(
        const ValueKey<String>('album-profile-shuffle-button'),
      );

      expect(shuffleButton, findsOneWidget);

      await tester.tap(shuffleButton);

      await tester.pump();

      expect(engine.lastShuffleEnabled, isTrue);

      await tester.tap(shuffleButton);

      await tester.pump();

      expect(engine.lastShuffleEnabled, isFalse);

      await engine.dispose();
    });

    testWidgets('tapping playable track starts playback', (tester) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack(songId: 'play-song', title: 'Play Song')],
      );

      final engine = FakePlaybackEngine();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.pumpAndSettle();

      final trackFinder = find.byKey(
        const ValueKey<String>('album-track-play-song'),
      );

      expect(trackFinder, findsOneWidget);

      await tester.tap(trackFinder);

      await tester.pump();

      expect(engine.loadQueueCallCount, 1);

      expect(engine.lastLoadedTracks, hasLength(1));

      expect(engine.lastLoadedTracks!.single.songId, 'play-song');

      expect(engine.lastAutoPlay, isTrue);

      await engine.dispose();
    });

    testWidgets('unavailable track is disabled and does not start playback', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(
            songId: 'missing-song',
            title: 'Missing Song',
            filePath: '',
            isAvailable: false,
          ),
        ],
      );

      final engine = FakePlaybackEngine();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.pumpAndSettle();

      final tileFinder = find.byKey(
        const ValueKey<String>('album-track-missing-song'),
      );

      expect(tileFinder, findsOneWidget);

      final tile = tester.widget<ListTile>(tileFinder);

      expect(tile.enabled, isFalse);

      expect(tile.onTap, isNull);

      expect(engine.loadQueueCallCount, 0);

      await engine.dispose();
    });

    testWidgets('playback controls are disabled when no tracks are playable', (
      tester,
    ) async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
        ],
      );

      final engine = FakePlaybackEngine();

      await tester.pumpWidget(
        buildSubject(
          repository: repository,
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        ),
      );

      await tester.pumpAndSettle();

      final playButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('album-profile-play-all-button')),
      );

      expect(playButton.onPressed, isNull);

      final shuffleButton = tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('album-profile-shuffle-button')),
      );

      expect(shuffleButton.onPressed, isNull);

      await engine.dispose();
    });
  });
}

Widget buildSubject({
  required LibraryQueryRepository? repository,
  PlaybackCoordinator? playbackCoordinator,
}) {
  return Provider<LibraryQueryRepository?>.value(
    value: repository,
    child: Provider<PlaybackCoordinator?>.value(
      value: playbackCoordinator,
      child: const MaterialApp(
        home: AlbumProfilePage(
          albumId: 'album-1',
          initialAlbumTitle: 'Test Album',
        ),
      ),
    ),
  );
}

LibraryAlbum createAlbum({
  String albumId = 'album-1',
  String title = 'Test Album',
  String artistId = 'artist-1',
  String artistName = 'Test Artist',
  int trackCount = 2,
  DateTime? releaseDate,
  String? genre,
  String? primaryEditionTitle,
}) {
  return LibraryAlbum(
    albumId: albumId,
    title: title,
    artistId: artistId,
    artistName: artistName,
    primaryEditionId: 'edition-1',
    primaryEditionTitle: primaryEditionTitle,
    primaryEditionType: AlbumEditionType.values.first,
    releaseDate: releaseDate,
    genre: genre,
    trackCount: trackCount,
    dateAdded: DateTime(2026, 1, 1),
  );
}

LibraryTrack createTrack({
  String songId = 'song-1',
  String title = 'Test Song',
  String artistId = 'artist-1',
  String artistName = 'Test Artist',
  String albumId = 'album-1',
  String albumTitle = 'Test Album',
  String albumEditionTitle = 'Standard',
  int trackNumber = 1,
  int durationSeconds = 180,
  List<String> featuredArtists = const [],
  String? filePath,
  bool isAvailable = true,
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: artistId,
    artistName: artistName,
    albumId: albumId,
    albumTitle: albumTitle,
    albumEditionId: 'edition-1',
    albumEditionTitle: albumEditionTitle,
    albumEditionType: AlbumEditionType.values.first,
    trackNumber: trackNumber,
    durationSeconds: durationSeconds,
    isSingle: false,
    featuredArtists: featuredArtists,
    dateAdded: DateTime(2026, 1, 1),
    filePath: filePath ?? '/music/$songId.mp3',
    isAvailable: isAvailable,
  );
}

class FakeLibraryQueryRepository implements LibraryQueryRepository {
  FakeLibraryQueryRepository({
    this.album,
    this.tracks = const [],
    this.albumError,
    this.albumLoader,
  });

  final LibraryAlbum? album;
  final List<LibraryTrack> tracks;
  final Object? albumError;

  final Future<LibraryAlbum?> Function(String albumId)? albumLoader;

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    final loader = albumLoader;

    if (loader != null) {
      return loader(albumId);
    }

    final error = albumError;

    if (error != null) {
      throw error;
    }

    return album;
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
    return tracks;
  }

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return const [];
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
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    return const [];
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() async {
    return const [];
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async {
    return const [];
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    return const [];
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return const [];
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    return null;
  }
}

class FakePlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _statesController =
      StreamController<PlaybackState>.broadcast();

  PlaybackState _currentState = const PlaybackState();

  List<PlaybackTrack>? lastLoadedTracks;
  int? lastStartIndex;
  bool? lastAutoPlay;
  bool? lastShuffleEnabled;

  int loadQueueCallCount = 0;

  @override
  Stream<PlaybackState> get states {
    return _statesController.stream;
  }

  @override
  PlaybackState get currentState {
    return _currentState;
  }

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {
    loadQueueCallCount++;

    lastLoadedTracks = List<PlaybackTrack>.from(tracks);

    lastStartIndex = startIndex;
    lastAutoPlay = autoPlay;
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    lastShuffleEnabled = enabled;

    _currentState = _currentState.copyWith(shuffleEnabled: enabled);
  }

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {}

  @override
  Future<void> appendTrack(PlaybackTrack track) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> removeTrackAt(int index) async {}

  @override
  Future<void> moveTrack({
    required int oldIndex,
    required int newIndex,
  }) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _statesController.close();
  }
}
