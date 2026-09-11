import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/player/domain/models/playback_state.dart';

void main() {
  test('initial playback state is idle', () {
    const state = PlaybackState();

    expect(state.status, PlaybackStatus.idle);
    expect(state.hasTrack, isFalse);
    expect(state.isPlaying, isFalse);
    expect(state.progress, 0);
  });

  test('calculates clamped playback progress', () {
    const middle = PlaybackState(
      position: Duration(seconds: 50),
      duration: Duration(seconds: 100),
    );

    const beyond = PlaybackState(
      position: Duration(seconds: 150),
      duration: Duration(seconds: 100),
    );

    expect(middle.progress, 0.5);
    expect(beyond.progress, 1.0);
  });

  test('failed state exposes error', () {
    const state = PlaybackState(
      status: PlaybackStatus.failed,
      errorMessage: 'Unable to load audio.',
    );

    expect(state.hasError, isTrue);
    expect(state.errorMessage, 'Unable to load audio.');
  });

  test('copyWith can explicitly clear playback error', () {
    const failed = PlaybackState(
      status: PlaybackStatus.failed,
      errorMessage: 'Failure',
    );

    final restored = failed.copyWith(
      status: PlaybackStatus.ready,
      clearError: true,
    );

    expect(restored.status, PlaybackStatus.ready);
    expect(restored.errorMessage, isNull);
  });
}
