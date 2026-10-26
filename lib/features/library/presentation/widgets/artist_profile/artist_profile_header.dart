import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_atmosphere_colors.dart';
import '../../../../../core/design/sonus_count_label.dart';
import '../../../../../core/design/sonus_theme.dart';
import '../../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../application/models/library_artist.dart';
import '../../models/artist_profile_sections.dart';

/// The cinematic artist hero (SN-45): a full-bleed banner photo that fades
/// into the page, with the artist's name over its lower edge and a smaller,
/// separate portrait anchored at the transition.
///
/// Banner and portrait are different saved images. Without a banner, the
/// page's atmosphere fills the hero; without a portrait, initials are
/// shown. Neither ever stands in for the other.
class ArtistProfileHeader extends StatelessWidget {
  const ArtistProfileHeader({
    super.key,
    required this.artist,
    required this.bannerPath,
    required this.portraitPath,
    required this.atmosphere,
    this.standing,
    this.summary,
  });

  final LibraryArtist artist;
  final String? bannerPath;
  final String? portraitPath;
  final SonusAtmosphereColors atmosphere;
  final ArtistStanding? standing;

  /// The line under the name; the artist's album and song counts if null.
  final String? summary;

  /// The banner's shape, as the banner crop editor frames it.
  static const double bannerAspectRatio = 4 / 3;

  static const double _portraitSize = 88;

  /// The photo's height: the banner's shape at this width, but never more
  /// than about half the screen, so the catalog starts on the first screen.
  static double imageHeightFor(BuildContext context, double width) {
    final screen = MediaQuery.sizeOf(context).height;
    final cap = screen <= 0 ? 440.0 : (screen * 0.46).clamp(220.0, 440.0);
    return (width / bannerAspectRatio).clamp(220.0, cap);
  }

  /// How far the page scrolls before the hero's name has gone under the
  /// toolbar, so the toolbar may show a compact title instead.
  static double collapseOffset(
    BuildContext context, {
    required double width,
    required bool hasBanner,
  }) {
    final imageHeight = hasBanner
        ? imageHeightFor(context, width)
        : MediaQuery.paddingOf(context).top + 168.0;
    return imageHeight -
        MediaQuery.paddingOf(context).top -
        kToolbarHeight +
        _portraitSize / 2;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final gutter = tokens.metrics.pageGutter;
    final topInset = MediaQuery.paddingOf(context).top;
    final banner = bannerPath?.trim();
    final hasBanner = banner != null && banner.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final imageHeight = hasBanner
            ? imageHeightFor(context, width)
            : topInset + 168.0;

        return Stack(
          key: const ValueKey<String>('artist-profile-hero'),
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                SizedBox(
                  height: imageHeight,
                  width: double.infinity,
                  child: hasBanner
                      ? _Banner(
                          path: banner,
                          artistId: artist.artistId,
                          width: width,
                        )
                      : _AtmosphereBackdrop(atmosphere: atmosphere),
                ),
                // Room for the identity row below the photo's edge.
                const SizedBox(height: _portraitSize / 2 + 8),
              ],
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: _Fades(
                  atmosphere: atmosphere,
                  topInset: topInset,
                  imageHeight: imageHeight,
                ),
              ),
            ),
            Positioned(
              left: gutter,
              right: gutter,
              bottom: 0,
              child: _Identity(
                artist: artist,
                portraitPath: portraitPath,
                standing: standing,
                summary: summary,
                atmosphere: atmosphere,
                portraitSize: _portraitSize,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.path,
    required this.artistId,
    required this.width,
  });

  final String path;
  final String artistId;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context)).round();

    return Image.file(
      File(path),
      key: ValueKey<String>('artist-profile-banner-$artistId'),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) =>
          const SizedBox.expand(key: ValueKey('artist-profile-banner-error')),
    );
  }
}

class _AtmosphereBackdrop extends StatelessWidget {
  const _AtmosphereBackdrop({required this.atmosphere});

  final SonusAtmosphereColors atmosphere;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey<String>('artist-profile-banner-fallback'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              atmosphere.accent.withValues(alpha: 0.28),
              atmosphere.surface,
            ),
            atmosphere.background,
          ],
        ),
      ),
    );
  }
}

/// A light scrim under the status and app bars, and the long fade from
/// the photo into the page, so there is no edge and no black block.
class _Fades extends StatelessWidget {
  const _Fades({
    required this.atmosphere,
    required this.topInset,
    required this.imageHeight,
  });

  final SonusAtmosphereColors atmosphere;
  final double topInset;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    final background = atmosphere.background;

    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxHeight <= 0 ? 1.0 : constraints.maxHeight;
        final imageEnd = (imageHeight / total).clamp(0.0, 1.0);
        final fadeStart = (imageEnd * 0.42).clamp(0.0, imageEnd);
        final scrimEnd = ((topInset + kToolbarHeight) / total).clamp(
          0.0,
          fadeStart,
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, scrimEnd, fadeStart, imageEnd, 1],
              colors: [
                Colors.black.withValues(alpha: 0.38),
                Colors.black.withValues(alpha: 0),
                background.withValues(alpha: 0),
                background,
                background,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.artist,
    required this.portraitPath,
    required this.standing,
    required this.summary,
    required this.atmosphere,
    required this.portraitSize,
  });

  final LibraryArtist artist;
  final String? portraitPath;
  final ArtistStanding? standing;
  final String? summary;
  final SonusAtmosphereColors atmosphere;
  final double portraitSize;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final standing = this.standing;
    const shadow = [ui.Shadow(blurRadius: 12, color: Color(0x66000000))];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _Portrait(
          artist: artist,
          path: portraitPath,
          size: portraitSize,
          ring: atmosphere.background,
          glow: atmosphere.isTinted && tokens.decoration.allowGlow
              ? atmosphere.accent
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                artist.name,
                key: ValueKey<String>('artist-profile-name-${artist.artistId}'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  shadows: shadow,
                ),
              ),
              const SizedBox(height: 6),
              if (standing != null)
                Text(
                  '#${standing.rank} in your artists, all time · '
                  '${sonusCount(standing.streamCount, 'stream')}',
                  key: const ValueKey<String>('artist-profile-standing'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    shadows: shadow,
                  ),
                ),
              Text(
                summary ??
                    '${sonusCount(artist.albumCount, 'album')} • '
                        '${sonusCount(artist.songCount, 'song')}',
                key: const ValueKey<String>('artist-profile-summary'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({
    required this.artist,
    required this.path,
    required this.size,
    required this.ring,
    this.glow,
  });

  final LibraryArtist artist;
  final String? path;
  final double size;
  final Color ring;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    final glow = this.glow;
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 3),
        boxShadow: glow == null
            ? null
            : [BoxShadow(color: glow.withValues(alpha: 0.32), blurRadius: 24)],
      ),
      child: SonusArtworkFrame(
        size: size,
        circular: true,
        child: path == null
            ? _ArtistArtworkFallback(artistName: artist.name)
            : Image.file(
                File(path),
                key: ValueKey<String>(
                  'artist-profile-artwork-${artist.artistId}',
                ),
                fit: BoxFit.cover,
                cacheWidth: cacheSize,
                gaplessPlayback: true,
                semanticLabel: artist.name,
                errorBuilder: (context, error, stackTrace) {
                  return _ArtistArtworkFallback(artistName: artist.name);
                },
              ),
      ),
    );
  }
}

class _ArtistArtworkFallback extends StatelessWidget {
  const _ArtistArtworkFallback({required this.artistName});

  final String artistName;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return ColoredBox(
      key: const ValueKey<String>('artist-profile-artwork-fallback'),
      color: colors.artworkPlaceholder,
      child: Center(
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              artistInitials(artistName),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.onArtworkPlaceholder,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One or two initials for an artist without a portrait.
String artistInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();

  if (parts.isEmpty) {
    return '?';
  }

  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }

  return '${parts.first.substring(0, 1)}'
          '${parts.last.substring(0, 1)}'
      .toUpperCase();
}
