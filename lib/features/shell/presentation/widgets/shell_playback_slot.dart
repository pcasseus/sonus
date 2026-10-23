import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/models/playback_track.dart';
import '../../../player/presentation/controllers/playback_state_controller.dart';
import '../../../player/presentation/pages/now_playing_page.dart';
import '../../../player/presentation/pages/playback_queue_page.dart';

class ShellPlaybackSlot extends StatelessWidget {
  const ShellPlaybackSlot({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (child != null) {
      return Material(
        key: const ValueKey<String>('shell-playback-slot'),
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(top: false, child: child!),
      );
    }

    final stateController = context.watch<PlaybackStateController>();
    final state = stateController.state;
    final track = state.queue.currentTrack;

    return Material(
      key: const ValueKey<String>('shell-playback-slot'),
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: track == null
            ? const SizedBox.shrink(key: ValueKey<String>('mini-player-empty'))
            : _MiniPlayer(
                state: state,
                track: track,
                coordinator: context.read<PlaybackCoordinator>(),
              ),
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({
    required this.state,
    required this.track,
    required this.coordinator,
  });

  final PlaybackState state;
  final PlaybackTrack track;
  final PlaybackCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return Semantics(
      container: true,
      label: 'Now playing ${track.title} by ${track.artistName}',
      child: Container(
        key: const ValueKey<String>('mini-player'),
        decoration: BoxDecoration(
          color: tokens.colors.raisedSurface,
          border: Border(top: BorderSide(color: tokens.colors.divider)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MiniPlayerProgress(state: state),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const ValueKey<String>('mini-player-open'),
                      borderRadius: BorderRadius.circular(
                        tokens.metrics.controlRadius,
                      ),
                      onTap: () => _openNowPlaying(context),
                      child: Row(
                        children: [
                          Hero(
                            tag: 'player-artwork-${track.songId}',
                            child: _MiniPlayerArtwork(track: track),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _MiniPlayerMetadata(track: track)),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('mini-player-previous'),
                    tooltip: 'Previous',
                    onPressed: state.queue.hasPrevious
                        ? () {
                            unawaited(coordinator.skipPrevious());
                          }
                        : null,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  _MiniPlayerPlayPauseButton(
                    state: state,
                    coordinator: coordinator,
                  ),
                  IconButton(
                    key: const ValueKey<String>('mini-player-next'),
                    tooltip: 'Next',
                    onPressed: state.queue.hasNext
                        ? () {
                            unawaited(coordinator.skipNext());
                          }
                        : null,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  IconButton(
                    key: const ValueKey<String>('mini-player-queue'),
                    tooltip: 'Queue',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PlaybackQueuePage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.queue_music_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openNowPlaying(BuildContext context) {
    final reducedMotion = SonusTheme.of(context).motion.reduced;

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 300),
        reverseTransitionDuration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return const NowPlayingPage();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _MiniPlayerProgress extends StatelessWidget {
  const _MiniPlayerProgress({required this.state});

  final PlaybackState state;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return SizedBox(
      key: const ValueKey<String>('mini-player-progress'),
      height: 2,
      child: LinearProgressIndicator(
        value: state.duration > Duration.zero ? state.progress : 0,
        color: colors.progressActive,
        backgroundColor: colors.progressInactive,
      ),
    );
  }
}

class _MiniPlayerArtwork extends StatelessWidget {
  const _MiniPlayerArtwork({required this.track});

  final PlaybackTrack track;

  @override
  Widget build(BuildContext context) {
    final path = track.artworkPath?.trim();

    return SonusArtworkFrame(
      key: const ValueKey<String>('mini-player-artwork'),
      size: 52,
      child: path != null && path.isNotEmpty
          ? Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _MiniPlayerArtworkFallback(),
            )
          : const _MiniPlayerArtworkFallback(),
    );
  }
}

class _MiniPlayerArtworkFallback extends StatelessWidget {
  const _MiniPlayerArtworkFallback();

  @override
  Widget build(BuildContext context) {
    return const SonusArtworkPlaceholder(
      key: ValueKey<String>('mini-player-artwork-fallback'),
    );
  }
}

class _MiniPlayerMetadata extends StatelessWidget {
  const _MiniPlayerMetadata({required this.track});

  final PlaybackTrack track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = SonusTheme.of(context).colors;

    return Column(
      key: const ValueKey<String>('mini-player-metadata'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track.title,
          key: const ValueKey<String>('mini-player-title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          track.artistName,
          key: const ValueKey<String>('mini-player-artist'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _MiniPlayerPlayPauseButton extends StatelessWidget {
  const _MiniPlayerPlayPauseButton({
    required this.state,
    required this.coordinator,
  });

  final PlaybackState state;
  final PlaybackCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    final isLoading = state.status == PlaybackStatus.loading;
    final colors = SonusTheme.of(context).colors;

    return IconButton.filled(
      key: const ValueKey<String>('mini-player-play-pause'),
      style: IconButton.styleFrom(
        backgroundColor: colors.playbackControl,
        foregroundColor: colors.onPlaybackControl,
      ),
      tooltip: state.isPlaying ? 'Pause' : 'Play',
      onPressed: isLoading
          ? null
          : () {
              unawaited(coordinator.togglePlayPause());
            },
      icon: isLoading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
    );
  }
}
