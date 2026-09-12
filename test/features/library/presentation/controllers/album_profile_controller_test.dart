import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/controllers/album_profile_controller.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

void main() {
  group('AlbumProfileController', () {
    test('loads album and tracks', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1', title: 'First Song'),
          createTrack(songId: 'song-2', title: 'Second Song'),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.album?.albumId, 'album-1');
      expect(controller.album?.title, 'Test Album');

      expect(controller.tracks, hasLength(2));

      expect(repository.requestedAlbumId, 'album-1');
      expect(repository.requestedTracksAlbumId, 'album-1');

      expect(controller.isLoading, isFalse);
      expect(controller.hasError, isFalse);
      expect(controller.isNotFound, isFalse);

      controller.dispose();
    });

    test('derives total album runtime from tracks', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1', durationSeconds: 185),
          createTrack(songId: 'song-2', durationSeconds: 240),
          createTrack(songId: 'song-3', durationSeconds: 95),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.totalDurationSeconds, 520);
      expect(controller.totalDuration, const Duration(minutes: 8, seconds: 40));

      controller.dispose();
    });

    test('negative track durations do not reduce album runtime', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1', durationSeconds: 180),
          createTrack(songId: 'song-2', durationSeconds: -40),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.totalDurationSeconds, 180);

      controller.dispose();
    });

    test('derives playable and unavailable track counts', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1'),
          createTrack(songId: 'song-2'),
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.playableTrackCount, 2);
      expect(controller.unavailableTrackCount, 1);
      expect(controller.hasUnavailableTracks, isTrue);

      controller.dispose();
    });

    test(
      'reports no unavailable tracks when every track is playable',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [
            createTrack(songId: 'song-1'),
            createTrack(songId: 'song-2'),
          ],
        );

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
        );

        await controller.load();

        expect(controller.playableTrackCount, 2);
        expect(controller.unavailableTrackCount, 0);
        expect(controller.hasUnavailableTracks, isFalse);

        controller.dispose();
      },
    );

    test('derives distinct album editions in track order', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(
            songId: 'song-1',
            albumEditionId: 'edition-standard',
            albumEditionTitle: 'Standard',
            albumEditionType: AlbumEditionType.standard,
          ),
          createTrack(
            songId: 'song-2',
            albumEditionId: 'edition-standard',
            albumEditionTitle: 'Standard',
            albumEditionType: AlbumEditionType.standard,
          ),
          createTrack(
            songId: 'song-3',
            albumEditionId: 'edition-deluxe',
            albumEditionTitle: 'Deluxe',
            albumEditionType: AlbumEditionType.deluxe,
          ),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.editionCount, 2);
      expect(controller.hasMultipleEditions, isTrue);
      expect(controller.editionTitles, ['Standard', 'Deluxe']);

      controller.dispose();
    });

    test('single edition album is not reported as multi-edition', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1'),
          createTrack(songId: 'song-2'),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.editionCount, 1);
      expect(controller.hasMultipleEditions, isFalse);
      expect(controller.editionTitles, ['Standard']);

      controller.dispose();
    });

    test('reports not found when album does not exist', () async {
      final repository = FakeLibraryQueryRepository();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'missing-album',
      );

      await controller.load();

      expect(controller.album, isNull);
      expect(controller.tracks, isEmpty);
      expect(controller.isNotFound, isTrue);
      expect(controller.hasError, isFalse);

      controller.dispose();
    });

    test('captures loading errors', () async {
      final repository = FakeLibraryQueryRepository(
        albumError: StateError('failed'),
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.album, isNull);
      expect(controller.tracks, isEmpty);
      expect(controller.hasError, isTrue);
      expect(controller.error, isA<StateError>());
      expect(controller.isLoading, isFalse);

      controller.dispose();
    });

    test('refresh reloads album and tracks', () async {
      var requestCount = 0;

      final repository = FakeLibraryQueryRepository(
        albumLoader: (albumId) async {
          requestCount++;

          return createAlbum(
            title: requestCount == 1 ? 'First Title' : 'Updated Title',
          );
        },
        tracks: [createTrack()],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.album?.title, 'First Title');

      await controller.refresh();

      expect(controller.album?.title, 'Updated Title');
      expect(requestCount, 2);

      controller.dispose();
    });

    test('playTrack starts playback for playable track', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack()],
      );

      final engine = FakePlaybackEngine();
      final coordinator = PlaybackCoordinator(engine: engine);

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: coordinator,
      );

      await controller.load();

      await controller.playTrack(controller.tracks.single);

      expect(engine.loadQueueCallCount, 1);
      expect(engine.lastLoadedTracks, hasLength(1));
      expect(engine.lastLoadedTracks!.single.songId, 'song-1');
      expect(engine.lastStartIndex, 0);
      expect(engine.lastAutoPlay, isTrue);

      controller.dispose();
      await engine.dispose();
    });

    test('playTrack ignores unavailable track', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
        ],
      );

      final engine = FakePlaybackEngine();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await controller.load();

      await controller.playTrack(controller.tracks.single);

      expect(engine.loadQueueCallCount, 0);

      controller.dispose();
      await engine.dispose();
    });

    test(
      'playAll starts from first playable track when shuffle is off',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [
            createTrack(
              songId: 'missing-song',
              filePath: '',
              isAvailable: false,
            ),
            createTrack(songId: 'song-2'),
            createTrack(songId: 'song-3'),
          ],
        );

        final engine = FakePlaybackEngine();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        );

        await controller.load();

        await controller.playAll();

        expect(engine.loadQueueCallCount, 1);

        expect(engine.lastLoadedTracks!.map((track) => track.songId), [
          'song-2',
          'song-3',
        ]);

        expect(engine.lastStartIndex, 0);
        expect(engine.lastAutoPlay, isTrue);

        controller.dispose();
        await engine.dispose();
      },
    );

    test('playAll starts from shuffled playable track', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'song-1'),
          createTrack(songId: 'song-2'),
          createTrack(songId: 'song-3'),
        ],
      );

      final engine = FakePlaybackEngine();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
        random: const FixedRandom(2),
      );

      await controller.load();

      await controller.setShuffleEnabled(true);

      await controller.playAll();

      expect(controller.isShuffleEnabled, isTrue);

      expect(engine.loadQueueCallCount, 1);

      expect(engine.lastLoadedTracks!.map((track) => track.songId), [
        'song-1',
        'song-2',
        'song-3',
      ]);

      expect(engine.lastStartIndex, 2);
      expect(engine.lastAutoPlay, isTrue);

      controller.dispose();
      await engine.dispose();
    });

    test(
      'setShuffleEnabled updates playback engine and controller state',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [createTrack()],
        );

        final engine = FakePlaybackEngine();

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
          playbackCoordinator: PlaybackCoordinator(engine: engine),
        );

        await controller.load();

        await controller.setShuffleEnabled(true);

        expect(controller.isShuffleEnabled, isTrue);
        expect(engine.lastShuffleEnabled, isTrue);

        await controller.setShuffleEnabled(false);

        expect(controller.isShuffleEnabled, isFalse);
        expect(engine.lastShuffleEnabled, isFalse);

        controller.dispose();
        await engine.dispose();
      },
    );

    test('toggleShuffle flips shuffle state', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack()],
      );

      final engine = FakePlaybackEngine();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await controller.load();

      await controller.toggleShuffle();

      expect(controller.isShuffleEnabled, isTrue);

      await controller.toggleShuffle();

      expect(controller.isShuffleEnabled, isFalse);

      controller.dispose();
      await engine.dispose();
    });

    test('playNext inserts playable track after current track', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack(songId: 'song-2')],
      );

      final engine = FakePlaybackEngine();

      final coordinator = PlaybackCoordinator(engine: engine);

      await coordinator.playTrack(
        createTrack(songId: 'current-song', title: 'Current Song'),
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: coordinator,
      );

      await controller.load();

      await controller.playNext(controller.tracks.single);

      expect(engine.lastInsertedTrack?.songId, 'song-2');
      expect(engine.lastInsertedIndex, 1);

      controller.dispose();
      await engine.dispose();
    });

    test('addToQueue appends playable track', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [createTrack(songId: 'song-2')],
      );

      final engine = FakePlaybackEngine();

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await controller.load();

      await controller.addToQueue(controller.tracks.single);

      expect(engine.lastAppendedTrack?.songId, 'song-2');

      controller.dispose();
      await engine.dispose();
    });

    test('reports whether tracks are playable', () async {
      final repository = FakeLibraryQueryRepository(
        album: createAlbum(),
        tracks: [
          createTrack(songId: 'playable-song'),
          createTrack(songId: 'missing-song', filePath: '', isAvailable: false),
        ],
      );

      final controller = AlbumProfileController(
        repository: repository,
        albumId: 'album-1',
      );

      await controller.load();

      expect(controller.hasPlayableTracks, isTrue);

      expect(controller.isTrackPlayable(controller.tracks.first), isTrue);

      expect(controller.isTrackPlayable(controller.tracks.last), isFalse);

      controller.dispose();
    });

    test(
      'hasPlayableTracks is false when every track is unavailable',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [
            createTrack(songId: 'missing-1', filePath: '', isAvailable: false),
            createTrack(songId: 'missing-2', filePath: '', isAvailable: false),
          ],
        );

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
        );

        await controller.load();

        expect(controller.hasPlayableTracks, isFalse);

        controller.dispose();
      },
    );

    test(
      'playback actions do nothing when playback coordinator is absent',
      () async {
        final repository = FakeLibraryQueryRepository(
          album: createAlbum(),
          tracks: [createTrack()],
        );

        final controller = AlbumProfileController(
          repository: repository,
          albumId: 'album-1',
        );

        await controller.load();

        await controller.playTrack(controller.tracks.single);
        await controller.playAll();
        await controller.playNext(controller.tracks.single);
        await controller.addToQueue(controller.tracks.single);
        await controller.toggleShuffle();

        expect(controller.isShuffleEnabled, isFalse);

        controller.dispose();
      },
    );
  });
}

LibraryAlbum createAlbum({
  String albumId = 'album-1',
  String title = 'Test Album',
  String artistId = 'artist-1',
}) {
  return LibraryAlbum(
    albumId: albumId,
    title: title,
    artistId: artistId,
    artistName: 'Test Artist',
    trackCount: 3,
    dateAdded: DateTime(2026, 1, 1),
  );
}

LibraryTrack createTrack({
  String songId = 'song-1',
  String title = 'Test Song',
  String artistId = 'artist-1',
  String albumId = 'album-1',
  String albumEditionId = 'edition-1',
  String albumEditionTitle = 'Standard',
  AlbumEditionType albumEditionType = AlbumEditionType.standard,
  int trackNumber = 1,
  int durationSeconds = 180,
  String? filePath,
  bool isAvailable = true,
}) {
  return LibraryTrack(
    songId: songId,
    title: title,
    artistId: artistId,
    artistName: 'Test Artist',
    albumId: albumId,
    albumTitle: 'Test Album',
    albumEditionId: albumEditionId,
    albumEditionTitle: albumEditionTitle,
    albumEditionType: albumEditionType,
    trackNumber: trackNumber,
    durationSeconds: durationSeconds,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime(2026, 1, 1),
    filePath: filePath ?? 'C:/Music/$songId.mp3',
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

  String? requestedAlbumId;
  String? requestedTracksAlbumId;

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async {
    requestedAlbumId = albumId;

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
    requestedTracksAlbumId = albumId;

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
