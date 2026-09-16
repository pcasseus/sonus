import 'dart:io';

import 'package:flutter/material.dart';

import '../../../application/models/library_album.dart';

class ArtistProfileAlbumsGrid extends StatelessWidget {
  const ArtistProfileAlbumsGrid({
    super.key,
    required this.albums,
    required this.onAlbumTap,
  });

  final List<LibraryAlbum> albums;
  final ValueChanged<LibraryAlbum> onAlbumTap;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const _EmptySection(message: 'No albums yet');
    }

    return GridView.builder(
      key: const ValueKey<String>('artist-profile-albums-grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
        childAspectRatio: 1.25,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];

        return _AlbumCard(
          key: ValueKey<String>('artist-album-${album.albumId}'),
          album: album,
          onTap: () => onAlbumTap(album),
        );
      },
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({super.key, required this.album, required this.onTap});

  final LibraryAlbum album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: _AlbumArtworkThumbnail(album: album),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _albumSummary(album),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _albumSummary(LibraryAlbum album) {
    final trackLabel = album.trackCount == 1 ? 'track' : 'tracks';
    return '${album.trackCount} $trackLabel';
  }
}

class _AlbumArtworkThumbnail extends StatelessWidget {
  const _AlbumArtworkThumbnail({required this.album});

  final LibraryAlbum album;

  @override
  Widget build(BuildContext context) {
    final path = album.artworkPath?.trim();

    if (path == null || path.isEmpty) {
      return _fallback(context);
    }

    return SizedBox.expand(
      key: ValueKey<String>('artist-album-artwork-${album.albumId}'),
      child: Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _fallback(context);
        },
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.album_rounded, size: 56, color: colorScheme.primary),
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
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}
