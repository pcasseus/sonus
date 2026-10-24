import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/library/application/models/library_track.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/application/controllers/playback_restoration_controller.dart';
import 'package:sonus_next/features/player/data/services/playback_session_store.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_session_snapshot.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

LibraryTrack _track(String id, {bool available = true, bool blocked = false}) {
  return LibraryTrack(
    songId: id,
    title: 'Song $id',
    artistId: 'artist',
    artistName: 'Artist',
    albumId: 'album',
    albumTitle: 'Album',
    albumEditionId: 'edition',
    albumEditionTitle: 'Standard',
    albumEditionType: AlbumEditionType.standard,
    trackNumber: 1,
    durationSeconds: 180,
    isSingle: false,
    featuredArtists: const [],
    dateAdded: DateTime.utc(2026, 10, 1),
    isAvailable: available,
    isSongBlocked: blocked,
    filePath: available ? '/music/$id.mp3' : null,
  );
}

void main() {
  late Map<String, String> storage;
  late _LoadingEngine engine;
  late PlaybackCoordinator coordinator;
  late List<(String, int)> logs;
  late PlaybackRestorationController controller;

  PlaybackSessionStore store() => PlaybackSessionStore.forTesting(
    getString: (key) async => storage[key],
    setString: (key, value) async => storage[key] = value,
    remove: (key) async => storage.remove(key),
  );

  void save(List<String> ids, {int index = 0, int seconds = 0}) {
    storage[PlaybackSessionStore.sessionKey] = jsonEncode(
      PlaybackSessionSnapshot(
        songIds: ids,
        currentIndex: index,
        position: Duration(seconds: seconds),
      ).toJson(),
    );
  }

  PlaybackSessionSnapshot? saved() {
    final raw = storage[PlaybackSessionStore.sessionKey];
    return raw == null
        ? null
        : PlaybackSessionSnapshot.fromJson(
            jsonDecode(raw) as Map<String, Object?>,
          );
  }

  Future<List<LibraryTrack>> library(List<LibraryTrack> tracks) async => tracks;

  setUp(() {
    storage = {};
    logs = [];
    engine = _LoadingEngine();
    coordinator = PlaybackCoordinator(engine: engine);
    controller = PlaybackRestorationController(
      store: store(),
      coordinator: coordinator,
      log: (message, {level = 800}) => logs.add((message, level)),
    );
  });

  tearDown(() async {
    controller.dispose();
    await engine.dispose();
  });

  group('restoring', () {
    test('brings the queue back paused, at the saved position', () async {
      save(['a', 'b', 'c'], index: 1, seconds: 75);

      final outcome = await controller.restore(
        () => library([_track('a'), _track('b'), _track('c')]),
      );

      expect(outcome, PlaybackRestoreOutcome.restored);
      expect(engine.loadedIds, ['a', 'b', 'c']);
      expect(engine.loadedStartIndex, 1);
      expect(engine.loadedAutoPlay, isFalse);
      expect(engine.seekedTo, const Duration(seconds: 75));
      expect(engine.playCalls, 0);
      expect(engine.currentState.status, PlaybackStatus.paused);
    });

    test('drops songs that are gone, missing or blacklisted', () async {
      save(['a', 'gone', 'missing', 'blocked', 'e'], index: 4, seconds: 30);

      await controller.restore(
        () => library([
          _track('a'),
          _track('missing', available: false),
          _track('blocked', blocked: true),
          _track('e'),
        ]),
      );

      expect(engine.loadedIds, ['a', 'e']);
      expect(engine.loadedStartIndex, 1);
      expect(engine.seekedTo, const Duration(seconds: 30));
    });

    test('if the saved song is gone, starts the next one from 0:00', () async {
      save(['a', 'gone', 'c'], index: 1, seconds: 90);

      await controller.restore(() => library([_track('a'), _track('c')]));

      expect(engine.loadedIds, ['a', 'c']);
      expect(engine.loadedStartIndex, 1);
      expect(engine.seekedTo, isNull);
    });

    test('nothing playable clears the saved session', () async {
      save(['a', 'b']);

      final outcome = await controller.restore(
        () => library([_track('a', available: false)]),
      );

      expect(outcome, PlaybackRestoreOutcome.nothingPlayable);
      expect(engine.loadedIds, isNull);
      expect(storage, isEmpty);
    });

    test('never replaces music that is already queued', () async {
      save(['a']);
      engine.emit(
        PlaybackState(
          queue: PlaybackQueue(tracks: [_playback('x')], currentIndex: 0),
          status: PlaybackStatus.playing,
        ),
      );

      final outcome = await controller.restore(() => library([_track('a')]));

      expect(outcome, PlaybackRestoreOutcome.skippedBusy);
      expect(engine.loadedIds, isNull);
    });

    test('runs only once', () async {
      save(['a']);
      await controller.restore(() => library([_track('a')]));

      final again = await controller.restore(() => library([_track('a')]));

      expect(again, PlaybackRestoreOutcome.skippedBusy);
      expect(engine.loadCalls, 1);
    });

    test('with nothing saved, Sonus starts empty', () async {
      final outcome = await controller.restore(() => library([_track('a')]));

      expect(outcome, PlaybackRestoreOutcome.nothingSaved);
      expect(engine.loadedIds, isNull);
    });

    test('a failure is logged and Sonus starts empty', () async {
      save(['a']);

      final outcome = await controller.restore(
        () async => throw StateError('library unavailable'),
      );

      expect(outcome, PlaybackRestoreOutcome.failed);
      expect(logs.single.$2, 1000);
    });
  });

  group('recording', () {
    test('the empty startup queue never erases the saved session', () async {
      save(['a', 'b'], index: 1, seconds: 40);

      // Sonus starts empty; states arrive before the library is readable.
      engine.emit(const PlaybackState());
      await pumpEventQueue();

      expect(saved()!.songIds, ['a', 'b']);
    });

    test('saves queue changes and steady progress', () async {
      await controller.restore(() => library(const []));

      engine.emit(_state(['a', 'b'], index: 0, seconds: 0));
      await pumpEventQueue();
      expect(saved()!.songIds, ['a', 'b']);

      engine.emit(_state(['a', 'b'], index: 0, seconds: 4));
      await pumpEventQueue();
      expect(saved()!.position, Duration.zero, reason: 'within interval');

      engine.emit(_state(['a', 'b'], index: 0, seconds: 11));
      await pumpEventQueue();
      expect(saved()!.position, const Duration(seconds: 11));

      engine.emit(_state(['a', 'b'], index: 1, seconds: 0));
      await pumpEventQueue();
      expect(saved()!.currentIndex, 1);
    });

    test('pausing saves the exact position', () async {
      await controller.restore(() => library(const []));
      engine.emit(_state(['a'], seconds: 0));
      await pumpEventQueue();

      engine.emit(_state(['a'], seconds: 3, status: PlaybackStatus.paused));
      await pumpEventQueue();

      expect(saved()!.position, const Duration(seconds: 3));
    });

    test(
      'saveNow captures the position before the app is backgrounded',
      () async {
        await controller.restore(() => library(const []));
        engine.emit(_state(['a'], seconds: 0));
        await pumpEventQueue();
        engine.emit(_state(['a'], seconds: 6));
        await pumpEventQueue();

        await controller.saveNow();

        expect(saved()!.position, const Duration(seconds: 6));
      },
    );

    test('a finished or cleared queue is not kept', () async {
      await controller.restore(() => library(const []));
      engine.emit(_state(['a'], seconds: 0));
      await pumpEventQueue();

      engine.emit(_state(['a'], status: PlaybackStatus.completed));
      await pumpEventQueue();
      expect(storage, isEmpty);

      engine.emit(_state(['a'], seconds: 0));
      await pumpEventQueue();
      engine.emit(const PlaybackState());
      await pumpEventQueue();
      expect(storage, isEmpty);
    });

    test('a failed save is logged, never thrown', () async {
      final failing = PlaybackRestorationController(
        store: PlaybackSessionStore.forTesting(
          getString: (key) async => null,
          setString: (key, value) async => throw StateError('disk full'),
          remove: (key) async {},
        ),
        coordinator: coordinator,
        log: (message, {level = 800}) => logs.add((message, level)),
      );
      addTearDown(failing.dispose);
      await failing.restore(() => library(const []));

      engine.emit(_state(['a']));
      await pumpEventQueue();

      expect(logs.last.$2, 900);
    });
  });

  group('snapshot format', () {
    test('round-trips', () {
      const snapshot = PlaybackSessionSnapshot(
        songIds: ['a', 'b'],
        currentIndex: 1,
        position: Duration(milliseconds: 1500),
      );

      expect(PlaybackSessionSnapshot.fromJson(snapshot.toJson()), snapshot);
    });

    test('rejects unusable documents', () {
      for (final json in <Map<String, Object?>>[
        {
          'version': 2,
          'songIds': ['a'],
          'currentIndex': 0,
          'positionMs': 0,
        },
        {
          'version': 1,
          'songIds': <String>[],
          'currentIndex': 0,
          'positionMs': 0,
        },
        {
          'version': 1,
          'songIds': ['a'],
          'currentIndex': 3,
          'positionMs': 0,
        },
        {
          'version': 1,
          'songIds': ['a'],
          'currentIndex': 0,
          'positionMs': -1,
        },
        {
          'version': 1,
          'songIds': [1],
          'currentIndex': 0,
          'positionMs': 0,
        },
      ]) {
        expect(PlaybackSessionSnapshot.fromJson(json), isNull, reason: '$json');
      }
    });

    test('corrupt storage reads as nothing saved', () async {
      storage[PlaybackSessionStore.sessionKey] = '{not json';

      expect(await store().load(), isNull);
    });
  });
}

PlaybackTrack _playback(String id) => PlaybackTrack(
  songId: id,
  title: 'Song $id',
  artistId: 'artist',
  artistName: 'Artist',
  albumId: 'album',
  albumTitle: 'Album',
  filePath: '/music/$id.mp3',
  duration: const Duration(minutes: 3),
);

PlaybackState _state(
  List<String> ids, {
  int index = 0,
  int seconds = 0,
  PlaybackStatus status = PlaybackStatus.playing,
}) {
  return PlaybackState(
    queue: PlaybackQueue(
      tracks: [for (final id in ids) _playback(id)],
      currentIndex: index,
    ),
    status: status,
    position: Duration(seconds: seconds),
  );
}

/// Loads queues like the real engine: the queue appears paused and never
/// starts playing unless asked.
class _LoadingEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState();

  List<String>? loadedIds;
  int? loadedStartIndex;
  bool? loadedAutoPlay;
  Duration? seekedTo;
  int loadCalls = 0;
  int playCalls = 0;

  void emit(PlaybackState state) {
    _state = state;
    _states.add(state);
  }

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {
    loadCalls++;
    loadedIds = [for (final track in tracks) track.songId];
    loadedStartIndex = startIndex;
    loadedAutoPlay = autoPlay;
    emit(
      PlaybackState(
        queue: PlaybackQueue(tracks: tracks, currentIndex: startIndex),
        status: autoPlay ? PlaybackStatus.playing : PlaybackStatus.paused,
      ),
    );
  }

  @override
  Future<void> seek(Duration position) async {
    seekedTo = position;
    emit(_state.copyWith(position: position));
  }

  @override
  Future<void> play() async => playCalls++;

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipToIndex(int index) async {}

  @override
  Future<void> insertTrack(PlaybackTrack track, {required int index}) async {}

  @override
  Future<void> appendTrack(PlaybackTrack track) async {}

  @override
  Future<void> removeTrackAt(int index) async {}

  @override
  Future<void> moveTrack({
    required int oldIndex,
    required int newIndex,
  }) async {}

  @override
  Future<void> setShuffleEnabled(bool enabled) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> dispose() async {
    if (!_states.isClosed) await _states.close();
  }
}
