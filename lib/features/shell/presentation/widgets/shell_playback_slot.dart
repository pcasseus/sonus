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
        onOpen: () => openNowPlaying(context),
        onSwipeUp: () => openNowPlaying(context),
        // A sideways swipe closes the player only while paused, so music
        // that is playing can never be stopped by accident.
        onDismiss: state.isPlaying || state.status == PlaybackStatus.loading
            ? null
            : () {
                unawaited(coordinator.dismissPausedSession());
              },
      ),
    );
  }
}

/// Opens Now Playing from the mini-player (tap or swipe up).
///
/// There is only ever one: a second tap, or a tap and a swipe together,
/// while it is opening or open does nothing. Now Playing rises from the
/// bar while the bar folds away underneath (see PlaybackHost), so there is
/// no second player surface and the page behind never jumps. With reduced
/// motion it simply appears.
void openNowPlaying(BuildContext context) {
  final routes = PlaybackHost.routesOf(context);

  if (routes != null && routes.hasNowPlaying) {
    return;
  }

  final tokens = SonusTheme.of(context);
  final reducedMotion =
      tokens.motion.reduced || MediaQuery.disableAnimationsOf(context);
  const duration = Duration(milliseconds: 320);

  _navigator(context).push(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: NowPlayingPage.routeName),
      transitionDuration: reducedMotion ? Duration.zero : duration,
      reverseTransitionDuration: reducedMotion ? Duration.zero : duration,
      pageBuilder: (context, animation, secondaryAnimation) {
        return const NowPlayingPage();
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        // Rises from where the bar is; the fade only covers the first
        // part, so the page is opaque well before it settles and no band
        // of the page behind shows through.
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.35),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: const Interval(0, 0.45, curve: Curves.easeOut),
            ),
            child: child,
          ),
        );
      },
    ),
  );
}
