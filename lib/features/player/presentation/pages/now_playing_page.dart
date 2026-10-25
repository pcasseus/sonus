import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/playback/sonus_now_playing_view.dart';
import '../../../../core/design/widgets/playback/sonus_playback_controls.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../application/controllers/playback_coordinator.dart';
import '../../domain/models/playback_repeat_mode.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/playback_track.dart';
import '../controllers/playback_state_controller.dart';
import 'lyrics_page.dart';
import 'playback_queue_page.dart';
import '../widgets/playback_error_notice.dart';

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  /// Route name the playback host uses to hide the mini-player here.
  static const routeName = '/now-playing';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlaybackStateController>().state;
    final coordinator = context.read<PlaybackCoordinator>();
    final track = state.queue.currentTrack;

    return Scaffold(
      key: const ValueKey<String>('now-playing-page'),
      // The artwork atmosphere runs behind a transparent app bar.
      extendBodyBehindAppBar: track != null,
      appBar: AppBar(
        backgroundColor: track == null ? null : Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          key: const ValueKey<String>('now-playing-close'),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
        title: const Text('Now Playing'),
        centerTitle: true,
      ),
      body: track == null
          ? const SonusStateView(
              key: ValueKey<String>('now-playing-empty'),
              icon: Icons.music_note_rounded,
              title: 'Nothing is playing',
              message: 'Play a song to see it here.',
            )
          : _NowPlayingContent(
              state: state,
              track: track,
              coordinator: coordinator,
            ),
    );
  }
}

/// Maps the SN-44 playback state onto the Sonus Now Playing layout. The
/// progress bar keeps SN-44's seek contract: while a finger drags, the bar
/// and elapsed time follow it locally, and playback seeks once, when the
/// drag or tap ends.
class _NowPlayingContent extends StatelessWidget {
  const _NowPlayingContent({
    required this.state,
    required this.track,
    required this.coordinator,
  });

  final PlaybackState state;
  final PlaybackTrack track;
  final PlaybackCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    final knownDuration = state.duration > Duration.zero
        ? state.duration
        : null;

    return SonusNowPlayingView(
      keyPrefix: 'now-playing',
      title: track.title,
      artist: track.artistName,
      album: track.albumTitle,
      artworkPath: track.artworkPath,
      position: state.position,
      duration: knownDuration,
      isPlaying: state.isPlaying,
      isLoading: state.status == PlaybackStatus.loading,
      shuffleEnabled: state.shuffleEnabled,
      repeat: _repeatDisplay(state.repeatMode),
      notice: state.hasError ? const _PlaybackError() : null,
      onSeek: (position) {
        unawaited(coordinator.seek(position));
      },
      onPlayPause: () {
        unawaited(coordinator.togglePlayPause());
      },
      onPrevious: state.canSkipPrevious
          ? () {
              unawaited(coordinator.skipPrevious());
            }
          : null,
      onNext: state.canSkipNext
          ? () {
              unawaited(coordinator.skipNext());
            }
          : null,
      onToggleShuffle: () {
        unawaited(coordinator.setShuffleEnabled(!state.shuffleEnabled));
      },
      onCycleRepeat: () {
        unawaited(coordinator.setRepeatMode(_nextRepeatMode(state.repeatMode)));
      },
      onOpenQueue: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PlaybackQueuePage()),
        );
      },
      onOpenLyrics: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const LyricsPage()));
      },
    );
  }

  static SonusRepeatDisplay _repeatDisplay(PlaybackRepeatMode mode) =>
      switch (mode) {
        PlaybackRepeatMode.off => SonusRepeatDisplay.off,
        PlaybackRepeatMode.all => SonusRepeatDisplay.all,
        PlaybackRepeatMode.one => SonusRepeatDisplay.one,
      };

  static PlaybackRepeatMode _nextRepeatMode(PlaybackRepeatMode current) =>
      switch (current) {
        PlaybackRepeatMode.off => PlaybackRepeatMode.all,
        PlaybackRepeatMode.all => PlaybackRepeatMode.one,
        PlaybackRepeatMode.one => PlaybackRepeatMode.off,
      };
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError();

  // The engine's error text is technical and can contain file paths, so the
  // listener sees plain wording instead.
  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return Container(
      key: const ValueKey<String>('now-playing-error'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.colors.raisedSurface,
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        border: Border.all(color: tokens.colors.divider),
      ),
      child: const Center(
        child: PlaybackErrorNotice(message: PlaybackErrorNotice.fullMessage),
      ),
    );
  }
}
