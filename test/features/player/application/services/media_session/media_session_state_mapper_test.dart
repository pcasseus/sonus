import 'package:audio_service/audio_service.dart' as media;
import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/player/application/services/media_session/media_session_state_mapper.dart';
import 'package:sonus_next/features/player/domain/models/playback_repeat_mode.dart';
import 'package:sonus_next/features/player/domain/models/playback_state.dart';

import 'media_session_test_support.dart';

final _now = DateTime.utc(2026, 10, 24, 12);

MediaSessionSnapshot _map(
  PlaybackState state, {
  bool previousPlaying = false,
  bool artworkExists = true,
}) {
  return MediaSessionStateMapper.map(
    state,
    now: _now,
    previousPlaying: previousPlaying,
    artworkExists: (_) => artworkExists,
  );
}

void main() {
  group('controls', () {
    test('every active state shows Previous, Play/Pause, Next, Stop', () {
      for (final status in [
        PlaybackStatus.loading,
        PlaybackStatus.ready,
        PlaybackStatus.playing,
        PlaybackStatus.paused,
        PlaybackStatus.failed,
      ]) {
        final state = _map(queuedState(status: status)).state;
        final actions = state.controls.map((c) => c.action).toList();

        expect(actions, [
          media.MediaAction.skipToPrevious,
          state.playing ? media.MediaAction.pause : media.MediaAction.play,
          media.MediaAction.skipToNext,
          media.MediaAction.stop,
        ], reason: '$status');
        expect(state.androidCompactActionIndices, [0, 1, 2], reason: '$status');
      }
    });

    test('previous and next stay visible at the ends of the queue', () {
      for (final index in [0, 2]) {
        final actions = _map(
          queuedState(index: index),
        ).state.controls.map((c) => c.action);

        expect(actions, contains(media.MediaAction.skipToPrevious));
        expect(actions, contains(media.MediaAction.skipToNext));
      }
    });

    test('lock screen, Bluetooth and headsets can seek and toggle', () {
      final actions = _map(queuedState()).state.systemActions;

      expect(
        actions,
        containsAll([
          media.MediaAction.seek,
          media.MediaAction.playPause,
          media.MediaAction.skipToQueueItem,
          media.MediaAction.setShuffleMode,
          media.MediaAction.setRepeatMode,
        ]),
      );
    });
  });

  group('status', () {
    test('playing and paused map to ready with the right button', () {
      final playing = _map(queuedState()).state;
      final paused = _map(queuedState(status: PlaybackStatus.paused)).state;

      expect(playing.processingState, media.AudioProcessingState.ready);
      expect(playing.playing, isTrue);
      expect(paused.processingState, media.AudioProcessingState.ready);
      expect(paused.playing, isFalse);
    });

    test('buffering keeps the button the listener chose', () {
      final whilePlaying = _map(
        queuedState(status: PlaybackStatus.loading),
        previousPlaying: true,
      ).state;
      final whilePaused = _map(
        queuedState(status: PlaybackStatus.loading),
      ).state;

      expect(
        whilePlaying.processingState,
        media.AudioProcessingState.buffering,
      );
      expect(whilePlaying.playing, isTrue);
      expect(whilePaused.playing, isFalse);
    });

    test('an error keeps the controls so the listener can move on', () {
      final state = _map(queuedState(status: PlaybackStatus.failed)).state;

      expect(state.processingState, media.AudioProcessingState.error);
      expect(state.playing, isFalse);
      expect(state.errorMessage, 'This song could not be played.');
      expect(state.controls, isNotEmpty);
    });

    test('stopped, finished and empty sessions go idle with nothing shown', () {
      for (final state in [
        const PlaybackState(),
        queuedState(status: PlaybackStatus.idle),
        queuedState(status: PlaybackStatus.completed),
        queuedState(tracks: const []),
      ]) {
        final snapshot = _map(state);

        expect(snapshot.state.processingState, media.AudioProcessingState.idle);
        expect(snapshot.state.controls, isEmpty);
        expect(snapshot.item, isNull);
        expect(snapshot.queue, isEmpty);
      }
    });
  });

  group('metadata', () {
    test('describes the current track', () {
      final item = _map(queuedState(index: 1)).item!;

      expect(item.id, 'b');
      expect(item.title, 'Song b');
      expect(item.artist, 'Artist b');
      expect(item.album, 'Album b');
      expect(item.duration, const Duration(minutes: 3));
    });

    test('uses the loaded duration, falling back to the library one', () {
      expect(
        _map(
          queuedState(duration: const Duration(seconds: 200)),
        ).item!.duration,
        const Duration(seconds: 200),
      );
      expect(
        _map(queuedState(duration: Duration.zero)).item!.duration,
        const Duration(minutes: 3),
      );
    });

    test('offers artwork only when the file exists', () {
      final withArt = queuedState(
        tracks: [mediaTrack('a', artworkPath: '/art/a.png')],
      );

      expect(_map(withArt).item!.artUri, Uri.file('/art/a.png'));
      expect(_map(withArt, artworkExists: false).item!.artUri, isNull);
      expect(
        _map(
          queuedState(tracks: [mediaTrack('a', artworkPath: '  ')]),
        ).item!.artUri,
        isNull,
      );
    });

    test('publishes the queue, position and modes', () {
      final snapshot = _map(
        queuedState(
          index: 2,
          position: const Duration(seconds: 42),
          shuffle: true,
          repeat: PlaybackRepeatMode.one,
        ),
      );

      expect(snapshot.queue.map((item) => item.id), ['a', 'b', 'c']);
      expect(snapshot.state.queueIndex, 2);
      expect(snapshot.state.updatePosition, const Duration(seconds: 42));
      expect(snapshot.state.updateTime, _now);
      expect(snapshot.state.shuffleMode, media.AudioServiceShuffleMode.all);
      expect(snapshot.state.repeatMode, media.AudioServiceRepeatMode.one);
    });
  });
}
