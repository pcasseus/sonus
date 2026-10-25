import 'dart:io';

import 'package:audio_service/audio_service.dart' as media;
import 'package:flutter/foundation.dart';

import '../../../domain/models/playback_repeat_mode.dart';
import '../../../domain/models/playback_state.dart';
import '../../../domain/models/playback_track.dart';

typedef ArtworkExists = bool Function(String path);

/// What the Android media session should show for one Sonus state.
@immutable
class MediaSessionSnapshot {
  const MediaSessionSnapshot({
    required this.state,
    required this.item,
    required this.queue,
  });

  final media.PlaybackState state;
  final media.MediaItem? item;
  final List<media.MediaItem> queue;
}

/// Translates Sonus playback state into media-session state.
///
/// Pure: it never touches the player, the queue or analytics. The
/// notification always shows Previous, Play/Pause and Next in the same
/// order while something is queued; only the play/pause glyph changes.
abstract final class MediaSessionStateMapper {
  /// Expanded-notification buttons, always in this order. Stop comes last
  /// so the compact view (first three) never changes shape.
  static List<media.MediaControl> controlsFor({required bool playing}) => [
    media.MediaControl.skipToPrevious,
    playing ? media.MediaControl.pause : media.MediaControl.play,
    media.MediaControl.skipToNext,
    media.MediaControl.stop,
  ];

  static const List<int> compactActionIndices = [0, 1, 2];

  /// Actions Android may send from the lock screen, Bluetooth devices and
  /// (later) Android Auto.
  static const Set<media.MediaAction> systemActions = {
    media.MediaAction.seek,
    media.MediaAction.playPause,
    media.MediaAction.skipToQueueItem,
    media.MediaAction.setShuffleMode,
    media.MediaAction.setRepeatMode,
  };

  /// Maps [state]. While Sonus is loading, [previousPlaying] keeps the
  /// play/pause button showing what the listener asked for, so it does not
  /// flicker during buffering.
  static MediaSessionSnapshot map(
    PlaybackState state, {
    required DateTime now,
    bool previousPlaying = false,
    ArtworkExists? artworkExists,
  }) {
    final track = state.queue.currentTrack;

    // Nothing queued, or a terminal state: the session goes idle, which
    // removes the notification and lets the service stop.
    if (track == null ||
        state.status == PlaybackStatus.idle ||
        state.status == PlaybackStatus.completed) {
      return MediaSessionSnapshot(
        state: media.PlaybackState(
          processingState: media.AudioProcessingState.idle,
          updateTime: now,
          repeatMode: _repeatMode(state.repeatMode),
          shuffleMode: _shuffleMode(state.shuffleEnabled),
        ),
        item: null,
        queue: const [],
      );
    }

    final playing = switch (state.status) {
      PlaybackStatus.playing => true,
      PlaybackStatus.loading => previousPlaying,
      _ => false,
    };

    final processingState = switch (state.status) {
      PlaybackStatus.loading => media.AudioProcessingState.buffering,
      PlaybackStatus.failed => media.AudioProcessingState.error,
      _ => media.AudioProcessingState.ready,
    };

    final failed = state.status == PlaybackStatus.failed;

    return MediaSessionSnapshot(
      state: media.PlaybackState(
        processingState: processingState,
        playing: playing,
        controls: controlsFor(playing: playing),
        androidCompactActionIndices: compactActionIndices,
        systemActions: systemActions,
        updatePosition: state.position,
        bufferedPosition: state.position,
        updateTime: now,
        errorCode: failed ? 1 : null,
        errorMessage: failed ? 'This song could not be played.' : null,
        repeatMode: _repeatMode(state.repeatMode),
        shuffleMode: _shuffleMode(state.shuffleEnabled),
        queueIndex: state.queue.currentIndex,
      ),
      item: itemFor(
        track,
        duration: state.duration,
        artworkExists: artworkExists ?? _fileExists,
      ),
      queue: [for (final queued in state.queue.tracks) itemFor(queued)],
    );
  }

  /// The media item for [track]. Artwork is only offered when the file
  /// exists, so a missing file never leaves a broken image.
  static media.MediaItem itemFor(
    PlaybackTrack track, {
    Duration? duration,
    ArtworkExists? artworkExists,
  }) {
    final artworkPath = track.artworkPath?.trim();
    final hasArtwork =
        artworkExists != null &&
        artworkPath != null &&
        artworkPath.isNotEmpty &&
        artworkExists(artworkPath);
    final knownDuration = duration != null && duration > Duration.zero
        ? duration
        : track.duration > Duration.zero
        ? track.duration
        : null;

    return media.MediaItem(
      id: track.songId,
      title: track.title,
      artist: track.artistName,
      album: track.albumTitle,
      duration: knownDuration,
      artUri: hasArtwork ? Uri.file(artworkPath) : null,
      playable: true,
    );
  }

  static media.AudioServiceRepeatMode _repeatMode(PlaybackRepeatMode mode) =>
      switch (mode) {
        PlaybackRepeatMode.off => media.AudioServiceRepeatMode.none,
        PlaybackRepeatMode.one => media.AudioServiceRepeatMode.one,
        PlaybackRepeatMode.all => media.AudioServiceRepeatMode.all,
      };

  static media.AudioServiceShuffleMode _shuffleMode(bool enabled) => enabled
      ? media.AudioServiceShuffleMode.all
      : media.AudioServiceShuffleMode.none;

  static bool _fileExists(String path) {
    try {
      return File(path).existsSync();
    } on FileSystemException {
      return false;
    }
  }
}
