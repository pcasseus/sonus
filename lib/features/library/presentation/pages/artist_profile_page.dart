import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../controllers/artist_profile_controller.dart';
import 'album_profile_page.dart';

class ArtistProfilePage extends StatefulWidget {
  const ArtistProfilePage({
    super.key,
    required this.artistId,
    this.initialArtistName,
  });

  final String artistId;
  final String? initialArtistName;

  @override
  State<ArtistProfilePage> createState() => _ArtistProfilePageState();
}

class _ArtistProfilePageState extends State<ArtistProfilePage> {
  ArtistProfileController? _controller;
  LibraryQueryRepository? _repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final repository = context.watch<LibraryQueryRepository?>();

    if (repository == null || identical(repository, _repository)) {
      return;
    }

    _controller?.dispose();

    _repository = repository;
    _controller = ArtistProfileController(
      repository: repository,
      artistId: widget.artistId,
      playbackCoordinator: context.read<PlaybackCoordinator?>(),
    );

    unawaited(_controller!.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      key: const ValueKey<String>('artist-profile-page'),
      appBar: AppBar(
        title: Text(
          controller?.artist?.name ?? widget.initialArtistName ?? 'Artist',
        ),
      ),
      body: controller == null
          ? const Center(child: Text('Loading artist...'))
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.isLoading && controller.artist == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (controller.hasError && controller.artist == null) {
                  return _ArtistProfileLoadError(onRetry: controller.load);
                }

                if (controller.isNotFound) {
                  return const _ArtistNotFound();
                }

                final artist = controller.artist;

                if (artist == null) {
                  return const SizedBox.shrink();
                }

                return RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ListView(
                    key: const PageStorageKey<String>('artist-profile-scroll'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    children: [
                      _ArtistHeader(
                        artist: artist,
                        artworkPath: controller.headerArtworkPath,
                      ),
                      const SizedBox(height: 20),
                      _PlaybackControls(controller: controller),
                      const SizedBox(height: 28),
                      _SectionHeading(
                        title: 'Albums',
                        count: controller.albums.length,
                      ),
                      const SizedBox(height: 12),
                      _AlbumsGrid(albums: controller.albums),
                      const SizedBox(height: 28),
                      _SectionHeading(
                        title: 'Songs',
                        count: controller.tracks.length,
                      ),
                      const SizedBox(height: 8),
                      _TracksList(controller: controller),
                    ],
                  ),
                );
              },
            ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({required this.artist, required this.artworkPath});

  final LibraryArtist artist;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ArtistArtwork(artist: artist, artworkPath: artworkPath),
        const SizedBox(height: 16),
        Text(
          artist.name,
          key: ValueKey<String>('artist-profile-name-${artist.artistId}'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _summary(artist),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
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

class _ArtistArtwork extends StatelessWidget {
  const _ArtistArtwork({required this.artist, required this.artworkPath});

  final LibraryArtist artist;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    final path = artworkPath;

    if (path == null) {
      return _ArtistArtworkFallback(artistName: artist.name);
    }

    return ClipOval(
      child: SizedBox(
        key: ValueKey<String>('artist-profile-artwork-${artist.artistId}'),
        width: 104,
        height: 104,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
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
    return CircleAvatar(
      key: const ValueKey<String>('artist-profile-artwork-fallback'),
      radius: 52,
      child: Text(
        _initials(artistName),
        style: Theme.of(context).textTheme.headlineMedium,
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

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.controller});

  final ArtistProfileController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          key: const ValueKey<String>('artist-profile-shuffle-button'),
          tooltip: controller.isShuffleEnabled ? 'Shuffle on' : 'Shuffle off',
          onPressed: controller.hasPlayableTracks
              ? () {
                  unawaited(controller.toggleShuffle());
                }
              : null,
          icon: Icon(
            controller.isShuffleEnabled
                ? Icons.shuffle_on_rounded
                : Icons.shuffle_rounded,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          key: const ValueKey<String>('artist-profile-play-all-button'),
          onPressed: controller.hasPlayableTracks
              ? () {
                  unawaited(controller.playAll());
                }
              : null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Play'),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Text('$count', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _AlbumsGrid extends StatelessWidget {
  const _AlbumsGrid({required this.albums});

  final List<LibraryAlbum> albums;

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
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];

        return Card(
          key: ValueKey<String>('artist-album-${album.albumId}'),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
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
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(child: _AlbumArtworkThumbnail(album: album)),
                  ),
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _albumSummary(album),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        key: ValueKey<String>('artist-album-artwork-${album.albumId}'),
        width: 84,
        height: 84,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _fallback(context);
          },
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    return Icon(
      Icons.album_rounded,
      size: 52,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}

class _TracksList extends StatelessWidget {
  const _TracksList({required this.controller});

  final ArtistProfileController controller;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.tracks;

    if (tracks.isEmpty) {
      return const _EmptySection(message: 'No songs yet');
    }

    return Column(
      key: const ValueKey<String>('artist-profile-tracks-list'),
      children: [
        for (final track in tracks)
          _TrackTile(
            track: track,
            isPlayable: controller.isTrackPlayable(track),
            onPlay: () => controller.playTrack(track),
            onPlayNext: () => controller.playNext(track),
            onAddToQueue: () => controller.addToQueue(track),
          ),
      ],
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.isPlayable,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
  });

  final LibraryTrack track;
  final bool isPlayable;

  final Future<void> Function() onPlay;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onAddToQueue;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey<String>('artist-track-${track.songId}'),
      contentPadding: EdgeInsets.zero,
      enabled: isPlayable,
      leading: SizedBox(
        width: 32,
        child: Center(child: Text('${track.trackNumber}')),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: track.albumTitle.trim().isEmpty
          ? null
          : Text(
              track.albumTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatDuration(track.durationSeconds),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          PopupMenuButton<_TrackMenuAction>(
            key: ValueKey<String>('artist-track-menu-${track.songId}'),
            enabled: isPlayable,
            onSelected: (action) {
              switch (action) {
                case _TrackMenuAction.playNext:
                  unawaited(onPlayNext());
                case _TrackMenuAction.addToQueue:
                  unawaited(onAddToQueue());
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _TrackMenuAction.playNext,
                child: ListTile(
                  leading: Icon(Icons.skip_next_rounded),
                  title: Text('Play next'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _TrackMenuAction.addToQueue,
                child: ListTile(
                  leading: Icon(Icons.queue_music_rounded),
                  title: Text('Add to queue'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: isPlayable
          ? () {
              unawaited(onPlay());
            }
          : null,
    );
  }

  String _formatDuration(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    final remainder = safeSeconds % 60;

    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

enum _TrackMenuAction { playNext, addToQueue }

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

class _ArtistProfileLoadError extends StatelessWidget {
  const _ArtistProfileLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Could not load this artist.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () {
                unawaited(onRetry());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistNotFound extends StatelessWidget {
  const _ArtistNotFound();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 48),
            SizedBox(height: 16),
            Text('Artist not found', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
