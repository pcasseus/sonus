import 'package:flutter/material.dart';

import '../../sonus_theme.dart';
import '../sonus_artwork_image.dart';

/// The universal mini-player surface (SN-48E): a compact, softly rounded
/// bar with artwork, title and artist, a thin progress line and playback
/// controls.
///
/// Presentation only. One shared application-level host (the playback
/// host below every route) places it once; this widget never decides where
/// it appears. Tapping the body opens Now Playing.
///
/// Play or pause and Next are always shown. Previous and Queue join them
/// when the bar is at least [fullControlsWidth] wide, so narrow phones keep
/// room for the song; both stay one tap away on Now Playing.
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
  final VoidCallback? onNext;

  /// Shown on wide bars only; null disables the button.
  final VoidCallback? onPrevious;

  /// Shown on wide bars only, when given.
  final VoidCallback? onOpenQueue;
  final VoidCallback? onOpen;

  /// Artwork accent from the host; the theme's playback colour by default.
  final Color? accentColor;

  /// Prefix of every key: the bar itself, then `-open`, `-title`,
  /// `-artist`, `-play-pause`, `-next`, `-previous`, `-queue` and
  /// `-progress`.
  final String keyPrefix;

  /// Bar height at normal text sizes.
  static const double height = 64;
  static const double _margin = 8;

  /// Bar width from which Previous and Queue are shown.
  static const double fullControlsWidth = 380;

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
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final accent = accentColor ?? colors.playbackControl;
    final progress = this.progress;
    final radius = BorderRadius.circular(tokens.metrics.cardRadius);
    final status = this.status;
    final onOpenQueue = this.onOpenQueue;

    const buttonSize = BoxConstraints(minWidth: 48, minHeight: 48);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(_margin, _margin, _margin, _margin),
      child: Semantics(
        container: true,
        label: 'Now playing',
        child: Material(
          key: ValueKey<String>(keyPrefix),
          color: colors.raisedSurface,
          // Restrained depth: a soft shadow only while effects are allowed.
          elevation: tokens.decoration.allowGlow ? 6 : 0,
          shadowColor: Colors.black.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: colors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: barHeight(context),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final full = constraints.maxWidth >= fullControlsWidth;

                return Stack(
                  children: [
                    Row(
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
                                        size: 48,
                                      ),
                                ),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        key: _key('title'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
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
                        if (full)
                          IconButton(
                            key: _key('previous'),
                            tooltip: 'Previous',
                            onPressed: onPrevious,
                            constraints: buttonSize,
                            color: colors.textPrimary,
                            icon: const Icon(
                              Icons.skip_previous_rounded,
                              size: 28,
                            ),
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
                    ),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ExcludeSemantics(
                          key: _key('progress'),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            minHeight: 2,
                            color: accentColor ?? colors.progressActive,
                            backgroundColor: colors.progressInactive,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
