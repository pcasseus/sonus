import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/controllers/artist_profile_controller.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

void main() {
  group('ArtistProfileController', () {
    test('loads artist, albums, and tracks', () async {
      final artist = createArtist();
      final album = createAlbum();
      final track = createTrack();

      final repository = FakeLibraryQueryRepository(
        artist: artist,
        albums: [album],
        tracks: [track],
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: artist.artistId,
      );

      await controller.load();

      expect(controller.artist, same(artist));
      expect(controller.albums, [album]);
      expect(controller.tracks, [track]);
      expect(controller.isLoading, isFalse);
      expect(controller.hasError, isFalse);
      expect(controller.isNotFound, isFalse);

      expect(repository.requestedArtistId, artist.artistId);
      expect(repository.requestedAlbumsArtistId, artist.artistId);
      expect(repository.requestedTracksArtistId, artist.artistId);

      controller.dispose();
    });

    test('reports artist not found without loading albums or tracks', () async {
      final repository = FakeLibraryQueryRepository(artist: null);

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'missing-artist',
      );

      await controller.load();

      expect(controller.artist, isNull);
      expect(controller.albums, isEmpty);
      expect(controller.tracks, isEmpty);
      expect(controller.isNotFound, isTrue);
      expect(controller.hasError, isFalse);

      expect(repository.requestedArtistId, 'missing-artist');
      expect(repository.requestedAlbumsArtistId, isNull);
      expect(repository.requestedTracksArtistId, isNull);

      controller.dispose();
    });

    test('captures repository failure', () async {
      final repository = FakeLibraryQueryRepository(
        artistError: StateError('artist failed'),
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      await controller.load();

      expect(controller.artist, isNull);
      expect(controller.hasError, isTrue);
      expect(controller.error, isA<StateError>());
      expect(controller.isLoading, isFalse);
      expect(controller.isNotFound, isFalse);

      controller.dispose();
    });

    test('refresh reloads profile data', () async {
      var artistName = 'Original Artist';

      final repository = FakeLibraryQueryRepository(
        artistLoader: (_) async {
          return createArtist(name: artistName);
        },
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      await controller.load();

      expect(controller.artist?.name, 'Original Artist');

      artistName = 'Updated Artist';

      await controller.refresh();

      expect(controller.artist?.name, 'Updated Artist');

      expect(repository.artistRequestCount, 2);

      controller.dispose();
    });

    test('reports whether artist has playable tracks', () async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
          createTrack(songId: 'playable-song'),
        ],
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      await controller.load();

      expect(controller.hasPlayableTracks, isTrue);

      expect(controller.isTrackPlayable(controller.tracks.first), isFalse);

      expect(controller.isTrackPlayable(controller.tracks.last), isTrue);

      controller.dispose();
    });

    test('playTrack loads the selected playable track', () async {
      final repository = FakeLibraryQueryRepository();

      final engine = FakePlaybackEngine();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      final selectedTrack = createTrack(songId: 'song-play', title: 'Play Me');

      await controller.playTrack(selectedTrack);

      expect(engine.loadQueueCallCount, 1);

      expect(engine.lastLoadedTracks, hasLength(1));

      expect(engine.lastLoadedTracks!.single.songId, 'song-play');

      expect(engine.lastStartIndex, 0);

      expect(engine.lastAutoPlay, isTrue);

      await engine.dispose();
      controller.dispose();
    });

    test('playTrack ignores unavailable tracks', () async {
      final repository = FakeLibraryQueryRepository();

      final engine = FakePlaybackEngine();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      final unavailableTrack = createTrack(
        songId: 'missing-song',
        filePath: '',
        isAvailable: false,
      );

      await controller.playTrack(unavailableTrack);

      expect(engine.loadQueueCallCount, 0);

      await engine.dispose();
      controller.dispose();
    });

    test(
      'playAll starts from first playable track when shuffle is off',
      () async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          tracks: [
            createTrack(
              songId: 'missing-song',
              filePath: '',
              isAvailable: false,
            ),
            createTrack(songId: 'playable-1'),
            createTrack(songId: 'playable-2'),
          ],
        );

        final engine = FakePlaybackEngine();

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        );

        await controller.load();
        await controller.playAll();

        expect(engine.loadQueueCallCount, 1);

        expect(engine.lastLoadedTracks!.map((track) => track.songId), [
          'playable-1',
          'playable-2',
        ]);

        expect(engine.lastStartIndex, 0);

        expect(engine.lastAutoPlay, isTrue);

        await engine.dispose();
        controller.dispose();
      },
    );

    test(
      'playAll chooses among playable tracks when shuffle is enabled',
      () async {
        final repository = FakeLibraryQueryRepository(
          artist: createArtist(),
          tracks: [
            createTrack(songId: 'playable-1'),
            createTrack(
              songId: 'missing-song',
              filePath: '',
              isAvailable: false,
            ),
            createTrack(songId: 'playable-2'),
          ],
        );

        final engine = FakePlaybackEngine();

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          playbackCoordinator: PlaybackCoordinator(engine: engine),
          random: const FixedRandom(1),
        );

        await controller.load();
        await controller.setShuffleEnabled(true);
        await controller.playAll();

        expect(controller.isShuffleEnabled, isTrue);

        expect(engine.lastShuffleEnabled, isTrue);

        expect(engine.lastLoadedTracks!.map((track) => track.songId), [
          'playable-1',
          'playable-2',
        ]);

        expect(engine.lastStartIndex, 1);

        await engine.dispose();
        controller.dispose();
      },
    );

    test('playAll does nothing when no artist tracks are playable', () async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [
          createTrack(songId: 'missing-1', filePath: '', isAvailable: false),
          createTrack(songId: 'missing-2', filePath: '', isAvailable: false),
        ],
      );

      final engine = FakePlaybackEngine();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await controller.load();
      await controller.playAll();

      expect(controller.hasPlayableTracks, isFalse);

      expect(engine.loadQueueCallCount, 0);

      expect(engine.stopCallCount, 0);

      await engine.dispose();
      controller.dispose();
    });

    test(
      'toggleShuffle updates playback engine and controller state',
      () async {
        final repository = FakeLibraryQueryRepository();

        final engine = FakePlaybackEngine();

        final controller = ArtistProfileController(
          repository: repository,
          artistId: 'artist-1',
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        );

        expect(controller.isShuffleEnabled, isFalse);

        await controller.toggleShuffle();

        expect(controller.isShuffleEnabled, isTrue);

        expect(engine.lastShuffleEnabled, isTrue);

        await controller.toggleShuffle();

        expect(controller.isShuffleEnabled, isFalse);

        expect(engine.lastShuffleEnabled, isFalse);

        await engine.dispose();
        controller.dispose();
      },
    );

    test('addToQueue appends a playable track', () async {
      final repository = FakeLibraryQueryRepository();

      final engine = FakePlaybackEngine();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      final selectedTrack = createTrack(
        songId: 'queue-song',
        title: 'Queue Me',
      );

      await controller.addToQueue(selectedTrack);

      expect(engine.lastAppendedTrack, isNotNull);

      expect(engine.lastAppendedTrack!.songId, 'queue-song');

      await engine.dispose();
      controller.dispose();
    });

    test('playNext inserts a playable track after the current track', () async {
      final repository = FakeLibraryQueryRepository();

      final engine = FakePlaybackEngine();

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      final currentTrack = createTrack(
        songId: 'current-song',
        title: 'Current Song',
      );

      final nextTrack = createTrack(songId: 'next-song', title: 'Next Song');

      await controller.playTrack(currentTrack);

      await controller.playNext(nextTrack);

      expect(engine.lastInsertedTrack, isNotNull);

      expect(engine.lastInsertedTrack!.songId, 'next-song');

      expect(engine.lastInsertedIndex, 1);

      await engine.dispose();
      controller.dispose();
    });

    test('playback actions do nothing without playback coordinator', () async {
      final repository = FakeLibraryQueryRepository(
        artist: createArtist(),
        tracks: [createTrack(songId: 'song-1')],
      );

      final controller = ArtistProfileController(
        repository: repository,
        artistId: 'artist-1',
      );

      await controller.load();

      await controller.playTrack(controller.tracks.single);

      await controller.playAll();

      await controller.playNext(controller.tracks.single);

      await controller.addToQueue(controller.tracks.single);

      await controller.toggleShuffle();

      expect(controller.isShuffleEnabled, isFalse);

      controller.dispose();
    });
  });
}

LibraryArtist createArtist({
  String artistId = 'artist-1',
  String name = 'Test Artist',
}) {
  return LibraryArtist(
    artistId: artistId,
    name: name,
    albumCount: 1,
    songCount: 1,
    dateAdded: DateTime(2026, 1, 1),
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
  String title = 'Test Song',
  String artistId = 'artist-1',
  String? filePath,
  bool isAvailable = true,
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: artistId,
    artistName: 'Test Artist',
    albumId: 'album-1',
    albumTitle: 'Test Album',
    albumEditionId: 'edition-1',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.values.first,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime(2026, 1, 1),
    filePath: filePath ?? 'C:/Music/$songId.mp3',
    isAvailable: isAvailable,
  );
}

class FakeLibraryQueryRepository implements LibraryQueryRepository {
  FakeLibraryQueryRepository({
    this.artist,
    this.albums = const [],
    this.tracks = const [],
    this.artistError,
    this.artistLoader,
  });

  final LibraryArtist? artist;
  final List<LibraryAlbum> albums;
  final List<LibraryTrack> tracks;
  final Object? artistError;

  final Future<LibraryArtist?> Function(String artistId)? artistLoader;

  String? requestedArtistId;
  String? requestedAlbumsArtistId;
  String? requestedTracksArtistId;

  int artistRequestCount = 0;

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async {
    requestedArtistId = artistId;
    artistRequestCount++;

    final loader = artistLoader;

    if (loader != null) {
      return loader(artistId);
    }

    final error = artistError;

    if (error != null) {
      throw error;
    }

    return artist;
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async {
    requestedAlbumsArtistId = artistId;

    return albums;
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    requestedTracksArtistId = artistId;

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
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async {
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
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    return null;
  }

  @override
  Future<List<LibraryArtist>> getArtists() async {
    return const [];
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

  PlaybackTrack? lastInsertedTrack;
  int? lastInsertedIndex;

  PlaybackTrack? lastAppendedTrack;

  int loadQueueCallCount = 0;
  int stopCallCount = 0;

  @override
  Stream<PlaybackState> get states => _statesController.stream;

  @override
  PlaybackState get currentState => _currentState;

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

    final queue = tracks.isEmpty
        ? const PlaybackQueue()
        : PlaybackQueue(
            tracks: List<PlaybackTrack>.unmodifiable(tracks),
            currentIndex: startIndex,
          );

    _currentState = PlaybackState(
      queue: queue,
      status: autoPlay ? PlaybackStatus.playing : PlaybackStatus.ready,
      shuffleEnabled: _currentState.shuffleEnabled,
    );
  }

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    lastShuffleEnabled = enabled;

    _currentState = _currentState.copyWith(shuffleEnabled: enabled);
  }

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {
    lastInsertedTrack = track;
    lastInsertedIndex = index;

    _currentState = _currentState.copyWith(
      queue: _currentState.queue.insertTrack(track, index: index),
    );
  }

  @override
  Future<void> appendTrack(PlaybackTrack track) async {
    lastAppendedTrack = track;

    _currentState = _currentState.copyWith(
      queue: _currentState.queue.appendTrack(track),
    );
  }

  @override
  Future<void> play() async {
    _currentState = _currentState.copyWith(status: PlaybackStatus.playing);
  }

  @override
  Future<void> pause() async {
    _currentState = _currentState.copyWith(status: PlaybackStatus.paused);
  }

  @override
  Future<void> seek(Duration position) async {
    _currentState = _currentState.copyWith(position: position);
  }

  @override
  Future<void> skipNext() async {
    if (!_currentState.queue.hasNext) {
      return;
    }

    _currentState = _currentState.copyWith(
      queue: _currentState.queue.moveNext(),
    );
  }

  @override
  Future<void> skipPrevious() async {
    if (!_currentState.queue.hasPrevious) {
      return;
    }

    _currentState = _currentState.copyWith(
      queue: _currentState.queue.movePrevious(),
    );
  }

  @override
  Future<void> skipToIndex(int index) async {
    _currentState = _currentState.copyWith(
      queue: _currentState.queue.moveTo(index),
    );
  }

  @override
  Future<void> removeTrackAt(int index) async {
    _currentState = _currentState.copyWith(
      queue: _currentState.queue.removeTrackAt(index),
    );
  }

  @override
  Future<void> moveTrack({required int oldIndex, required int newIndex}) async {
    _currentState = _currentState.copyWith(
      queue: _currentState.queue.moveTrack(
        oldIndex: oldIndex,
        newIndex: newIndex,
      ),
    );
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    _currentState = _currentState.copyWith(repeatMode: mode);
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    _currentState = const PlaybackState();
  }

  @override
  Future<void> dispose() async {
    await _statesController.close();
  }
}

class FixedRandom implements Random {
  const FixedRandom(this.value);

  final int value;

  @override
  int nextInt(int max) {
    if (max <= 0) {
      throw ArgumentError.value(max, 'max');
    }

    return value % max;
  }

  @override
  bool nextBool() {
    return value.isEven;
  }

  @override
  double nextDouble() {
    return 0.5;
  }
}
