import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlaybackStateController>().state;
    final coordinator = context.read<PlaybackCoordinator>();
    final track = state.queue.currentTrack;

    return Scaffold(
      key: const ValueKey<String>('now-playing-page'),
      appBar: AppBar(
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
          ? const _EmptyNowPlaying()
          : _NowPlayingContent(
              state: state,
              track: track,
              coordinator: coordinator,
            ),
    );
  }
}

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
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final artworkSize = (constraints.maxWidth - 48).clamp(220.0, 420.0);

          return SingleChildScrollView(
            key: const PageStorageKey<String>('now-playing-scroll'),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 44,
              ),
              child: Column(
                children: [
                  Hero(
                    tag: 'player-artwork-${track.songId}',
                    child: _NowPlayingArtwork(track: track, size: artworkSize),
                  ),
                  const SizedBox(height: 28),
                  _TrackMetadata(track: track),
                  // Directly under the song, so it is seen without scrolling.
                  if (state.hasError) ...[
                    const SizedBox(height: 16),
                    const _PlaybackError(),
                  ],
                  const SizedBox(height: 24),
                  _SeekSection(state: state, coordinator: coordinator),
                  const SizedBox(height: 14),
                  _PrimaryControls(state: state, coordinator: coordinator),
                  const SizedBox(height: 22),
                  _SecondaryActions(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _NowPlayingArtwork extends StatelessWidget {
  const _NowPlayingArtwork({required this.track, required this.size});

  final PlaybackTrack track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final path = track.artworkPath?.trim();

    return SizedBox.square(
      key: const ValueKey<String>('now-playing-artwork'),
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: colorScheme.surfaceContainerHighest,
          child: path != null && path.isNotEmpty
              ? Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      _ArtworkFallback(colorScheme: colorScheme),
                )
              : _ArtworkFallback(colorScheme: colorScheme),
        ),
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey<String>('now-playing-artwork-fallback'),
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 96,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TrackMetadata extends StatelessWidget {
  const _TrackMetadata({required this.track});

  final PlaybackTrack track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const ValueKey<String>('now-playing-metadata'),
      children: [
        Text(
          track.title,
          key: const ValueKey<String>('now-playing-title'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          track.artistName,
          key: const ValueKey<String>('now-playing-artist'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (track.albumTitle.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            track.albumTitle,
            key: const ValueKey<String>('now-playing-album'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The seek bar seeks once, when a drag or tap ends. While the finger is
/// down the bar and elapsed time follow it instead of playback, so playback
/// isn't asked to seek on every frame of a drag.
class _SeekSection extends StatefulWidget {
  const _SeekSection({required this.state, required this.coordinator});

  final PlaybackState state;
  final PlaybackCoordinator coordinator;

  @override
  State<_SeekSection> createState() => _SeekSectionState();
}

class _SeekSectionState extends State<_SeekSection> {
  /// Where the drag currently is; null when not dragging.
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final durationMs = state.duration.inMilliseconds;
    final safeDurationMs = durationMs < 0 ? 0 : durationMs;
    final rawPositionMs = _dragMs?.round() ?? state.position.inMilliseconds;

    final safePositionMs = rawPositionMs.clamp(0, safeDurationMs);

    final max = safeDurationMs > 0 ? safeDurationMs.toDouble() : 1.0;
    final value = safeDurationMs > 0 ? safePositionMs.toDouble() : 0.0;
    final canSeek = safeDurationMs > 0;

    return Column(
      key: const ValueKey<String>('now-playing-seek-section'),
      children: [
        Slider(
          key: const ValueKey<String>('now-playing-seek'),
          value: value,
          max: max,
          onChangeStart: canSeek
              ? (newValue) => setState(() => _dragMs = newValue)
              : null,
          onChanged: canSeek
              ? (newValue) => setState(() => _dragMs = newValue)
              : null,
          onChangeEnd: canSeek
              ? (newValue) {
                  setState(() => _dragMs = null);
                  unawaited(
                    widget.coordinator.seek(
                      Duration(milliseconds: newValue.round()),
                    ),
                  );
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(Duration(milliseconds: safePositionMs)),
                key: const ValueKey<String>('now-playing-elapsed'),
              ),
              Text(
                _formatDuration(state.duration),
                key: const ValueKey<String>('now-playing-duration'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PrimaryControls extends StatelessWidget {
  const _PrimaryControls({required this.state, required this.coordinator});

  final PlaybackState state;
  final PlaybackCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    final isLoading = state.status == PlaybackStatus.loading;

    return Row(
      key: const ValueKey<String>('now-playing-primary-controls'),
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          key: const ValueKey<String>('now-playing-shuffle'),
          tooltip: state.shuffleEnabled
              ? 'Turn shuffle off'
              : 'Turn shuffle on',
          isSelected: state.shuffleEnabled,
          onPressed: () {
            unawaited(coordinator.setShuffleEnabled(!state.shuffleEnabled));
          },
          icon: const Icon(Icons.shuffle_rounded),
          selectedIcon: const Icon(Icons.shuffle_on_rounded),
        ),
        IconButton(
          key: const ValueKey<String>('now-playing-previous'),
          tooltip: 'Previous',
          iconSize: 36,
          onPressed: state.canSkipPrevious
              ? () {
                  unawaited(coordinator.skipPrevious());
                }
              : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        SizedBox.square(
          dimension: 72,
          child: IconButton.filled(
            key: const ValueKey<String>('now-playing-play-pause'),
            tooltip: state.isPlaying ? 'Pause' : 'Play',
            iconSize: 38,
            onPressed: isLoading
                ? null
                : () {
                    unawaited(coordinator.togglePlayPause());
                  },
            icon: isLoading
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(
                    state.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
          ),
        ),
        IconButton(
          key: const ValueKey<String>('now-playing-next'),
          tooltip: 'Next',
          iconSize: 36,
          onPressed: state.canSkipNext
              ? () {
                  unawaited(coordinator.skipNext());
                }
              : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          key: const ValueKey<String>('now-playing-repeat'),
          tooltip: _repeatTooltip(state.repeatMode),
          isSelected: state.repeatMode != PlaybackRepeatMode.off,
          onPressed: () {
            unawaited(
              coordinator.setRepeatMode(_nextRepeatMode(state.repeatMode)),
            );
          },
          icon: Icon(_repeatIcon(state.repeatMode)),
        ),
      ],
    );
  }

  PlaybackRepeatMode _nextRepeatMode(PlaybackRepeatMode current) {
    switch (current) {
      case PlaybackRepeatMode.off:
        return PlaybackRepeatMode.all;
      case PlaybackRepeatMode.all:
        return PlaybackRepeatMode.one;
      case PlaybackRepeatMode.one:
        return PlaybackRepeatMode.off;
    }
  }

  IconData _repeatIcon(PlaybackRepeatMode mode) {
    switch (mode) {
      case PlaybackRepeatMode.one:
        return Icons.repeat_one_rounded;
      case PlaybackRepeatMode.off:
      case PlaybackRepeatMode.all:
        return Icons.repeat_rounded;
    }
  }

  String _repeatTooltip(PlaybackRepeatMode mode) {
    switch (mode) {
      case PlaybackRepeatMode.off:
        return 'Repeat off';
      case PlaybackRepeatMode.all:
        return 'Repeat all';
      case PlaybackRepeatMode.one:
        return 'Repeat one';
    }
  }
}

class _SecondaryActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey<String>('now-playing-secondary-actions'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          key: const ValueKey<String>('now-playing-lyrics'),
          onPressed: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const LyricsPage()));
          },
          icon: const Icon(Icons.lyrics_outlined),
          label: const Text('Lyrics'),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          key: const ValueKey<String>('now-playing-queue'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PlaybackQueuePage(),
              ),
            );
          },
          icon: const Icon(Icons.queue_music_rounded),
          label: const Text('Queue'),
        ),
      ],
    );
  }
}

class _PlaybackError extends StatelessWidget {
  const _PlaybackError();

  // The engine's error text is technical and can contain file paths, so the
  // listener sees plain wording instead.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: const ValueKey<String>('now-playing-error'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(
        child: PlaybackErrorNotice(message: PlaybackErrorNotice.fullMessage),
      ),
    );
  }
}

class _EmptyNowPlaying extends StatelessWidget {
  const _EmptyNowPlaying();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      key: const ValueKey<String>('now-playing-empty'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 72,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing is playing',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
