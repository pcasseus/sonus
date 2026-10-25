import 'package:flutter/material.dart';

import '../../sonus_artwork_palette.dart';
import '../../sonus_atmosphere_colors.dart';
import '../../sonus_theme.dart';
import '../sonus_artwork_frame.dart';
import '../sonus_artwork_image.dart';
import '../sonus_artwork_atmosphere_builder.dart';
import '../sonus_word_fit_text.dart';
import 'sonus_playback_controls.dart';
import 'sonus_playback_progress.dart';

/// The Sonus Now Playing layout (SN-48E): large artwork over the artwork's
/// atmosphere, title and artist, the theme's progress treatment, playback
/// controls, and Queue and Lyrics actions.
///
/// Presentation only. The player page supplies the values and callbacks;
/// nothing here talks to the playback engine, so integrating it is a small
/// mapping in the player feature.
class SonusNowPlayingView extends StatelessWidget {
  const SonusNowPlayingView({
    super.key,
    required this.title,
    required this.artist,
    required this.position,
    required this.duration,
    required this.isPlaying,
    this.album,
    this.artworkPath,
    this.artworkPalette,
    this.isLoading = false,
    this.shuffleEnabled = false,
    this.repeat = SonusRepeatDisplay.off,
    this.onSeek,
    this.onPlayPause,
    this.onPrevious,
    this.onNext,
    this.onToggleShuffle,
    this.onCycleRepeat,
    this.onOpenQueue,
    this.onOpenLyrics,
    this.onOpenArtist,
    this.notice,
    this.keyPrefix,
  });

  final String title;
  final String artist;
  final String? album;
  final String? artworkPath;
  final SonusArtworkPalette? artworkPalette;

  final Duration position;
  final Duration? duration;
  final bool isPlaying;
  final bool isLoading;
  final bool shuffleEnabled;
  final SonusRepeatDisplay repeat;

  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onPlayPause;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onToggleShuffle;
  final VoidCallback? onCycleRepeat;
  final VoidCallback? onOpenQueue;
  final VoidCallback? onOpenLyrics;

  /// Makes the artist line a link, when the player can open the profile.
  final VoidCallback? onOpenArtist;

  /// For example a playback error, shown directly under the song so it is
  /// seen without scrolling.
  final Widget? notice;

  /// Keys the parts `<prefix>-artwork`, `-title`, `-artist`, `-album`,
  /// `-seek`, `-elapsed`, `-queue`, `-lyrics` and the controls (see
  /// [SonusPlaybackControls.keyPrefix]). Without it the view uses its own
  /// `sonus-now-playing-*` keys.
  final String? keyPrefix;

  ValueKey<String> _key(String name) =>
      ValueKey<String>('${keyPrefix ?? 'sonus-now-playing'}-$name');

  /// Width from which artwork sits beside the controls (landscape, tablets).
  static const double wideLayoutWidth = 720;

  @override
  Widget build(BuildContext context) {
    return SonusArtworkAtmosphereBuilder(
      artworkPath: artworkPath,
      palette: artworkPalette,
      builder: (context, atmosphere) => DecoratedBox(
        key: const ValueKey<String>('sonus-now-playing-view'),
        decoration: BoxDecoration(
          gradient: atmosphere.isTinted
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [atmosphere.surface, atmosphere.background],
                )
              : null,
          color: atmosphere.isTinted ? null : atmosphere.background,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gutter = SonusTheme.of(context).metrics.pageGutter;
            final wide = constraints.maxWidth >= wideLayoutWidth;
            // System bars, or an app bar drawn over the atmosphere.
            final insets = MediaQuery.paddingOf(context);

            if (wide) {
              final artSize =
                  (constraints.maxHeight -
                          gutter * 2 -
                          insets.top -
                          insets.bottom)
                      .clamp(160.0, constraints.maxWidth * 0.42);
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  gutter + insets.left,
                  gutter + insets.top,
                  gutter + insets.right,
                  gutter + insets.bottom,
                ),
                child: Row(
                  children: [
                    _Artwork(
                      key: _key('artwork'),
                      path: artworkPath,
                      size: artSize,
                      atmosphere: atmosphere,
                    ),
                    SizedBox(width: gutter * 2),
                    Expanded(
                      child: SingleChildScrollView(
                        child: _details(context, atmosphere),
                      ),
                    ),
                  ],
                ),
              );
            }

            final artSize = [
              constraints.maxWidth - gutter * 2,
              (constraints.maxHeight - insets.top) * 0.46,
              420.0,
            ].reduce((a, b) => a < b ? a : b).clamp(120.0, 420.0);

            // Scrolls rather than clips when text is large or the screen
            // short. Content fades out as it scrolls under the app bar,
            // instead of meeting a solid slab there.
            return _TopFade(
              key: _key('top-fade'),
              fadeStart: insets.top,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  12 + insets.top,
                  gutter,
                  24 + insets.bottom,
                ),
                child: Column(
                  children: [
                    _Artwork(
                      key: _key('artwork'),
                      path: artworkPath,
                      size: artSize,
                      atmosphere: atmosphere,
                    ),
                    const SizedBox(height: 24),
                    _details(context, atmosphere),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _details(BuildContext context, SonusAtmosphereColors atmosphere) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final notice = this.notice;
    final album = this.album;
    final onOpenArtist = this.onOpenArtist;

    final artistText = Text(
      artist,
      key: _key('artist'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(
        color: onOpenArtist == null ? colors.textSecondary : atmosphere.accent,
        fontWeight: FontWeight.w600,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          // A long single word shrinks to fit instead of breaking.
          child: SonusWordFitText(
            title,
            textKey: _key('title'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: onOpenArtist == null
              ? artistText
              : InkWell(
                  onTap: onOpenArtist,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: 1,
                      child: artistText,
                    ),
                  ),
                ),
        ),
        if (album != null && album.trim().isNotEmpty)
          Text(
            album,
            key: _key('album'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        if (notice != null) ...[const SizedBox(height: 12), notice],
        const SizedBox(height: 18),
        SonusPlaybackProgress(
          key: _key('seek'),
          elapsedKey: _key('elapsed'),
          position: position,
          duration: duration,
          onSeek: onSeek,
          accentColor: atmosphere.isTinted ? atmosphere.accent : null,
        ),
        const SizedBox(height: 12),
        SonusPlaybackControls(
          isPlaying: isPlaying,
          isLoading: isLoading,
          shuffleEnabled: shuffleEnabled,
          repeat: repeat,
          onPlayPause: onPlayPause,
          onPrevious: onPrevious,
          onNext: onNext,
          onToggleShuffle: onToggleShuffle,
          onCycleRepeat: onCycleRepeat,
          accentColor: atmosphere.isTinted ? atmosphere.accent : null,
          onAccentColor: atmosphere.isTinted ? atmosphere.onAccent : null,
          keyPrefix: keyPrefix,
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: 12,
          runSpacing: 8,
          children: [
            TextButton.icon(
              key: _key('queue'),
              onPressed: onOpenQueue,
              icon: const Icon(Icons.queue_music_rounded),
              label: const Text('Queue'),
            ),
            TextButton.icon(
              key: _key('lyrics'),
              onPressed: onOpenLyrics,
              icon: const Icon(Icons.lyrics_outlined),
              label: const Text('Lyrics'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    super.key,
    required this.path,
    required this.size,
    required this.atmosphere,
  });

  final String? path;
  final double size;
  final SonusAtmosphereColors atmosphere;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final glow = atmosphere.isTinted && tokens.decoration.allowGlow;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.metrics.artworkRadius),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: atmosphere.accent.withValues(alpha: 0.32),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: path == null || path!.trim().isEmpty
          ? SonusArtworkFrame(
              size: size,
              child: ColoredBox(
                color: tokens.colors.artworkPlaceholder,
                child: Icon(
                  Icons.music_note_rounded,
                  size: size * 0.4,
                  color: tokens.colors.onArtworkPlaceholder,
                ),
              ),
            )
          : SonusArtworkImage(path: path, size: size),
    );
  }
}

/// Fades content out as it scrolls up past [fadeStart] (the app bar's lower
/// edge), so it dissolves under a transparent app bar. Nothing is faded at
/// rest, because the content starts below that edge.
class _TopFade extends StatelessWidget {
  const _TopFade({super.key, required this.fadeStart, required this.child});

  final double fadeStart;
  final Widget child;

  static const double _fadeLength = 28;

  @override
  Widget build(BuildContext context) {
    if (fadeStart <= 0) return child;

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final height = bounds.height <= 0 ? 1.0 : bounds.height;
        // Fully faded a little above the bar's edge, fully shown from the
        // edge down, so content at rest (which starts below it) is never
        // touched.
        final end = (fadeStart / height).clamp(0.0, 1.0);
        final start = ((fadeStart - _fadeLength) / height).clamp(0.0, end);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, start, end, 1],
          colors: const [
            Color(0x00000000),
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
          ],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}
