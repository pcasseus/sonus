import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_atmosphere_colors.dart';
import '../../../../../core/design/sonus_theme.dart';
import '../../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../application/models/library_artist.dart';

/// Portrait, name and catalogue summary, on a background that flows from
/// the artwork's tint into the page.
class ArtistProfileHeader extends StatelessWidget {
  const ArtistProfileHeader({
    super.key,
    required this.artist,
    required this.artworkPath,
    required this.atmosphere,
  });

  final LibraryArtist artist;
  final String? artworkPath;
  final SonusAtmosphereColors atmosphere;

  /// Page width from which the portrait sits beside the name (landscape and
  /// tablets), keeping the sections below in view.
  static const double wideLayoutWidth = 560;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return DecoratedBox(
      key: const ValueKey<String>('artist-profile-hero'),
      decoration: BoxDecoration(
        // Both ends keep text readable (the atmosphere guarantees it), so
        // every blend between them does too.
        gradient: atmosphere.isTinted
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [atmosphere.surface, atmosphere.background],
              )
            : null,
        color: atmosphere.isTinted ? null : atmosphere.background,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.metrics.pageGutter,
          12,
          tokens.metrics.pageGutter,
          20,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final glow = atmosphere.isTinted && tokens.decoration.allowGlow
                ? atmosphere.accent
                : null;

            if (constraints.maxWidth >= wideLayoutWidth) {
              final size = (constraints.maxWidth * 0.28).clamp(128.0, 200.0);
              return Row(
                children: [
                  _ArtistPortrait(
                    artist: artist,
                    artworkPath: artworkPath,
                    size: size,
                    glow: glow,
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: _details(context, centered: false)),
                ],
              );
            }

            final size = (constraints.maxWidth * 0.5).clamp(112.0, 200.0);
            return Column(
              children: [
                _ArtistPortrait(
                  artist: artist,
                  artworkPath: artworkPath,
                  size: size,
                  glow: glow,
                ),
                const SizedBox(height: 18),
                _details(context, centered: true),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _details(BuildContext context, {required bool centered}) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final align = centered ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          artist.name,
          key: ValueKey<String>('artist-profile-name-${artist.artistId}'),
          textAlign: align,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        // Plain wrapping text: the counts can never push past the hero,
        // whatever the width or text size.
        Text(
          _summary(artist),
          key: const ValueKey<String>('artist-profile-summary'),
          textAlign: align,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  String _summary(LibraryArtist artist) {
    final albumLabel = artist.albumCount == 1 ? 'album' : 'albums';
    final songLabel = artist.songCount == 1 ? 'song' : 'songs';

    return '${artist.albumCount} $albumLabel • '
        '${artist.songCount} $songLabel';
  }
}

class _ArtistPortrait extends StatelessWidget {
  const _ArtistPortrait({
    required this.artist,
    required this.artworkPath,
    required this.size,
    this.glow,
  });

  final LibraryArtist artist;
  final String? artworkPath;
  final double size;

  /// A soft glow in the artwork's accent, only with decoration effects on.
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final path = artworkPath?.trim();
    final glow = this.glow;
    // Decoded at its display size, never at the image's full resolution.
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: glow == null
            ? null
            : [
                BoxShadow(
                  color: glow.withValues(alpha: 0.32),
                  blurRadius: 36,
                  spreadRadius: 2,
                ),
              ],
      ),
      child: SonusArtworkFrame(
        size: size,
        circular: true,
        child: path == null || path.isEmpty
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
