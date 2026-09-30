import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
            const _SectionHeading(title: 'Popular This Week'),
            const SizedBox(height: 12),
            _PopularTracksRail(entries: snapshot.weeklyPopularTracks),
            const SizedBox(height: 30),
          ],

          if (snapshot.weeklyTopArtists.isNotEmpty) ...[
            const _SectionHeading(title: 'Top Artists'),
            const SizedBox(height: 12),
            _TopArtistsRail(entries: snapshot.weeklyTopArtists),
            const SizedBox(height: 30),
          ],

          if (snapshot.recentlyAddedTracks.isNotEmpty) ...[
            const _SectionHeading(title: 'Recently Added'),
            const SizedBox(height: 12),
            _RecentlyAddedTracksRail(tracks: snapshot.recentlyAddedTracks),
            const SizedBox(height: 30),
          ],

          if (snapshot.recentlyAddedAlbums.isNotEmpty) ...[
            const _SectionHeading(title: 'New Albums'),
            const SizedBox(height: 12),
            _AlbumsRail(albums: snapshot.recentlyAddedAlbums),
          ],
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PopularTracksRail extends StatelessWidget {
  const _PopularTracksRail({required this.entries});

  final List<HomePopularTrack> entries;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 270,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final entry = entries[index];

          return _PopularTrackCard(
            entry: entry,
            onTap: () {
              unawaited(_showTrackContext(context, entry.track));
            },
          );
        },
      ),
    );
  }
}

class _PopularTrackCard extends StatelessWidget {
  const _PopularTrackCard({required this.entry, required this.onTap});

  final HomePopularTrack entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final track = entry.track;

    return SizedBox(
      width: 170,
      child: InkWell(
        key: ValueKey<String>('home-popular-track-${track.songId}'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _SquareArtwork(
                    path: track.artworkPath,
                    fallbackIcon: Icons.music_note_rounded,
                    size: 170,
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _RankBadge(rank: entry.rank),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                track.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 3),
              Text(
                '${entry.qualifiedStreamCount} weekly streams',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopArtistsRail extends StatelessWidget {
  const _TopArtistsRail({required this.entries});

  final List<HomeTopArtist> entries;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 235,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final entry = entries[index];

          return _ArtistCard(
            entry: entry,
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
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({required this.entry, required this.onTap});

  final HomeTopArtist entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 160,
      child: InkWell(
        key: ValueKey<String>('home-top-artist-${entry.artist.artistId}'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _ArtistArtwork(artist: entry.artist, size: 160),
                Positioned(
                  top: 10,
                  left: 10,
                  child: _RankBadge(rank: entry.rank),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              entry.artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${entry.qualifiedStreamCount} weekly streams',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
            Text(
              _formatListeningDuration(entry.weeklyListeningDuration),
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
}

class _RecentlyAddedTracksRail extends StatelessWidget {
  const _RecentlyAddedTracksRail({required this.tracks});

  final List<LibraryTrack> tracks;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 225,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final track = tracks[index];

          return _RecentTrackCard(
            track: track,
            onTap: track.isBlocked
                ? null
                : () {
                    unawaited(_showTrackContext(context, track));
                  },
          );
        },
      ),
    );
  }
}

class _RecentTrackCard extends StatelessWidget {
  const _RecentTrackCard({required this.track, required this.onTap});

  final LibraryTrack track;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = track.isBlocked;

    return SizedBox(
      width: 150,
      child: InkWell(
        key: ValueKey<String>('home-recent-track-${track.songId}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Opacity(
          opacity: isDisabled ? 0.55 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  _SquareArtwork(
                    path: track.artworkPath,
                    fallbackIcon: Icons.music_note_rounded,
                    size: 150,
                  ),
                  if (isDisabled)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(
                            alpha: 0.45,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Center(child: Icon(Icons.block_rounded)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                track.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
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
    return SizedBox(
      height: 230,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final album = albums[index];

          return _AlbumCard(
            album: album,
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
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onTap});

  final LibraryAlbum album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 160,
      child: InkWell(
        key: ValueKey<String>('home-new-album-${album.albumId}'),
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AlbumArtwork(album: album, size: 160),
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
              album.artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          '#$rank',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox.square(
        dimension: size,
        child: normalizedPath != null && normalizedPath.isNotEmpty
            ? Image.file(
                File(normalizedPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _ArtworkFallback(icon: fallbackIcon),
              )
            : _ArtworkFallback(icon: fallbackIcon),
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(icon, size: 42, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ArtistArtwork extends StatelessWidget {
  const _ArtistArtwork({required this.artist, required this.size});

  final LibraryArtist artist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final topArtistsPath = artist.topArtistsArtworkPath?.trim();
    final headerPath = artist.headerArtworkPath?.trim();

    final path = topArtistsPath != null && topArtistsPath.isNotEmpty
        ? topArtistsPath
        : headerPath != null && headerPath.isNotEmpty
        ? headerPath
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: SizedBox.square(
        dimension: size,
        child: path == null
            ? const _ArtworkFallback(icon: Icons.person_rounded)
            : Image.file(
                File(path),
                key: ValueKey<String>(
                  'home-top-artist-artwork-${artist.artistId}',
                ),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const _ArtworkFallback(icon: Icons.person_rounded),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox.square(
        dimension: size,
        child: path == null || path.isEmpty
            ? const _ArtworkFallback(icon: Icons.album_rounded)
            : Image.file(
                File(path),
                key: ValueKey<String>(
                  'home-new-album-artwork-${album.albumId}',
                ),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const _ArtworkFallback(icon: Icons.album_rounded),
              ),
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
                  '${track.artistName} � ${track.albumTitle}',
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
