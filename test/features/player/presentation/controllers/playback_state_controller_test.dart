import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/player/application/controllers/playback_coordinator.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';
import 'package:sonus_next/features/player/domain/models/playback_track.dart';
import 'package:sonus_next/features/player/domain/services/playback_engine.dart';
import 'package:sonus_next/features/player/presentation/controllers/playback_state_controller.dart';

class FakePlaybackEngine implements PlaybackEngine {
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();

  PlaybackState state = const PlaybackState();

  @override
  PlaybackState get currentState => state;

  @override
  Stream<PlaybackState> get states => _controller.stream;

  void emit(PlaybackState newState) {
    state = newState;
    _controller.add(newState);
  }

  @override
  Future<void> loadQueue(
    List<PlaybackTrack> tracks, {
    int startIndex = 0,
    bool autoPlay = false,
  }) async {}

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
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

void main() {
  test('starts with coordinator current state', () {
    final engine = FakePlaybackEngine()
      ..state = const PlaybackState(
        status: PlaybackStatus.paused,
        position: Duration(seconds: 12),
      );

    final coordinator = PlaybackCoordinator(engine: engine);

    final controller = PlaybackStateController(coordinator: coordinator);

    expect(controller.state.status, PlaybackStatus.paused);
    expect(controller.state.position, const Duration(seconds: 12));

    controller.dispose();
  });

  test('updates when coordinator emits playback state', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    final controller = PlaybackStateController(coordinator: coordinator);

    var notifications = 0;

    controller.addListener(() {
      notifications++;
    });

    const updatedState = PlaybackState(
      status: PlaybackStatus.playing,
      position: Duration(seconds: 30),
      duration: Duration(minutes: 3),
    );

    engine.emit(updatedState);

    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, PlaybackStatus.playing);
    expect(controller.state.position, const Duration(seconds: 30));
    expect(notifications, 1);

    controller.dispose();
  });

  test('stops notifying after disposal', () async {
    final engine = FakePlaybackEngine();
    final coordinator = PlaybackCoordinator(engine: engine);

    final controller = PlaybackStateController(coordinator: coordinator);

    var notifications = 0;

    controller.addListener(() {
      notifications++;
    });

    controller.dispose();

    engine.emit(const PlaybackState(status: PlaybackStatus.playing));

    await Future<void>.delayed(Duration.zero);

    expect(notifications, 0);
  });
}
