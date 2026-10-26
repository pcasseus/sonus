import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../sonus_atmosphere_colors.dart';
import '../../sonus_theme.dart';
import '../sonus_artwork_atmosphere_builder.dart';
import '../sonus_artwork_image.dart';

/// The universal mini-player surface (SN-48E, refined in SN-45): a light,
/// softly rounded bar tinted by the artwork's atmosphere, with artwork,
/// title and artist, a thin progress line and Previous, Play or pause and
/// Next.
///
/// Presentation only. One shared application-level host (the playback
/// host below every route) places it once; this widget never decides where
/// it appears.
///
/// - Tapping the body opens Now Playing; swiping the bar up does too
///   ([onSwipeUp]), as an optional shortcut.
/// - Previous, Play or pause and Next are always shown. A control is
///   disabled, not hidden, at a real queue boundary. Queue joins them when
///   the bar is at least [fullControlsWidth] wide.
/// - When [onDismiss] is given (only while paused), a deliberate sideways
///   swipe closes the player. Without it, a sideways drag only springs
///   back, so it can never stop music.
///
/// The bar is [height] tall at normal text sizes and grows with large
/// text, so both lines stay readable; pages reserve exactly the same space
/// with [SonusMiniPlayer.reservedHeight].
class SonusMiniPlayer extends StatelessWidget {
  const SonusMiniPlayer({
    super.key,
    required this.title,
    required this.artist,
    required this.isPlaying,
    this.artworkPath,
    this.artwork,
    this.status,
    this.progress,
    this.isLoading = false,
    this.onPlayPause,
    this.onNext,
    this.onPrevious,
    this.onOpenQueue,
    this.onOpen,
    this.onSwipeUp,
    this.onDismiss,
    this.accentColor,
    this.keyPrefix = 'sonus-mini-player',
  });

  final String title;
  final String artist;
  final String? artworkPath;

  /// Replaces the artwork drawn from [artworkPath], for hosts with their
  /// own artwork widget.
  final Widget? artwork;

  /// Shown instead of [artist], for example a playback error.
  final Widget? status;
  final bool isPlaying;
  final bool isLoading;

  /// 0 to 1; null while the length is unknown (no line is drawn).
  final double? progress;
  final VoidCallback? onPlayPause;

  /// Null disables the button (the end of the queue).
  final VoidCallback? onNext;

  /// Null disables the button (the start of the queue).
  final VoidCallback? onPrevious;

  /// Shown on wide bars only, when given.
  final VoidCallback? onOpenQueue;
  final VoidCallback? onOpen;

  /// Called by an upward swipe on the bar.
  final VoidCallback? onSwipeUp;

  /// Closes the player after a deliberate sideways swipe. The host passes
  /// it only while playback is paused.
  final VoidCallback? onDismiss;

  /// Artwork accent from the host; the artwork atmosphere by default.
  final Color? accentColor;

  /// Prefix of every key: the bar itself, then `-open`, `-title`,
  /// `-artist`, `-play-pause`, `-next`, `-previous`, `-queue`,
  /// `-progress` and `-swipe`.
  final String keyPrefix;

  /// Bar height at normal text sizes.
  static const double height = 64;
  static const double _margin = 8;

  /// Bar width from which Queue is shown beside the transport controls.
  static const double fullControlsWidth = 380;

  /// An upward fling faster than this (logical pixels a second) opens Now
  /// Playing.
  static const double swipeUpVelocity = 300;

  /// The bar's height at the current text size: two lines of text plus
  /// padding, never less than [height].
  static double barHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final text = scaler.scale(14) * 1.45 + scaler.scale(12) * 1.45 + 16;
    return text > height ? text : height;
  }

  /// Space a page should leave at its bottom so the bar never covers it.
  static double reservedHeight(BuildContext context) =>
      barHeight(context) + _margin * 2 + MediaQuery.paddingOf(context).bottom;

  ValueKey<String> _key(String name) => ValueKey<String>('$keyPrefix-$name');

  @override
  Widget build(BuildContext context) {
    final onDismiss = this.onDismiss;
    final onOpen = this.onOpen;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(_margin, 6, _margin, _margin),
      child: Semantics(
        container: true,
        label: 'Now playing',
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Open Now Playing'): ?onOpen,
          const CustomSemanticsAction(label: 'Close player'): ?onDismiss,
        },
        child: _SwipeSurface(
          key: _key('swipe'),
          onSwipeUp: onSwipeUp,
          onDismiss: onDismiss,
          child: SonusArtworkAtmosphereBuilder(
            artworkPath: artworkPath,
            builder: (context, atmosphere) => _bar(context, atmosphere),
          ),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, SonusAtmosphereColors atmosphere) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    // The artwork's accent once its colours are known; until then (and
    // without artwork) the theme's own playback tokens.
    final accent =
        accentColor ??
        (atmosphere.isTinted ? atmosphere.accent : colors.playbackControl);
    final progressColor =
        accentColor ??
        (atmosphere.isTinted ? atmosphere.accent : colors.progressActive);
    final progress = this.progress;
    final radius = BorderRadius.circular(tokens.metrics.cardRadius);
    final status = this.status;
    final onOpenQueue = this.onOpenQueue;
    final lowEffects = !tokens.decoration.allowGlow;

    // A light surface tinted by the artwork, instead of a heavy opaque
    // slab. The atmosphere already falls back to the theme's own colours
    // for Decoration Off, High contrast and Low effects.
    final surface = atmosphere.isTinted
        ? Color.alphaBlend(
            atmosphere.surface.withValues(alpha: 0.9),
            colors.background,
          )
        : colors.surface;

    const buttonSize = BoxConstraints(minWidth: 48, minHeight: 48);

    return Material(
      key: ValueKey<String>(keyPrefix),
      color: surface,
      elevation: lowEffects ? 0 : 2,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: colors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: barHeight(context),
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final full = constraints.maxWidth >= fullControlsWidth;

                return Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        key: _key('open'),
                        onTap: onOpen,
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child:
                                  artwork ??
                                  SonusArtworkImage(
                                    path: artworkPath,
                                    size: 44,
                                  ),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    key: _key('title'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  status ??
                                      Text(
                                        artist,
                                        key: _key('artist'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: colors.textSecondary,
                                            ),
                                      ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      key: _key('previous'),
                      tooltip: 'Previous',
                      onPressed: onPrevious,
                      constraints: buttonSize,
                      color: colors.textPrimary,
                      icon: const Icon(Icons.skip_previous_rounded, size: 28),
                    ),
                    IconButton(
                      key: _key('play-pause'),
                      tooltip: isPlaying ? 'Pause' : 'Play',
                      onPressed: isLoading ? null : onPlayPause,
                      constraints: buttonSize,
                      color: accent,
                      icon: isLoading
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 30,
                            ),
                    ),
                    IconButton(
                      key: _key('next'),
                      tooltip: 'Next',
                      onPressed: onNext,
                      constraints: buttonSize,
                      color: colors.textPrimary,
                      icon: const Icon(Icons.skip_next_rounded, size: 28),
                    ),
                    if (full && onOpenQueue != null)
                      IconButton(
                        key: _key('queue'),
                        tooltip: 'Queue',
                        onPressed: onOpenQueue,
                        constraints: buttonSize,
                        color: colors.textSecondary,
                        icon: const Icon(Icons.queue_music_rounded),
                      ),
                    const SizedBox(width: 4),
                  ],
                );
              },
            ),
            if (progress != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 0,
                child: ExcludeSemantics(
                  key: _key('progress'),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 2,
                      color: progressColor,
                      backgroundColor: colors.progressInactive,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Upward swipes open; deliberate sideways swipes dismiss, but only when
/// [onDismiss] is set. Otherwise a sideways drag springs back.
class _SwipeSurface extends StatefulWidget {
  const _SwipeSurface({
    super.key,
    required this.child,
    this.onSwipeUp,
    this.onDismiss,
  });

  final Widget child;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onDismiss;

  /// How far (as a share of the bar's width) or how fast a release must be
  /// to dismiss.
  static const double dismissFraction = 0.4;
  static const double dismissVelocity = 900;

  @override
  State<_SwipeSurface> createState() => _SwipeSurfaceState();
}

class _SwipeSurfaceState extends State<_SwipeSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  double _width = 1;
  bool _dismissed = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  bool get _canDismiss => widget.onDismiss != null;

  Duration get _duration {
    final tokens = SonusTheme.of(context);
    return tokens.motion.reduced || MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (_dismissed) return;
    // Without a dismissal there is only a little give, so it reads as
    // "this does nothing now".
    final delta = _canDismiss ? details.delta.dx : details.delta.dx * 0.15;
    _offset.value = (_offset.value + delta).clamp(-_width, _width);
  }

  Future<void> _dragEnd(DragEndDetails details) async {
    if (_dismissed) return;
    final velocity = details.primaryVelocity ?? 0;
    final far =
        _offset.value.abs() >= _width * _SwipeSurface.dismissFraction ||
        velocity.abs() >= _SwipeSurface.dismissVelocity;
    final onDismiss = widget.onDismiss;

    if (onDismiss != null && far) {
      _dismissed = true;
      final direction = _offset.value != 0 ? _offset.value.sign : velocity.sign;
      await _offset.animateTo(
        direction * _width,
        duration: _duration,
        curve: Curves.easeOutCubic,
      );
      onDismiss();
      return;
    }

    await _offset.animateTo(0, duration: _duration, curve: Curves.easeOut);
  }

  @override
  void didUpdateWidget(covariant _SwipeSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the session did not end (playback resumed meanwhile), the bar
    // comes back.
    if (_dismissed && widget.onDismiss == null) {
      _dismissed = false;
      _offset.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth.isFinite ? constraints.maxWidth : 400;
        final onSwipeUp = widget.onSwipeUp;

        return GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onHorizontalDragUpdate: _dragUpdate,
          onHorizontalDragEnd: _dragEnd,
          onVerticalDragEnd: onSwipeUp == null
              ? null
              : (details) {
                  if ((details.primaryVelocity ?? 0) <
                      -SonusMiniPlayer.swipeUpVelocity) {
                    onSwipeUp();
                  }
                },
          child: AnimatedBuilder(
            animation: _offset,
            builder: (context, child) => Opacity(
              opacity: (1 - (_offset.value.abs() / _width) * 0.7).clamp(
                0.0,
                1.0,
              ),
              child: Transform.translate(
                offset: Offset(_offset.value, 0),
                child: child,
              ),
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}
