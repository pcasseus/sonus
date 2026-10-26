import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_word_fit_text.dart';
import '../../application/models/library_artist.dart';

/// An Artists grid card: square artwork, the name on up to two lines and
/// the album and song counts.
class LibraryArtistCard extends StatelessWidget {
  const LibraryArtistCard({
    super.key,
    required this.artist,
    required this.onTap,
  });

  final LibraryArtist artist;
  final VoidCallback onTap;

  /// Height of the text under the artwork at a text scale of 1: two name
  /// lines and the counts. Grids scale it with the text size.
  static const double captionHeight = 84;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(tokens.metrics.cardRadius);
    final name = artist.name.trim().isEmpty ? 'Unknown Artist' : artist.name;

    return Material(
      key: ValueKey<String>('artist-${artist.artistId}'),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: colors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('artist-open-${artist.artistId}'),
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final artworkSize = constraints.maxWidth;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: artworkSize,
                  child: _ArtistArtwork(
                    artistName: name,
                    artworkPath: _artworkPath,
                    size: artworkSize,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          // A long single name shrinks rather than breaking
                          // mid-word on narrow cards at large text.
                          child: SonusWordFitText(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Large counts at large text sizes scale down to the
                        // card's width instead of overflowing it.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Row(
                            children: [
                              _ArtistStat(
                                key: ValueKey<String>(
                                  'artist-album-count-${artist.artistId}',
                                ),
                                icon: Icons.album_outlined,
                                value: '${artist.albumCount}',
                                semanticsLabel: _albumLabel,
                              ),
                              const SizedBox(width: 12),
                              _ArtistStat(
                                key: ValueKey<String>(
                                  'artist-song-count-${artist.artistId}',
                                ),
                                icon: Icons.music_note_rounded,
                                value: '${artist.songCount}',
                                semanticsLabel: _songLabel,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String? get _artworkPath {
    final topArtistsPath = artist.topArtistsArtworkPath?.trim();

    if (topArtistsPath != null && topArtistsPath.isNotEmpty) {
      return topArtistsPath;
    }

    final headerPath = artist.headerArtworkPath?.trim();

    if (headerPath != null && headerPath.isNotEmpty) {
      return headerPath;
    }

    return null;
  }

  /// Releases of every format (albums, EPs, Singles), so not "albums".
  String get _albumLabel {
    return artist.albumCount == 1
        ? '1 release'
        : '${artist.albumCount} releases';
  }

  String get _songLabel {
    return artist.songCount == 1 ? '1 song' : '${artist.songCount} songs';
  }
}

class _ArtistArtwork extends StatelessWidget {
  const _ArtistArtwork({
    required this.artistName,
    required this.artworkPath,
    required this.size,
  });

  final String artistName;
  final String? artworkPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = artworkPath;

    if (path == null) {
      return _ArtistArtworkFallback(artistName: artistName);
    }

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      // Decoded at its display size, never at full resolution, so long
      // grids scroll smoothly.
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) {
        return _ArtistArtworkFallback(artistName: artistName);
      },
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
      key: const ValueKey<String>('artist-artwork-fallback'),
      color: colors.artworkPlaceholder,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -18,
            bottom: -22,
            child: Icon(
              Icons.graphic_eq_rounded,
              size: 112,
              color: colors.onArtworkPlaceholder.withValues(alpha: 0.08),
            ),
          ),
          Center(
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _initials(artistName),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: colors.onArtworkPlaceholder,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
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
}

class _ArtistStat extends StatelessWidget {
  const _ArtistStat({
    super.key,
    required this.icon,
    required this.value,
    required this.semanticsLabel,
  });

  final IconData icon;
  final String value;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
