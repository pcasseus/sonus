import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/playback/sonus_mini_player.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/models/playback_track.dart';
import '../../../player/presentation/controllers/playback_state_controller.dart';
import '../../../player/presentation/pages/now_playing_page.dart';
import '../../../player/presentation/pages/playback_queue_page.dart';
import '../../../player/presentation/widgets/playback_error_notice.dart';
import 'playback_host.dart';

/// The playback host's bar: the Sonus mini-player, fed by the playback
/// state and driving the coordinator.
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

    // The host lays the bar out below the routes, so its margins show the
    // page background rather than the bare window.
    return Material(
      key: const ValueKey<String>('shell-playback-slot'),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: track == null
          ? const SafeArea(
              top: false,
              child: SizedBox.shrink(
                key: ValueKey<String>('mini-player-empty'),
              ),
            )
          : _MiniPlayer(
              state: state,
              track: track,
              coordinator: context.read<PlaybackCoordinator>(),
            ),
    );
  }
}

/// The root navigator when the bar is in the playback host (outside any
/// route), otherwise the nearest one.
NavigatorState _navigator(BuildContext context) =>
    PlaybackHost.navigatorOf(context) ?? Navigator.of(context);

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
    final path = track.artworkPath?.trim();
    final hasArtwork = path != null && path.isNotEmpty;

    return Semantics(
      container: true,
      label: 'Now playing ${track.title} by ${track.artistName}',
      child: SonusMiniPlayer(
        keyPrefix: 'mini-player',
        title: track.title,
        artist: track.artistName,
        artworkPath: hasArtwork ? path : null,
        artwork: hasArtwork
            ? null
            : const SonusArtworkFrame(
                key: ValueKey<String>('mini-player-artwork'),
                size: 48,
                child: SonusArtworkPlaceholder(
                  key: ValueKey<String>('mini-player-artwork-fallback'),
                ),
              ),
        status: state.hasError
            ? const PlaybackErrorNotice(
                key: ValueKey<String>('mini-player-error'),
                message: PlaybackErrorNotice.shortMessage,
                compact: true,
              )
            : null,
        isPlaying: state.isPlaying,
        isLoading: state.status == PlaybackStatus.loading,
        // No line while the length is unknown.
        progress: state.duration > Duration.zero ? state.progress : null,
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
        onOpenQueue: () {
          _navigator(context).push(
            MaterialPageRoute<void>(builder: (_) => const PlaybackQueuePage()),
          );
        },
        onOpen: () => _openNowPlaying(context),
      ),
    );
  }

  void _openNowPlaying(BuildContext context) {
    final reducedMotion = SonusTheme.of(context).motion.reduced;

    _navigator(context).push(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: NowPlayingPage.routeName),
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
