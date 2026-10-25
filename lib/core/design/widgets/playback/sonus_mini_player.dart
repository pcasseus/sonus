import 'package:flutter/material.dart';

import '../../sonus_theme.dart';
import '../sonus_artwork_image.dart';

/// The universal mini-player surface (SN-48E): a compact, softly rounded
/// bar with artwork, title and artist, a thin progress line and play,
/// pause and next controls.
///
/// Presentation only. One shared application-level host (the shell's
/// playback slot) is meant to place it once above every route; this widget
/// never decides where it appears. Tapping the body opens Now Playing.
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
    this.progress,
    this.isLoading = false,
    this.onPlayPause,
    this.onNext,
    this.onOpen,
    this.accentColor,
  });

  final String title;
  final String artist;
  final String? artworkPath;
  final bool isPlaying;
  final bool isLoading;

  /// 0 to 1; null while the length is unknown (no line is drawn).
  final double? progress;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onOpen;

  /// Artwork accent from the host; the theme's playback colour by default.
  final Color? accentColor;

  /// Bar height at normal text sizes.
  static const double height = 64;
  static const double _margin = 8;

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

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final accent = accentColor ?? colors.playbackControl;
    final progress = this.progress;
    final radius = BorderRadius.circular(tokens.metrics.cardRadius);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(_margin, _margin, _margin, _margin),
      child: Semantics(
        container: true,
        label: 'Now playing',
        child: Material(
          key: const ValueKey<String>('sonus-mini-player'),
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
            child: Stack(
              children: [
                InkWell(
                  key: const ValueKey<String>('sonus-mini-player-open'),
                  onTap: onOpen,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: SonusArtworkImage(path: artworkPath, size: 48),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey<String>(
                          'sonus-mini-player-play-pause',
                        ),
                        tooltip: isPlaying ? 'Pause' : 'Play',
                        onPressed: isLoading ? null : onPlayPause,
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
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
                        key: const ValueKey<String>('sonus-mini-player-next'),
                        tooltip: 'Next',
                        onPressed: onNext,
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        color: colors.textPrimary,
                        icon: const Icon(Icons.skip_next_rounded, size: 28),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                if (progress != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ExcludeSemantics(
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 2,
                        color: accent,
                        backgroundColor: colors.progressInactive,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
