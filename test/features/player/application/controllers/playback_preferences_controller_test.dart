import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/application/controllers/playback_preferences_controller.dart';
import 'package:sonus_next/features/player/data/services/playback_preferences_store.dart';
import 'package:sonus_next/features/player/domain/models/playback_preferences.dart';
import 'package:sonus_next/features/player/domain/models/playback_queue.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';

const _track = PlaybackTrack(
  songId: 'song-1',
  title: 'First Song',
  artistId: 'artist-1',
  artistName: 'First Artist',
  albumId: 'album-1',
  albumTitle: 'First Album',
  filePath: '/music/first.mp3',
  duration: Duration(minutes: 3),
);

void main() {
  late Map<String, String> storage;
  late List<(String, int)> logs;
  late _ModeEngine engine;
  bool failWrites = false;

  PlaybackPreferencesController build({PlaybackPreferencesStore? store}) {
    final controller = PlaybackPreferencesController(
      store:
          store ??
          PlaybackPreferencesStore.forTesting(
            getString: (key) async => storage[key],
            setString: (key, value) async {
              if (failWrites) throw StateError('disk full');
              storage[key] = value;
            },
          ),
      coordinator: PlaybackCoordinator(engine: engine),
      log: (message, {level = 800}) => logs.add((message, level)),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  void storePreferences(PlaybackPreferences preferences) {
    storage[PlaybackPreferencesStore.preferencesKey] = jsonEncode(
      preferences.toJson(),
    );
  }

  Map<String, Object?> stored() =>
      jsonDecode(storage[PlaybackPreferencesStore.preferencesKey]!)
          as Map<String, Object?>;

  setUp(() {
    storage = {};
    logs = [];
    engine = _ModeEngine();
    failWrites = false;
  });

  tearDown(() => engine.dispose());

  test('defaults to off and changes nothing on a fresh device', () async {
    final controller = build();

    await controller.load();

    expect(controller.isLoaded, isTrue);
    expect(controller.preferences, const PlaybackPreferences());
    expect(engine.shuffleCalls, isEmpty);
    expect(engine.repeatCalls, isEmpty);
    expect(storage, isEmpty);
  });

  test('restores saved shuffle and repeat to an empty queue', () async {
    storePreferences(
      const PlaybackPreferences(
        rememberShuffleAndRepeat: true,
        shuffleEnabled: true,
        repeatMode: PlaybackRepeatMode.all,
      ),
    );
    final controller = build();

    await controller.load();

    expect(engine.currentState.shuffleEnabled, isTrue);
    expect(engine.currentState.repeatMode, PlaybackRepeatMode.all);
    expect(controller.restoreSkipped, isFalse);
  });

  test('never reshuffles music that is already queued', () async {
    storePreferences(
      const PlaybackPreferences(
        rememberShuffleAndRepeat: true,
        shuffleEnabled: true,
        repeatMode: PlaybackRepeatMode.one,
      ),
    );
    engine.emit(
      const PlaybackState(
        queue: PlaybackQueue(tracks: [_track], currentIndex: 0),
        status: PlaybackStatus.playing,
      ),
    );
    final controller = build();

    await controller.load();

    expect(engine.shuffleCalls, isEmpty);
    expect(engine.repeatCalls, isEmpty);
    expect(controller.restoreSkipped, isTrue);
  });

  test('saved modes are ignored while remembering is off', () async {
    storePreferences(
      const PlaybackPreferences(
        shuffleEnabled: true,
        repeatMode: PlaybackRepeatMode.all,
      ),
    );
    final controller = build();

    await controller.load();

    expect(engine.shuffleCalls, isEmpty);
    expect(engine.repeatCalls, isEmpty);
  });

  test('turning it on captures the current modes and saves them', () async {
    final controller = build();
    await controller.load();
    await engine.setShuffleEnabled(true);
    await engine.setRepeatMode(PlaybackRepeatMode.one);
    await pumpEventQueue();

    await controller.setRememberShuffleAndRepeat(true);

    expect(stored(), {
      'version': 1,
      'rememberShuffleAndRepeat': true,
      'shuffleEnabled': true,
      'repeatMode': 'one',
    });
  });

  test('records mode changes while remembering is on', () async {
    final controller = build();
    await controller.load();
    await controller.setRememberShuffleAndRepeat(true);

    await engine.setRepeatMode(PlaybackRepeatMode.all);
    await pumpEventQueue();

    expect(controller.preferences.repeatMode, PlaybackRepeatMode.all);
    expect(stored()['repeatMode'], 'all');
  });

  test('turning it off forgets the saved modes and stops recording', () async {
    final controller = build();
    await controller.load();
    await controller.setRememberShuffleAndRepeat(true);
    await engine.setShuffleEnabled(true);
    await pumpEventQueue();

    await controller.setRememberShuffleAndRepeat(false);
    await engine.setRepeatMode(PlaybackRepeatMode.all);
    await pumpEventQueue();

    expect(stored(), const PlaybackPreferences().toJson());
    // The player itself keeps whatever the listener chose.
    expect(engine.currentState.shuffleEnabled, isTrue);
  });

  test('unreadable storage keeps defaults and is logged', () async {
    final controller = build(
      store: PlaybackPreferencesStore.forTesting(
        getString: (key) async => throw StateError('locked'),
        setString: (key, value) async {},
      ),
    );

    await controller.load();

    expect(controller.isLoaded, isTrue);
    expect(controller.preferences, const PlaybackPreferences());
    expect(logs.single.$2, 1000);
  });

  test(
    'a failed save keeps the choice for the session and reports it',
    () async {
      final controller = build();
      await controller.load();
      failWrites = true;

      await controller.setRememberShuffleAndRepeat(true);

      expect(controller.preferences.rememberShuffleAndRepeat, isTrue);
      expect(controller.saveError, isA<StateError>());
      expect(logs.last.$2, 1000);

      failWrites = false;
      await controller.setRememberShuffleAndRepeat(false);
      expect(controller.saveError, isNull);
    },
  );
}

/// A playback engine that only models shuffle, repeat and the queue.
class _ModeEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState();

  final List<bool> shuffleCalls = [];
  final List<PlaybackRepeatMode> repeatCalls = [];

  void emit(PlaybackState state) {
    _state = state;
    _states.add(state);
  }

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  Future<void> setShuffleEnabled(bool enabled) async {
    shuffleCalls.add(enabled);
    emit(_state.copyWith(shuffleEnabled: enabled));
  }

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {
    repeatCalls.add(mode);
    emit(_state.copyWith(repeatMode: mode));
  }

  @override
  Future<void> dispose() async {
    if (!_states.isClosed) await _states.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
