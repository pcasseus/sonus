import 'dart:io';

import 'package:flutter/material.dart';

import '../../../application/models/library_artist.dart';

class ArtistProfileHeader extends StatelessWidget {
  const ArtistProfileHeader({
    super.key,
    required this.artist,
    required this.artworkPath,
  });

  final LibraryArtist artist;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: SizedBox(
        height: 200,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ArtistHeroArtwork(artist: artist, artworkPath: artworkPath),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.82),
                  ],
                  stops: const [0.0, 0.48, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 22,
              right: 22,
              bottom: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    key: ValueKey<String>(
                      'artist-profile-name-${artist.artistId}',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MetadataPill(
                    icon: Icons.library_music_rounded,
                    label: _summary(artist),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Icon(
                Icons.graphic_eq_rounded,
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.75),
                size: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _summary(LibraryArtist artist) {
    final albumLabel = artist.albumCount == 1 ? 'album' : 'albums';
    final songLabel = artist.songCount == 1 ? 'song' : 'songs';

    return '${artist.albumCount} $albumLabel • '
        '${artist.songCount} $songLabel';
  }
}

class _ArtistHeroArtwork extends StatelessWidget {
  const _ArtistHeroArtwork({required this.artist, required this.artworkPath});

  final LibraryArtist artist;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    final path = artworkPath?.trim();

    if (path == null || path.isEmpty) {
      return _ArtistArtworkFallback(artistName: artist.name);
    }

    return SizedBox.expand(
      key: ValueKey<String>('artist-profile-artwork-${artist.artistId}'),
      child: Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _ArtistArtworkFallback(artistName: artist.name);
        },
      ),
    );
  }
}

class _ArtistArtworkFallback extends StatelessWidget {
  const _ArtistArtworkFallback({required this.artistName});

  final String artistName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      key: const ValueKey<String>('artist-profile-artwork-fallback'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Center(
        child: Text(
          _initials(artistName),
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onPrimaryContainer.withValues(alpha: 0.45),
          ),
        ),
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

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.9)),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
