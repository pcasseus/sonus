import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../core/design/widgets/sonus_decorations.dart';
import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_artist.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/presentation/pages/album_profile_page.dart';
import '../../../library/presentation/pages/artist_profile_page.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../application/models/home_popular_track.dart';
import '../../application/models/home_top_artist.dart';
import '../controllers/home_controller.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController?>();

    if (controller == null) {
      return const _HomeMessage(
        icon: Icons.hourglass_empty_rounded,
        title: 'Home is getting ready',
        message: 'Your Sonus Home data is still initializing.',
      );
    }

    final snapshot = controller.snapshot;

    if (controller.isLoading && snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.hasError && snapshot == null) {
      return _HomeError(onRetry: controller.load);
    }

    if (snapshot == null || snapshot.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
          children: const [
            SizedBox(height: 100),
            _HomeMessage(
              icon: Icons.home_outlined,
              title: 'Your Home is empty',
              message: 'Import music to get started.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const PageStorageKey<String>('home-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 40),
        children: [
          if (controller.hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _RefreshErrorBanner(onRetry: controller.refresh),
            ),

          if (snapshot.weeklyPopularTracks.isNotEmpty) ...[
            const _SectionHeading(
              title: 'Popular This Week',
              caption: 'Your most-played tracks this week',
              featured: true,
            ),
            const SizedBox(height: _headingGap),
            _PopularTracksRail(entries: snapshot.weeklyPopularTracks),
            const SizedBox(height: _sectionGap),
          ],

          if (snapshot.weeklyTopArtists.isNotEmpty) ...[
            const _SectionHeading(title: 'Top Artists'),
            const SizedBox(height: _headingGap),
            _TopArtistsRail(entries: snapshot.weeklyTopArtists),
            const SizedBox(height: _sectionGap),
          ],

          if (snapshot.recentlyAddedTracks.isNotEmpty) ...[
            const _SectionHeading(title: 'Recently Added'),
            const SizedBox(height: _headingGap),
            _RecentlyAddedTracksRail(tracks: snapshot.recentlyAddedTracks),
            const SizedBox(height: _sectionGap),
          ],

          if (snapshot.recentlyAddedAlbums.isNotEmpty) ...[
            const _SectionHeading(title: 'New Albums'),
            const SizedBox(height: _headingGap),
            _AlbumsRail(albums: snapshot.recentlyAddedAlbums),
          ],
        ],
      ),
    );
  }
}

/// Space between a section heading and its rail.
const double _headingGap = 12;

/// Space between one section's rail and the next heading.
const double _sectionGap = 32;

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    this.caption,
    this.featured = false,
  });

  final String title;

  /// A short line under the lead section's heading that sets it apart from
  /// the supporting rails.
  final String? caption;

  /// The lead section carries the theme's surface texture behind its
  /// heading. Rails and cards stay untextured.
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final caption = this.caption;

    Widget heading = SonusSectionHeading(
      title: title,
      padding: EdgeInsets.symmetric(horizontal: tokens.metrics.pageGutter),
    );

    if (caption != null) {
      heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.metrics.pageGutter,
              tokens.metrics.spaceXs,
              tokens.metrics.pageGutter,
              0,
            ),
            child: Text(
              caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tokens.colors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    if (!featured) {
      return heading;
    }

    return Stack(
      children: [
        const Positioned.fill(child: SonusSurfaceTexture()),
        heading,
      ],
    );
  }
}

/// Card widths for the Home rails, derived from the screen so every rail
/// shows a partial next card and reads as scrollable.
///
/// Popular This Week leads with the largest cards; Recently Added and New
/// Albums share one smaller size, so the page reads as a feature followed
/// by supporting rails.
abstract final class _RailSizing {
  /// Space between cards in a rail.
  static const double gap = 14;

  static double featuredWidth(BuildContext context) =>
      fit(context, cardsPerScreen: 2.1, min: 150, max: 220);

  static double standardWidth(BuildContext context) =>
      fit(context, cardsPerScreen: 2.5, min: 130, max: 180);

  static double fit(
    BuildContext context, {
    required double cardsPerScreen,
    required double min,
    required double max,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final gutter = SonusTheme.of(context).metrics.pageGutter;

    return ((screenWidth - gutter * 2 - gap) / cardsPerScreen).clamp(min, max);
  }
}

/// A horizontal rail of cards inset by the page gutter.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final gutter = SonusTheme.of(context).metrics.pageGutter;

    return SizedBox(
      height: height,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: _RailSizing.gap),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

class _PopularTracksRail extends StatelessWidget {
  const _PopularTracksRail({required this.entries});

  final List<HomePopularTrack> entries;

  @override
  Widget build(BuildContext context) {
    final cardWidth = _RailSizing.featuredWidth(context);

    return _Rail(
      height: _railHeight(context, artwork: cardWidth, text: 100),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final track = entry.track;

        return _RailCard(
          cardKey: ValueKey<String>('home-popular-track-${track.songId}'),
          width: cardWidth,
          title: track.title,
          subtitle: track.artistName,
          detail: '${entry.qualifiedStreamCount} weekly streams',
          artwork: Stack(
            children: [
              _SquareArtwork(
                path: track.artworkPath,
                fallbackIcon: Icons.music_note_rounded,
                size: cardWidth,
              ),
              Positioned(
                top: 10,
                left: 10,
                child: _RankBadge(rank: entry.rank),
              ),
            ],
          ),
          onTap: () {
            unawaited(_showTrackContext(context, track));
          },
        );
      },
    );
  }
}

/// A square-artwork rail card: artwork, a bold title, a secondary line and
/// an optional statistic.
class _RailCard extends StatelessWidget {
  const _RailCard({
    required this.cardKey,
    required this.width,
    required this.artwork,
    required this.title,
    required this.subtitle,
    this.detail,
    this.onTap,
    this.dimmed = false,
  });

  final Key cardKey;
  final double width;
  final Widget artwork;
  final String title;
  final String subtitle;

  /// A figure such as a stream count, set in tabular digits.
  final String? detail;

  /// Null leaves the card visible but not interactive.
  final VoidCallback? onTap;

  /// Fades the card for content that cannot be played.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SonusTheme.of(context);
    final radius = BorderRadius.circular(tokens.metrics.cardRadius);
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: tokens.colors.textSecondary,
    );
    final detail = this.detail;

    return SizedBox(
      width: width,
      child: _CardFocusRing(
        borderRadius: radius,
        builder: (onFocusChange) => InkWell(
          key: cardKey,
          borderRadius: radius,
          onTap: onTap,
          onFocusChange: onFocusChange,
          child: Opacity(
            opacity: dimmed ? 0.55 : 1,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  artwork,
                  const SizedBox(height: 10),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: tokens.colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: secondaryStyle,
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: secondaryStyle?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlines a card in the theme's focus colour while it has keyboard focus.
///
/// Ink highlights paint beneath artwork, so without a ring a focused card
/// would barely change. The ring is a foreground border: it adds no layout.
class _CardFocusRing extends StatefulWidget {
  const _CardFocusRing({required this.borderRadius, required this.builder});

  final BorderRadius borderRadius;
  final Widget Function(ValueChanged<bool> onFocusChange) builder;

  @override
  State<_CardFocusRing> createState() => _CardFocusRingState();
}

class _CardFocusRingState extends State<_CardFocusRing> {
  bool _focused = false;

  void _handleFocusChange(bool focused) {
    if (focused != _focused) {
      setState(() => _focused = focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return DecoratedBox(
      key: _focused ? const ValueKey<String>('home-card-focus-ring') : null,
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        border: _focused ? Border.all(color: colors.focus, width: 3) : null,
      ),
      child: widget.builder(_handleFocusChange),
    );
  }
}

class _TopArtistsRail extends StatelessWidget {
  const _TopArtistsRail({required this.entries});

  final List<HomeTopArtist> entries;

  @override
  Widget build(BuildContext context) {
    final cardWidth = _ArtistCard.widthFor(context);

    return _Rail(
      height: _railHeight(
        context,
        artwork: _ArtistCard.artworkHeightFor(cardWidth),
        text: _ArtistCard.infoHeight,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];

        return _ArtistCard(
          entry: entry,
          width: cardWidth,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ArtistProfilePage(
                  artistId: entry.artist.artistId,
                  initialArtistName: entry.artist.name,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// A portrait Top Artists card: tall artwork above a separate information
/// panel, like an editorial artist feature.
class _ArtistCard extends StatelessWidget {
  const _ArtistCard({
    required this.entry,
    required this.width,
    required this.onTap,
  });

  /// Portrait artwork, width : height.
  static const double artworkAspectRatio = 3 / 4;

  /// Room for a name of up to two lines and two statistic lines at 1x
  /// text, so long names stay readable at large text sizes too.
  static const double infoHeight = 104;

  /// About two and a quarter cards per screen, so the rail reads as
  /// scrollable on every width.
  static double widthFor(BuildContext context) =>
      _RailSizing.fit(context, cardsPerScreen: 2.25, min: 140, max: 190);

  static double artworkHeightFor(double width) => width / artworkAspectRatio;

  final HomeTopArtist entry;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SonusTheme.of(context);
    final radius = BorderRadius.circular(tokens.metrics.cardRadius);

    return SizedBox(
      width: width,
      child: _CardFocusRing(
        borderRadius: radius,
        builder: (onFocusChange) => Material(
          color: tokens.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: tokens.decoration.showMarks
                ? BorderSide(color: tokens.colors.artworkFrame)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey<String>('home-top-artist-${entry.artist.artistId}'),
            onTap: onTap,
            onFocusChange: onFocusChange,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: artworkHeightFor(width),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _ArtistArtwork(artist: entry.artist),
                      if (tokens.decoration.allowGradients)
                        _ArtworkFade(color: tokens.colors.surface),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _RankBadge(rank: entry.rank),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.artist.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: tokens.colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${entry.qualifiedStreamCount} weekly streams',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatListeningDuration(
                            entry.weeklyListeningDuration,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.colors.textSecondary,
                          ),
                        ),
                      ],
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

/// Blends the bottom of the artwork into the information panel.
class _ArtworkFade extends StatelessWidget {
  const _ArtworkFade({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.72, 1],
            colors: [color.withValues(alpha: 0), color],
          ),
        ),
      ),
    );
  }
}

class _RecentlyAddedTracksRail extends StatelessWidget {
  const _RecentlyAddedTracksRail({required this.tracks});

  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context) {
    final cardWidth = _RailSizing.standardWidth(context);

    return _Rail(
      height: _railHeight(context, artwork: cardWidth, text: 75),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isBlocked = track.isBlocked;

        return _RailCard(
          cardKey: ValueKey<String>('home-recent-track-${track.songId}'),
          width: cardWidth,
          title: track.title,
          subtitle: track.artistName,
          dimmed: isBlocked,
          artwork: Stack(
            children: [
              _SquareArtwork(
                path: track.artworkPath,
                fallbackIcon: Icons.music_note_rounded,
                size: cardWidth,
              ),
              if (isBlocked) const Positioned.fill(child: _BlockedOverlay()),
            ],
          ),
          onTap: isBlocked
              ? null
              : () {
                  unawaited(_showTrackContext(context, track));
                },
        );
      },
    );
  }
}

/// Marks artwork of a track that cannot be played. The icon carries a
/// label, so the state is not conveyed by fading alone.
class _BlockedOverlay extends StatelessWidget {
  const _BlockedOverlay();

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.background.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(tokens.metrics.artworkRadius),
      ),
      child: Center(
        child: Icon(
          Icons.block_rounded,
          semanticLabel: 'Unavailable',
          color: tokens.colors.textPrimary,
        ),
      ),
    );
  }
}

class _AlbumsRail extends StatelessWidget {
  const _AlbumsRail({required this.albums});

  final List<LibraryAlbum> albums;

  @override
  Widget build(BuildContext context) {
    final cardWidth = _RailSizing.standardWidth(context);

    return _Rail(
      height: _railHeight(context, artwork: cardWidth, text: 75),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];

        return _RailCard(
          cardKey: ValueKey<String>('home-new-album-${album.albumId}'),
          width: cardWidth,
          title: album.title,
          subtitle: album.artistName,
          artwork: _AlbumArtwork(album: album, size: cardWidth),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AlbumProfilePage(
                  albumId: album.albumId,
                  initialAlbumTitle: album.title,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.accentPrimary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          '#$rank',
          semanticsLabel: 'Rank $rank',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: tokens.colors.onAccentPrimary,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _SquareArtwork extends StatelessWidget {
  const _SquareArtwork({
    required this.path,
    required this.fallbackIcon,
    required this.size,
  });

  final String? path;
  final IconData fallbackIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final normalizedPath = path?.trim();

    return SonusArtworkFrame(
      size: size,
      child: normalizedPath != null && normalizedPath.isNotEmpty
          ? Image.file(
              File(normalizedPath),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _ArtworkFallback(icon: fallbackIcon),
            )
          : _ArtworkFallback(icon: fallbackIcon),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SonusArtworkPlaceholder(icon: icon, iconSize: 42);
  }
}

class _ArtistArtwork extends StatelessWidget {
  const _ArtistArtwork({required this.artist});

  /// Portrait crops keep the upper part of the image, where faces usually
  /// are, rather than the exact centre.
  static const Alignment _portraitFocus = Alignment(0, -0.35);

  final LibraryArtist artist;

  @override
  Widget build(BuildContext context) {
    final topArtistsPath = artist.topArtistsArtworkPath?.trim();
    final headerPath = artist.headerArtworkPath?.trim();

    final path = topArtistsPath != null && topArtistsPath.isNotEmpty
        ? topArtistsPath
        : headerPath != null && headerPath.isNotEmpty
        ? headerPath
        : null;

    if (path == null) {
      return _ArtistInitials(name: artist.name);
    }

    return Image.file(
      File(path),
      key: ValueKey<String>('home-top-artist-artwork-${artist.artistId}'),
      fit: BoxFit.cover,
      alignment: _portraitFocus,
      errorBuilder: (_, _, _) => _ArtistInitials(name: artist.name),
    );
  }
}

/// The artist's initials on the theme placeholder, shown when there is no
/// artwork.
class _ArtistInitials extends StatelessWidget {
  const _ArtistInitials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final initials = name
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();

    return ColoredBox(
      key: const ValueKey<String>('home-top-artist-initials'),
      color: tokens.colors.artworkPlaceholder,
      child: Center(
        child: ExcludeSemantics(
          child: initials.isEmpty
              ? Icon(
                  Icons.person_rounded,
                  size: 48,
                  color: tokens.colors.onArtworkPlaceholder,
                )
              : Text(
                  initials,
                  style: tokens.text.featuredStat.copyWith(
                    color: tokens.colors.onArtworkPlaceholder,
                  ),
                ),
        ),
      ),
    );
  }
}

class _AlbumArtwork extends StatelessWidget {
  const _AlbumArtwork({required this.album, required this.size});

  final LibraryAlbum album;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = album.artworkPath?.trim();

    return SonusArtworkFrame(
      size: size,
      child: path == null || path.isEmpty
          ? const _ArtworkFallback(icon: Icons.album_rounded)
          : Image.file(
              File(path),
              key: ValueKey<String>('home-new-album-artwork-${album.albumId}'),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const _ArtworkFallback(icon: Icons.album_rounded),
            ),
    );
  }
}

class _HomeMessage extends StatelessWidget {
  const _HomeMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        children: [
          Icon(icon, size: 42, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            const Text('Home could not be loaded.'),
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: () {
                unawaited(onRetry());
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RefreshErrorBanner extends StatelessWidget {
  const _RefreshErrorBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Home could not refresh.',
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: () {
                unawaited(onRetry());
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Height of a horizontal rail: its artwork plus room for the card's text.
///
/// Rails scroll sideways, so their height is fixed up front. The text
/// allowance grows with the system text scale so titles and statistics stay
/// inside the card; at 1x the heights match the original layout.
double _railHeight(
  BuildContext context, {
  required double artwork,
  required double text,
}) {
  final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

  return artwork + text * math.max(1, textScale);
}

Future<void> _showTrackContext(BuildContext context, LibraryTrack track) async {
  if (track.isBlocked || !track.isAvailable) {
    return;
  }

  final playback = context.read<PlaybackCoordinator?>();

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${track.artistName} · ${track.albumTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('Play'),
                enabled: playback != null,
                onTap: playback == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        unawaited(playback.playTrack(track));
                      },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: const Text('Play next'),
                enabled: playback != null,
                onTap: playback == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        unawaited(playback.playNext(track));
                      },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: const Text('Add to queue'),
                enabled: playback != null,
                onTap: playback == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        unawaited(playback.addToQueue(track));
                      },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Add to playlist'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(showAddToPlaylistFlow(context, track));
                },
              ),
              ListTile(
                leading: const Icon(Icons.album_outlined),
                title: const Text('Go to album'),
                onTap: () {
                  Navigator.of(sheetContext).pop();

                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AlbumProfilePage(
                        albumId: track.albumId,
                        initialAlbumTitle: track.albumTitle,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('Go to artist'),
                onTap: () {
                  Navigator.of(sheetContext).pop();

                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ArtistProfilePage(
                        artistId: track.artistId,
                        initialArtistName: track.artistName,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _formatListeningDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;

  if (totalMinutes < 60) {
    return '$totalMinutes min listening';
  }

  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;

  if (minutes == 0) {
    return '${hours}h listening';
  }

  return '${hours}h ${minutes}m listening';
}
