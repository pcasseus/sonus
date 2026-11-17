import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../../core/design/sonus_theme.dart';
import '../../../../../core/design/widgets/sonus_horizontal_rail.dart';
import '../../../application/models/library_album.dart';
import '../../../application/models/library_track.dart';
import '../../models/artist_profile_sections.dart';

class ArtistProfileAlbumsGrid extends StatelessWidget {
  const ArtistProfileAlbumsGrid({
    super.key,
    required this.cards,
    required this.onAlbumTap,
    this.onSingleSongTap,
  });

  /// Releases, and in Singles also songs marked as Singles, in rail order.
  final List<ArtistRailCard> cards;
  final ValueChanged<LibraryAlbum> onAlbumTap;

  /// Opens a song shown as a Single (App Update 1.3); its card is inert
  /// without it.
  final ValueChanged<LibraryTrack>? onSingleSongTap;

  /// Narrowest a cover gets before the grid drops a column.
  static const double _minTileWidth = 140;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const _EmptySection(message: 'No albums yet');
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        // Profile Lab: a carousel; about two and a half covers in view, so
        // the next release shows there is more.
        final tileWidth = ((constraints.maxWidth - spacing * 2) / 2.4).clamp(
          _minTileWidth,
          200.0,
        );
        // Room under each cover for the title, summary and the most notes
        // any card here has, at any text size.
        final notes = cards.fold(
          0,
          (most, card) => card.notes.length > most ? card.notes.length : most,
        );
        final captionHeight = MediaQuery.textScalerOf(
          context,
        ).scale(48 + 18.0 * notes);

        return SizedBox(
          height: tileWidth + 10 + captionHeight,
          // Every card is built (as the grid did), so each release stays
          // findable by screen readers and lookups; covers decode lazily.
          // Starts at its first card on entry and for another artist or
          // order ([SonusHorizontalRail]); never shares the page's offset.
          child: SonusHorizontalRail(
            identity: cards.map(_cardId).join('|'),
            builder: (context, controller) => SingleChildScrollView(
              key: const ValueKey<String>('artist-profile-albums-grid'),
              controller: controller,
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (index, card) in cards.indexed) ...[
                    if (index > 0) const SizedBox(width: spacing),
                    SizedBox(
                      width: tileWidth,
                      child: _AlbumCard(
                        key: ValueKey<String>(_cardId(card)),
                        card: card,
                        artworkSize: tileWidth,
                        onTap: switch (card) {
                          ArtistReleaseCard(:final album) => () => onAlbumTap(
                            album,
                          ),
                          ArtistSingleSongCard(:final track) =>
                            onSingleSongTap == null
                                ? null
                                : () => onSingleSongTap!(track),
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _cardId(ArtistRailCard card) => switch (card) {
    ArtistReleaseCard(:final album) => 'artist-album-${album.albumId}',
    ArtistSingleSongCard(:final track) => 'artist-single-song-${track.songId}',
  };
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    super.key,
    required this.card,
    required this.artworkSize,
    required this.onTap,
  });

  final ArtistRailCard card;
  final double artworkSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SonusTheme.of(context);
    final radius = BorderRadius.circular(tokens.metrics.artworkRadius);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: tokens.colors.textSecondary,
    );

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
                child: _AlbumArtworkThumbnail(
                  key: ValueKey<String>(switch (card) {
                    ArtistReleaseCard(:final album) =>
                      'artist-album-artwork-${album.albumId}',
                    ArtistSingleSongCard(:final track) =>
                      'artist-single-song-artwork-${track.songId}',
                  }),
                  path: card.artworkPath,
                  label: card.title,
                  size: artworkSize,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              card.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: tokens.colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              card.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: secondary,
            ),
            for (final note in card.notes)
              Text(
                note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: secondary,
              ),
          ],
        ),
      ),
    );
  }
}

class _AlbumArtworkThumbnail extends StatelessWidget {
  const _AlbumArtworkThumbnail({
    super.key,
    required this.path,
    required this.label,
    required this.size,
  });

  final String? path;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = this.path?.trim();

    if (path == null || path.isEmpty) {
      return _fallback(context);
    }

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      // Decoded at its display size, never at the cover's full resolution.
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      semanticLabel: label,
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
