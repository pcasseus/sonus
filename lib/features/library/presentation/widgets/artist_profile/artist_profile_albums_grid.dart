import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../application/models/library_album.dart';

class ArtistProfileAlbumsGrid extends StatelessWidget {
  const ArtistProfileAlbumsGrid({
    super.key,
    required this.albums,
    required this.onAlbumTap,
    this.labelOf,
  });

  final List<LibraryAlbum> albums;
  final ValueChanged<LibraryAlbum> onAlbumTap;

  /// A word shown before the track count, such as a live release's
  /// format ("EP · 3 tracks"). Null shows the count alone.
  final String? Function(LibraryAlbum album)? labelOf;

  /// Narrowest a cover gets before the grid drops a column.
  static const double _minTileWidth = 140;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const _EmptySection(message: 'No albums yet');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        final columns =
            ((constraints.maxWidth + spacing) / (_minTileWidth + spacing))
                .floor()
                .clamp(1, 4);
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        // Room under each cover for the title and summary at any text size.
        final captionHeight = MediaQuery.textScalerOf(context).scale(48);

        return GridView.builder(
          key: const ValueKey<String>('artist-profile-albums-grid'),
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: 18,
            mainAxisExtent: tileWidth + 10 + captionHeight,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];

            return _AlbumCard(
              key: ValueKey<String>('artist-album-${album.albumId}'),
              album: album,
              label: labelOf?.call(album),
              artworkSize: tileWidth,
              onTap: () => onAlbumTap(album),
            );
          },
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    super.key,
    required this.album,
    required this.artworkSize,
    required this.onTap,
    this.label,
  });

  final LibraryAlbum album;
  final String? label;
  final double artworkSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SonusTheme.of(context);
    final radius = BorderRadius.circular(tokens.metrics.artworkRadius);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: radius,
              child: SizedBox.square(
                dimension: artworkSize,
                child: _AlbumArtworkThumbnail(album: album, size: artworkSize),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: tokens.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _albumSummary(album),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _albumSummary(LibraryAlbum album) {
    final trackLabel = album.trackCount == 1 ? 'track' : 'tracks';
    final count = '${album.trackCount} $trackLabel';
    return label == null ? count : '$label · $count';
  }
}

class _AlbumArtworkThumbnail extends StatelessWidget {
  const _AlbumArtworkThumbnail({required this.album, required this.size});

  final LibraryAlbum album;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = album.artworkPath?.trim();

    if (path == null || path.isEmpty) {
      return _fallback(context);
    }

    return Image.file(
      File(path),
      key: ValueKey<String>('artist-album-artwork-${album.albumId}'),
      fit: BoxFit.cover,
      // Decoded at its display size, never at the cover's full resolution.
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      semanticLabel: album.title,
      errorBuilder: (context, error, stackTrace) {
        return _fallback(context);
      },
    );
  }

  Widget _fallback(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return ColoredBox(
      color: colors.artworkPlaceholder,
      child: Center(
        child: Icon(
          Icons.album_rounded,
          size: 56,
          color: colors.onArtworkPlaceholder,
        ),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: SonusTheme.of(context).colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
