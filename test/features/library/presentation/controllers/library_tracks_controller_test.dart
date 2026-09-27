import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/library/application/models/library_album.dart';
import 'package:sonus_next/features/library/application/models/library_artist.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/application/models/library_track_order.dart';
import 'package:sonus_next/features/library/application/repositories/library_query_repository.dart';
import 'package:sonus_next/features/library/application/services/song_block_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/presentation/controllers/library_tracks_controller.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/sync/application/services/sync_mutation_runner.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_assignment_service.dart';
import 'package:sonus_next/features/artwork/application/services/artwork_file_picker.dart';
import 'package:sonus_next/features/artwork/domain/entities/artwork_asset.dart';

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
  }) async => const [];

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

class _CountingLibraryQueryRepository implements LibraryQueryRepository {
  _CountingLibraryQueryRepository({
    required this.delegate,
    required this.onGetTracks,
  });

  final FakeLibraryQueryRepository delegate;
  final void Function() onGetTracks;

  @override
  Future<List<LibraryTrack>> getTracks({
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) async {
    onGetTracks();
    return delegate.getTracks(order: order);
  }

  @override
  Future<List<LibraryTrack>> getRecentlyAddedTracks(int limit) {
    return delegate.getRecentlyAddedTracks(limit);
  }

  @override
  Future<LibraryTrack?> getTrackById(String songId) {
    return delegate.getTrackById(songId);
  }

  @override
  Future<List<LibraryTrack>> getTracksByArtistId(
    String artistId, {
    LibraryTrackOrder order = LibraryTrackOrder.title,
  }) {
    return delegate.getTracksByArtistId(artistId, order: order);
  }

  @override
  Future<List<LibraryTrack>> getTracksByAlbumId(String albumId) {
    return delegate.getTracksByAlbumId(albumId);
  }

  @override
  Future<List<LibraryAlbum>> getAlbums() {
    return delegate.getAlbums();
  }

  @override
  Future<List<LibraryAlbum>> getRecentlyAddedAlbums(int limit) {
    return delegate.getRecentlyAddedAlbums(limit);
  }

  @override
  Future<LibraryAlbum?> getAlbumById(String albumId) {
    return delegate.getAlbumById(albumId);
  }

  @override
  Future<List<LibraryAlbum>> getAlbumsByArtistId(String artistId) {
    return delegate.getAlbumsByArtistId(artistId);
  }

  @override
  Future<List<LibraryArtist>> getArtists() {
    return delegate.getArtists();
  }

  @override
  Future<LibraryArtist?> getArtistById(String artistId) {
    return delegate.getArtistById(artistId);
  }
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
  int removeTrackAtCallCount = 0;

  @override
  Stream<PlaybackState> get states => _statesController.stream;

  @override
  PlaybackState get currentState => const PlaybackState();
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
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {
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
  Future<void> removeTrackAt(int index) async {
    removeTrackAtCallCount++;
  }

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

class FakeArtworkFilePicker implements ArtworkFilePicker {
  FakeArtworkFilePicker({this.filePath});

  final String? filePath;

  int pickCallCount = 0;

  @override
  Future<String?> pickArtworkFile() async {
    pickCallCount++;
    return filePath;
  }
}

class FakeArtworkAssignmentService implements ArtworkAssignmentService {
  int assignSongCallCount = 0;
  int clearSongCallCount = 0;

  String? assignedSongId;
  String? assignedFilePath;
  String? clearedSongId;

  @override
  Future<ArtworkAsset> assignSong({
    required String songId,
    required String filePath,
    DateTime? now,
  }) async {
    assignSongCallCount++;
    assignedSongId = songId;
    assignedFilePath = filePath;

    return ArtworkAsset(
      id: 'artwork-test',
      filePath: filePath,
      normalizedPath: filePath.toLowerCase().replaceAll('\\', '/'),
      createdAt: now ?? DateTime(2026, 1, 1),
      updatedAt: now ?? DateTime(2026, 1, 1),
    );
  }

  @override
  Future<void> clearSong(String songId, {DateTime? now}) async {
    clearSongCallCount++;
    clearedSongId = songId;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
      ..tracks = [track(id: 'song-1', title: 'First Song')];

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

  test(
    'playTrack loads the current track context from the selected song',
    () async {
      final repository = FakeLibraryQueryRepository()
        ..tracks = [
          track(id: 'song-1'),
          track(id: 'song-2'),
          track(id: 'song-3'),
        ];

      final engine = FakePlaybackEngine();

      final controller = LibraryTracksController(
        repository: repository,
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await controller.load();
      await controller.playTrack(controller.tracks[1]);

      expect(engine.loadQueueCallCount, 1);
      expect(engine.lastLoadedTracks!.map((track) => track.songId), [
        'song-1',
        'song-2',
        'song-3',
      ]);
      expect(engine.lastStartIndex, 1);
      expect(engine.lastAutoPlay, isTrue);
    },
  );

  test(
    'playTrack remaps the selected song after unavailable tracks are filtered',
    () async {
      final repository = FakeLibraryQueryRepository()
        ..tracks = [
          track(id: 'missing', filePath: '', isAvailable: false),
          track(id: 'song-1'),
          track(id: 'song-2'),
        ];

      final engine = FakePlaybackEngine();

      final controller = LibraryTracksController(
        repository: repository,
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await controller.load();
      await controller.playTrack(controller.tracks[2]);

      expect(engine.loadQueueCallCount, 1);
      expect(engine.lastLoadedTracks!.map((track) => track.songId), [
        'song-1',
        'song-2',
      ]);
      expect(engine.lastStartIndex, 1);
      expect(engine.lastAutoPlay, isTrue);
    },
  );
  test(
    'playAll starts from the first playable track when shuffle is off',
    () async {
      final unavailable = track(
        id: 'unavailable',
        filePath: '',
        isAvailable: false,
      );

      final firstPlayable = track(id: 'playable-1');
      final secondPlayable = track(id: 'playable-2');

      final repository = FakeLibraryQueryRepository()
        ..tracks = [unavailable, firstPlayable, secondPlayable];

      final engine = FakePlaybackEngine();

      final controller = LibraryTracksController(
        repository: repository,
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
    },
  );

  test(
    'playAll chooses among playable tracks when shuffle is enabled',
    () async {
      final repository = FakeLibraryQueryRepository()
        ..tracks = [
          track(id: 'playable-1'),
          track(id: 'unavailable', filePath: '', isAvailable: false),
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

      expect(engine.lastLoadedTracks!.map((track) => track.songId), [
        'playable-1',
        'playable-2',
      ]);

      expect(engine.lastStartIndex, 1);
    },
  );

  test('playAll does nothing when no tracks are playable', () async {
    final repository = FakeLibraryQueryRepository()
      ..tracks = [
        track(id: 'missing-1', filePath: '', isAvailable: false),
        track(id: 'missing-2', filePath: '', isAvailable: false),
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

  test('toggleShuffle updates playback engine and controller state', () async {
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

  test(
    'canEditArtwork is true when artwork dependencies are available',
    () async {
      final repository = FakeLibraryQueryRepository();
      final engine = FakePlaybackEngine();

      final controller = LibraryTracksController(
        repository: repository,
        playbackCoordinator: PlaybackCoordinator(engine: engine),
        artworkAssignmentService: FakeArtworkAssignmentService(),
        artworkFilePicker: FakeArtworkFilePicker(),
      );

      expect(controller.canEditArtwork, isTrue);

      await engine.dispose();
    },
  );

  test('canEditArtwork is false without artwork dependencies', () async {
    final repository = FakeLibraryQueryRepository();
    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
    );

    expect(controller.canEditArtwork, isFalse);

    await engine.dispose();
  });

  test('changeArtwork assigns artwork to song and refreshes tracks', () async {
    var trackRequestCount = 0;

    final repository = FakeLibraryQueryRepository();

    final originalTrack = track(id: 'song-artwork', title: 'Original Title');

    final refreshedTrack = track(id: 'song-artwork', title: 'Refreshed Title');

    repository.tracks = [originalTrack];

    final artworkService = FakeArtworkAssignmentService();
    final artworkFilePicker = FakeArtworkFilePicker(
      filePath: r'C:\Music\Artwork\song.jpg',
    );

    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: _CountingLibraryQueryRepository(
        delegate: repository,
        onGetTracks: () {
          trackRequestCount++;

          repository.tracks = trackRequestCount == 1
              ? [originalTrack]
              : [refreshedTrack];
        },
      ),
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      artworkAssignmentService: artworkService,
      artworkFilePicker: artworkFilePicker,
    );

    await controller.load();

    expect(controller.tracks.single.title, 'Original Title');

    final changed = await controller.changeArtwork(controller.tracks.single);

    expect(changed, isTrue);
    expect(artworkFilePicker.pickCallCount, 1);
    expect(artworkService.assignSongCallCount, 1);
    expect(artworkService.assignedSongId, 'song-artwork');
    expect(artworkService.assignedFilePath, r'C:\Music\Artwork\song.jpg');
    expect(trackRequestCount, 2);
    expect(controller.tracks.single.title, 'Refreshed Title');

    await engine.dispose();
  });

  test('changeArtwork does nothing when picker is cancelled', () async {
    final repository = FakeLibraryQueryRepository()
      ..tracks = [track(id: 'song-artwork')];

    final artworkService = FakeArtworkAssignmentService();
    final artworkFilePicker = FakeArtworkFilePicker();

    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      artworkAssignmentService: artworkService,
      artworkFilePicker: artworkFilePicker,
    );

    await controller.load();

    final changed = await controller.changeArtwork(controller.tracks.single);

    expect(changed, isFalse);
    expect(artworkFilePicker.pickCallCount, 1);
    expect(artworkService.assignSongCallCount, 0);

    await engine.dispose();
  });

  test('clearArtwork clears song artwork and refreshes tracks', () async {
    var trackRequestCount = 0;

    final repository = FakeLibraryQueryRepository();

    final originalTrack = track(id: 'song-artwork', title: 'Original Title');

    final refreshedTrack = track(id: 'song-artwork', title: 'Refreshed Title');

    repository.tracks = [originalTrack];

    final artworkService = FakeArtworkAssignmentService();
    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: _CountingLibraryQueryRepository(
        delegate: repository,
        onGetTracks: () {
          trackRequestCount++;

          repository.tracks = trackRequestCount == 1
              ? [originalTrack]
              : [refreshedTrack];
        },
      ),
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      artworkAssignmentService: artworkService,
      artworkFilePicker: FakeArtworkFilePicker(),
    );

    await controller.load();

    final changed = await controller.clearArtwork(controller.tracks.single);

    expect(changed, isTrue);
    expect(artworkService.clearSongCallCount, 1);
    expect(artworkService.clearedSongId, 'song-artwork');
    expect(trackRequestCount, 2);
    expect(controller.tracks.single.title, 'Refreshed Title');

    await engine.dispose();
  });

  test('unavailable track can still have artwork changed', () async {
    final unavailableTrack = track(
      id: 'unavailable-song',
      filePath: '',
      isAvailable: false,
    );

    final repository = FakeLibraryQueryRepository()
      ..tracks = [unavailableTrack];

    final artworkService = FakeArtworkAssignmentService();
    final artworkFilePicker = FakeArtworkFilePicker(
      filePath: r'C:\Music\Artwork\unavailable.jpg',
    );

    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      artworkAssignmentService: artworkService,
      artworkFilePicker: artworkFilePicker,
    );

    await controller.load();

    final selectedTrack = controller.tracks.single;

    expect(controller.isTrackPlayable(selectedTrack), isFalse);
    expect(controller.canEditArtwork, isTrue);

    final changed = await controller.changeArtwork(selectedTrack);

    expect(changed, isTrue);
    expect(artworkService.assignSongCallCount, 1);
    expect(artworkService.assignedSongId, 'unavailable-song');

    await engine.dispose();
  });

  test('reports whether track metadata editing is available', () async {
    final repository = FakeLibraryQueryRepository();
    final engine = FakePlaybackEngine();
    final service = FakeTrackProfileEditingService();

    final editableController = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      trackProfileEditingService: service,
    );

    final missingServiceController = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
    );

    expect(editableController.canEditTrack('user-1'), isTrue);
    expect(editableController.canEditTrack('  user-1  '), isTrue);
    expect(editableController.canEditTrack(null), isFalse);
    expect(editableController.canEditTrack(''), isFalse);
    expect(editableController.canEditTrack('   '), isFalse);
    expect(missingServiceController.canEditTrack('user-1'), isFalse);

    await engine.dispose();
  });

  test('updateTrack forwards metadata and refreshes tracks', () async {
    var trackRequestCount = 0;

    final repository = FakeLibraryQueryRepository();
    final originalTrack = track(id: 'song-edit', title: 'Original Title');
    final refreshedTrack = track(id: 'song-edit', title: 'Edited Title');

    repository.tracks = [originalTrack];

    final service = FakeTrackProfileEditingService();
    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: _CountingLibraryQueryRepository(
        delegate: repository,
        onGetTracks: () {
          trackRequestCount++;

          repository.tracks = trackRequestCount == 1
              ? [originalTrack]
              : [refreshedTrack];
        },
      ),
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      trackProfileEditingService: service,
    );

    await controller.load();

    final changed = await controller.updateTrack(
      userId: 'user-1',
      track: controller.tracks.single,
      title: 'Edited Title',
      trackNumber: 7,
      discNumber: 1,
      featuredArtists: const ['Feature One', 'Feature Two'],
      isSingle: true,
    );

    expect(changed, isTrue);
    expect(service.updateCallCount, 1);
    expect(service.lastUserId, 'user-1');
    expect(service.lastSongId, 'song-edit');
    expect(service.lastTitle, 'Edited Title');
    expect(service.lastTrackNumber, 7);
    expect(service.lastFeaturedArtists, ['Feature One', 'Feature Two']);
    expect(service.lastIsSingle, isTrue);
    expect(trackRequestCount, 2);
    expect(controller.tracks.single.title, 'Edited Title');

    await engine.dispose();
  });

  test('unavailable track can still have metadata edited', () async {
    final unavailableTrack = track(
      id: 'unavailable-edit',
      title: 'Unavailable Song',
      filePath: '',
      isAvailable: false,
    );

    final repository = FakeLibraryQueryRepository()
      ..tracks = [unavailableTrack];

    final service = FakeTrackProfileEditingService();
    final engine = FakePlaybackEngine();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      trackProfileEditingService: service,
    );

    await controller.load();

    final selectedTrack = controller.tracks.single;

    expect(controller.isTrackPlayable(selectedTrack), isFalse);
    expect(controller.canEditTrack('user-1'), isTrue);

    final changed = await controller.updateTrack(
      userId: 'user-1',
      track: selectedTrack,
      title: 'Edited Unavailable Song',
      trackNumber: 2,
      discNumber: 1,
      featuredArtists: const ['Guest'],
      isSingle: false,
    );

    expect(changed, isTrue);
    expect(service.updateCallCount, 1);
    expect(service.lastSongId, 'unavailable-edit');

    await engine.dispose();
  });

  test(
    'updateTrack does nothing when editing is unavailable or user id is blank',
    () async {
      final repository = FakeLibraryQueryRepository()
        ..tracks = [track(id: 'song-edit')];

      final engine = FakePlaybackEngine();

      final missingServiceController = LibraryTracksController(
        repository: repository,
        playbackCoordinator: PlaybackCoordinator(engine: engine),
      );

      await missingServiceController.load();

      final missingServiceResult = await missingServiceController.updateTrack(
        userId: 'user-1',
        track: missingServiceController.tracks.single,
        title: 'Edited',
        trackNumber: 1,
        discNumber: 1,
        featuredArtists: const [],
        isSingle: false,
      );

      expect(missingServiceResult, isFalse);

      final service = FakeTrackProfileEditingService();

      final blankUserController = LibraryTracksController(
        repository: repository,
        playbackCoordinator: PlaybackCoordinator(engine: engine),
        trackProfileEditingService: service,
      );

      await blankUserController.load();

      final blankUserResult = await blankUserController.updateTrack(
        userId: '   ',
        track: blankUserController.tracks.single,
        title: 'Edited',
        trackNumber: 1,
        discNumber: 1,
        featuredArtists: const [],
        isSingle: false,
      );

      expect(blankUserResult, isFalse);
      expect(service.updateCallCount, 0);

      await engine.dispose();
    },
  );

  test('reports whether song blocking is available', () async {
    final repository = FakeLibraryQueryRepository();
    final engine = FakePlaybackEngine();
    final service = FakeSongBlockService();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      songBlockService: service,
    );

    final missingServiceController = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
    );

    expect(controller.canSetTrackBlocked('user-1'), isTrue);
    expect(controller.canSetTrackBlocked('  user-1  '), isTrue);
    expect(controller.canSetTrackBlocked(null), isFalse);
    expect(controller.canSetTrackBlocked(''), isFalse);
    expect(controller.canSetTrackBlocked('   '), isFalse);
    expect(missingServiceController.canSetTrackBlocked('user-1'), isFalse);

    await engine.dispose();
  });

  test('setTrackBlocked forwards mutation and refreshes tracks', () async {
    var trackRequestCount = 0;

    final repository = FakeLibraryQueryRepository()
      ..tracks = [track(id: 'song-block')];

    final engine = FakePlaybackEngine();
    final service = FakeSongBlockService();

    final controller = LibraryTracksController(
      repository: _CountingLibraryQueryRepository(
        delegate: repository,
        onGetTracks: () {
          trackRequestCount++;
        },
      ),
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      songBlockService: service,
    );

    await controller.load();

    expect(trackRequestCount, 1);

    final changed = await controller.setTrackBlocked(
      userId: 'user-1',
      track: controller.tracks.single,
      isBlocked: true,
    );

    expect(changed, isTrue);
    expect(service.setBlockedCallCount, 1);
    expect(service.lastUserId, 'user-1');
    expect(service.lastSongId, 'song-block');
    expect(service.lastIsBlocked, isTrue);
    expect(trackRequestCount, 2);

    await engine.dispose();
  });

  test('unblocking a song does not mutate the live queue', () async {
    final repository = FakeLibraryQueryRepository()
      ..tracks = [track(id: 'song-unblock')];

    final engine = FakePlaybackEngine();
    final service = FakeSongBlockService();

    final controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      songBlockService: service,
    );

    await controller.load();

    final changed = await controller.setTrackBlocked(
      userId: 'user-1',
      track: controller.tracks.single,
      isBlocked: false,
    );

    expect(changed, isTrue);
    expect(service.setBlockedCallCount, 1);
    expect(service.lastSongId, 'song-unblock');
    expect(service.lastIsBlocked, isFalse);

    expect(engine.removeTrackAtCallCount, 0);
    expect(engine.loadQueueCallCount, 0);
    expect(engine.lastInsertedTrack, isNull);
    expect(engine.lastAppendedTrack, isNull);
    expect(engine.stopCallCount, 0);

    await engine.dispose();
  });

  test('setTrackBlocked rejects missing service or blank user id', () async {
    final repository = FakeLibraryQueryRepository()
      ..tracks = [track(id: 'song-block')];

    final engine = FakePlaybackEngine();

    final missingServiceController = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
    );

    await missingServiceController.load();

    expect(
      await missingServiceController.setTrackBlocked(
        userId: 'user-1',
        track: missingServiceController.tracks.single,
        isBlocked: true,
      ),
      isFalse,
    );

    final service = FakeSongBlockService();

    final blankUserController = LibraryTracksController(
      repository: repository,
      playbackCoordinator: PlaybackCoordinator(engine: engine),
      songBlockService: service,
    );

    await blankUserController.load();

    expect(
      await blankUserController.setTrackBlocked(
        userId: '   ',
        track: blankUserController.tracks.single,
        isBlocked: true,
      ),
      isFalse,
    );

    expect(service.setBlockedCallCount, 0);

    await engine.dispose();
  });
}

class FakeSongBlockService extends SongBlockService {
  FakeSongBlockService()
    : super(mutationRunner: UnusedTrackSyncMutationRunner());

  int setBlockedCallCount = 0;
  String? lastUserId;
  String? lastSongId;
  bool? lastIsBlocked;

  @override
  Future<Song> setBlocked({
    required String userId,
    required String songId,
    required bool isBlocked,
    DateTime? now,
  }) async {
    setBlockedCallCount++;
    lastUserId = userId;
    lastSongId = songId;
    lastIsBlocked = isBlocked;

    final timestamp = now ?? DateTime.utc(2026, 1, 1);

    return Song(
      id: songId,
      artistId: 'artist-$songId',
      albumId: 'album-$songId',
      albumEditionId: 'edition-$songId',
      title: 'Song',
      canonicalTitle: 'song',
      trackNumber: 1,
      discNumber: 1,
      durationSeconds: 210,
      isSingle: false,
      featuredArtists: const [],
      artworkId: null,
      isBlocked: isBlocked,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }
}

class FakeTrackProfileEditingService extends TrackProfileEditingService {
  FakeTrackProfileEditingService()
    : super(mutationRunner: UnusedTrackSyncMutationRunner());

  int updateCallCount = 0;

  String? lastUserId;
  String? lastSongId;
  String? lastTitle;
  int? lastTrackNumber;
  int? lastDiscNumber;
  List<String>? lastFeaturedArtists;
  bool? lastIsSingle;

  @override
  Future<TrackProfileEditResult> updateTrack({
    required String userId,
    required String songId,
    required String title,
    required int trackNumber,
    int discNumber = 1,
    required List<String> featuredArtists,
    required bool isSingle,
    String? artistId,
    String? albumId,
    String? albumEditionId,
    DateTime? now,
  }) async {
    updateCallCount++;
    lastUserId = userId;
    lastSongId = songId;
    lastTitle = title;
    lastTrackNumber = trackNumber;
    lastDiscNumber = discNumber;
    lastFeaturedArtists = List<String>.from(featuredArtists);
    lastIsSingle = isSingle;

    final timestamp = now ?? DateTime.utc(2026, 1, 1);

    return TrackProfileEditResult(
      song: Song(
        id: songId,
        artistId: 'artist-$songId',
        albumId: 'album-$songId',
        albumEditionId: 'edition-$songId',
        title: title,
        canonicalTitle: title.trim().toLowerCase(),
        trackNumber: trackNumber,
        discNumber: discNumber,
        durationSeconds: 210,
        isSingle: isSingle,
        featuredArtists: List<String>.from(featuredArtists),
        artworkId: null,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
      changed: true,
    );
  }
}

class UnusedTrackSyncMutationRunner implements SyncMutationRunner {
  @override
  Future<T> run<T>(SyncMutationAction<T> action) {
    throw StateError('Sync mutation runner should not be used by this fake.');
  }
}
