import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/presentation/controllers/library_tracks_controller.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

class FakeLibraryQueryRepository implements LibraryQueryRepository {
  List<LibraryTrack> tracks = const [];
  Object? tracksError;

  LibraryTrackOrder? lastRequestedOrder;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    lastRequestedOrder = order;

    final error = tracksError;

    if (error != null) {
      throw error;
    }

    return tracks;
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) async =>
      const [];

  @override
  Future<LibraryTrack?> getTrackById(String songId) async => null;

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async =>
      const [];

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) async =>
      const [];

  @override
  Future<List<LibraryAlbum>> getAlbums() async => const [];

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) async =>
      const [];

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) async => null;

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) async =>
      const [];

  @override
  Future<List<LibraryArtist>> getArtists() async => const [];

  @override
  Future<LibraryArtist?> getArtistById(String artistId) async => null;
}

class FakePlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _statesController =
      StreamController<PlaybackState>.broadcast();

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
  PlaybackState get currentState => throw UnimplementedError();

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
  }

  @override
  Future<void> insertTrack(
    PlaybackTrack track, {
    required int index,
  }) async {
    lastInsertedTrack = track;
    lastInsertedIndex = index;
  }

  @override
  Future<void> appendTrack(PlaybackTrack track) async {
    lastAppendedTrack = track;
  }

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
  Future<void> stop() async {
    stopCallCount++;
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
  bool nextBool() => value.isEven;

  @override
  double nextDouble() => 0.5;
}

void main() {
  LibraryTrack track({
    required String id,
    String title = 'Song',
    String artistName = 'Artist',
    String? filePath,
    bool isAvailable = true,
  }) {
    return LibraryTrack(
      songId: id,
      title: title,
      artistId: 'artist-$id',
      artistName: artistName,
      albumId: 'album-$id',
      albumTitle: 'Album $id',
      albumEditionId: 'edition-$id',
      albumEditionTitle: 'Album $id',
      albumEditionType: AlbumEditionType.standard,
      trackNumber: 1,
      durationSeconds: 210,
      isSingle: false,
      featuredArtists: const [],
      dateAdded: DateTime.utc(2026, 9, 11),
      filePath: filePath ?? 'C:/Music/$id.mp3',
      isAvailable: isAvailable,
    );
  }

  test('loads tracks using the current order', () async {
    final repository = FakeLibraryQueryRepository()
      ..tracks = [
        track(
          id: 'song-1',
          title: 'First Song',
        ),
      ];

    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
    );

    await controller.load();

    expect(controller.isLoading, isFalse);
    expect(controller.hasError, isFalse);
    expect(controller.tracks, hasLength(1));
    expect(controller.tracks.single.title, 'First Song');
    expect(repository.lastRequestedOrder, LibraryTrackOrder.title);
  });

  test('changing order reloads tracks using the selected order', () async {
    final repository = FakeLibraryQueryRepository();

    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
    );

    await controller.setOrder(LibraryTrackOrder.artist);

    expect(controller.order, LibraryTrackOrder.artist);
    expect(repository.lastRequestedOrder, LibraryTrackOrder.artist);

    await controller.setOrder(LibraryTrackOrder.dateAdded);

    expect(controller.order, LibraryTrackOrder.dateAdded);
    expect(repository.lastRequestedOrder, LibraryTrackOrder.dateAdded);
  });

  test('captures repository failures', () async {
    final repository = FakeLibraryQueryRepository()
      ..tracksError = StateError('Query failed');

    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
    );

    await controller.load();

    expect(controller.isLoading, isFalse);
    expect(controller.hasError, isTrue);
    expect(controller.error, isA<StateError>());
  });

  test('reports an empty track library', () async {
    final repository = FakeLibraryQueryRepository();

    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
    );

    await controller.load();

    expect(controller.isEmpty, isTrue);
    expect(controller.tracks, isEmpty);
  });

  test('playTrack loads the selected playable track', () async {
    final repository = FakeLibraryQueryRepository();

    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
    );

    final selectedTrack = track(
      id: 'song-play',
      title: 'Play Me',
    );

    await controller.playTrack(selectedTrack);

    expect(engine.loadQueueCallCount, 1);
    expect(engine.lastLoadedTracks, hasLength(1));
    expect(engine.lastLoadedTracks!.single.songId, 'song-play');
    expect(engine.lastStartIndex, 0);
    expect(engine.lastAutoPlay, isTrue);
  });

  test('playAll starts from the first playable track when shuffle is off',
      () async {
    final unavailable = track(
      id: 'unavailable',
      filePath: '',
      isAvailable: false,
    );

    final firstPlayable = track(id: 'playable-1');
    final secondPlayable = track(id: 'playable-2');

    final repository = FakeLibraryQueryRepository()
      ..tracks = [
        unavailable,
        firstPlayable,
        secondPlayable,
      ];

    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
    );

    await controller.load();
    await controller.playAll();

    expect(engine.loadQueueCallCount, 1);

    expect(
      engine.lastLoadedTracks!.map((track) => track.songId),
      [
        'playable-1',
        'playable-2',
      ],
    );

    expect(engine.lastStartIndex, 0);
    expect(engine.lastAutoPlay, isTrue);
  });

  test('playAll chooses among playable tracks when shuffle is enabled',
      () async {
    final repository = FakeLibraryQueryRepository()
      ..tracks = [
        track(id: 'playable-1'),
        track(
          id: 'unavailable',
          filePath: '',
          isAvailable: false,
        ),
        track(id: 'playable-2'),
      ];

    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      random: const FixedRandom(1),
    );

    await controller.load();
    await controller.setShuffleEnabled(true);
    await controller.playAll();

    expect(controller.isShuffleEnabled, isTrue);
    expect(engine.lastShuffleEnabled, isTrue);

    expect(
      engine.lastLoadedTracks!.map((track) => track.songId),
      [
        'playable-1',
        'playable-2',
      ],
    );

    expect(engine.lastStartIndex, 1);
  });

  test('playAll does nothing when no tracks are playable', () async {
    final repository = FakeLibraryQueryRepository()
      ..tracks = [
        track(
          id: 'missing-1',
          filePath: '',
          isAvailable: false,
        ),
        track(
          id: 'missing-2',
          filePath: '',
          isAvailable: false,
        ),
      ];

    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
    );

    await controller.load();
    await controller.playAll();

    expect(engine.loadQueueCallCount, 0);
    expect(engine.stopCallCount, 0);
  });

  test('toggleShuffle updates playback engine and controller state',
      () async {
    final repository = FakeLibraryQueryRepository();

    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
    );

    expect(controller.isShuffleEnabled, isFalse);

    await controller.toggleShuffle();

    expect(controller.isShuffleEnabled, isTrue);
    expect(engine.lastShuffleEnabled, isTrue);

    await controller.toggleShuffle();

    expect(controller.isShuffleEnabled, isFalse);
    expect(engine.lastShuffleEnabled, isFalse);
  });
}
