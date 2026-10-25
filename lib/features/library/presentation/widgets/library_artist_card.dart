import 'dart:io';

import 'package:flutter/material.dart';

import '../../application/models/library_artist.dart';

class LibraryArtistCard extends StatelessWidget {
  const LibraryArtistCard({
    super.key,
    required this.artist,
    required this.onTap,
  });

  final LibraryArtist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artworkPath = _artworkPath;

    return Material(
      key: ValueKey<String>('artist-${artist.artistId}'),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('artist-open-${artist.artistId}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ArtistArtwork(
                  artistName: artist.name,
                  artworkPath: artworkPath,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist.name.trim().isEmpty
                          ? 'Unknown Artist'
                          : artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 9),
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
            ],
          ),
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

  String get _albumLabel {
    return artist.albumCount == 1 ? '1 album' : '${artist.albumCount} albums';
  }

  String get _songLabel {
    return artist.songCount == 1 ? '1 song' : '${artist.songCount} songs';
  }
}

class _ArtistArtwork extends StatelessWidget {
  const _ArtistArtwork({required this.artistName, required this.artworkPath});

  final String artistName;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    final path = artworkPath;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SizedBox.expand(
        child: path == null
            ? _ArtistArtworkFallback(artistName: artistName)
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _ArtistArtworkFallback(artistName: artistName);
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
    final theme = Theme.of(context);

    return DecoratedBox(
      key: const ValueKey<String>('artist-artwork-fallback'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.surfaceContainer,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -18,
            bottom: -22,
            child: Icon(
              Icons.graphic_eq_rounded,
              size: 112,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.045),
            ),
          ),
          Center(
            child: Text(
              _initials(artistName),
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
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
    final theme = Theme.of(context);

    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
