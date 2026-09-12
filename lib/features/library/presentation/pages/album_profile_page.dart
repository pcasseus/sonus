import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../controllers/album_profile_controller.dart';

class AlbumProfilePage extends StatefulWidget {
  const AlbumProfilePage({
    super.key,
    required this.albumId,
    this.initialAlbumTitle,
  });

  final String albumId;
  final String? initialAlbumTitle;

  @override
  State<AlbumProfilePage> createState() => _AlbumProfilePageState();
}

class _AlbumProfilePageState extends State<AlbumProfilePage> {
  AlbumProfileController? _controller;
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
    _controller = AlbumProfileController(
      repository: repository,
      albumId: widget.albumId,
      playbackCoordinator: context.read<PlaybackCoordinator?>(),
      artworkAssignmentService: context.read<ArtworkAssignmentService?>(),
      artworkFilePicker: context.read<ArtworkFilePicker?>(),
    );

    unawaited(_controller!.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      key: const ValueKey<String>('album-profile-page'),
      appBar: AppBar(
        title: controller == null
            ? Text(widget.initialAlbumTitle ?? 'Album')
            : AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  return Text(
                    controller.album?.title ??
                        widget.initialAlbumTitle ??
                        'Album',
                  );
                },
              ),
        actions: [
          if (controller != null)
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                return PopupMenuButton<_AlbumArtworkMenuAction>(
                  key: const ValueKey<String>('album-profile-artwork-menu'),
                  enabled: controller.canEditArtwork,
                  tooltip: 'Edit artwork',
                  onSelected: (action) {
                    unawaited(_handleArtworkAction(controller, action));
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _AlbumArtworkMenuAction.change,
                      child: ListTile(
                        leading: Icon(Icons.image_rounded),
                        title: Text('Change artwork'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _AlbumArtworkMenuAction.clear,
                      child: ListTile(
                        leading: Icon(Icons.hide_image_rounded),
                        title: Text('Clear artwork'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
      body: controller == null
          ? const Center(child: Text('Loading album...'))
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.isLoading && controller.album == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (controller.hasError && controller.album == null) {
                  return _AlbumProfileLoadError(onRetry: controller.load);
                }

                if (controller.isNotFound) {
                  return const _AlbumNotFound();
                }

                final album = controller.album;

                if (album == null) {
                  return const SizedBox.shrink();
                }

                return RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ListView(
                    key: const PageStorageKey<String>('album-profile-scroll'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    children: [
                      _AlbumHeader(
                        album: album,
                        controller: controller,
                        artworkPath: controller.artworkPath,
                      ),
                      const SizedBox(height: 20),
                      _PlaybackControls(controller: controller),
                      const SizedBox(height: 28),
                      _SectionHeading(
                        title: 'Tracks',
                        count: controller.tracks.length,
                      ),
                      const SizedBox(height: 8),
                      _TracksList(
                        controller: controller,
                        onChangeArtwork: (track) =>
                            _changeTrackArtwork(controller, track),
                        onClearArtwork: (track) =>
                            _clearTrackArtwork(controller, track),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _handleArtworkAction(
    AlbumProfileController controller,
    _AlbumArtworkMenuAction action,
  ) async {
    try {
      final changed = switch (action) {
        _AlbumArtworkMenuAction.change => await controller.changeArtwork(),
        _AlbumArtworkMenuAction.clear => await controller.clearArtwork(),
      };

      if (!mounted || !changed) {
        return;
      }

      final message = switch (action) {
        _AlbumArtworkMenuAction.change => 'Album artwork updated.',
        _AlbumArtworkMenuAction.clear => 'Album artwork cleared.',
      };

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update album artwork.')),
      );
    }
  }

  Future<void> _changeTrackArtwork(
    AlbumProfileController controller,
    LibraryTrack track,
  ) async {
    try {
      final changed = await controller.changeTrackArtwork(track);

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Song artwork updated.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update song artwork.')),
      );
    }
  }

  Future<void> _clearTrackArtwork(
    AlbumProfileController controller,
    LibraryTrack track,
  ) async {
    try {
      final changed = await controller.clearTrackArtwork(track);

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Song artwork cleared.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update song artwork.')),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.album,
    required this.controller,
    required this.artworkPath,
  });

  final LibraryAlbum album;
  final AlbumProfileController controller;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = _metadata(album);

    return Column(
      children: [
        _AlbumArtwork(album: album, artworkPath: artworkPath),
        const SizedBox(height: 18),
        Text(
          album.title,
          key: ValueKey<String>('album-profile-title-${album.albumId}'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          album.artistName,
          key: ValueKey<String>('album-profile-artist-${album.artistId}'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Text(
          _summary(),
          key: const ValueKey<String>('album-profile-summary'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            metadata,
            key: const ValueKey<String>('album-profile-metadata'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (controller.hasUnavailableTracks) ...[
          const SizedBox(height: 10),
          _AvailabilityNotice(
            unavailableTrackCount: controller.unavailableTrackCount,
          ),
        ],
      ],
    );
  }

  String _summary() {
    final trackCount = controller.tracks.length;
    final trackLabel = trackCount == 1 ? 'track' : 'tracks';

    final runtime = _formatRuntime(controller.totalDuration);

    if (runtime.isEmpty) {
      return '$trackCount $trackLabel';
    }

    return '$trackCount $trackLabel • $runtime';
  }

  String _metadata(LibraryAlbum album) {
    final parts = <String>[];

    final releaseDate = album.releaseDate;

    if (releaseDate != null) {
      parts.add(_formatDate(releaseDate));
    }

    final genre = album.genre?.trim();

    if (genre != null && genre.isNotEmpty) {
      parts.add(genre);
    }

    if (controller.hasMultipleEditions) {
      parts.add('${controller.editionCount} editions');
    } else {
      final editionTitle = album.primaryEditionTitle?.trim();

      if (editionTitle != null &&
          editionTitle.isNotEmpty &&
          editionTitle.toLowerCase() != 'standard') {
        parts.add(editionTitle);
      }
    }

    return parts.join(' • ');
  }

  String _formatRuntime(Duration duration) {
    final totalMinutes = duration.inMinutes;

    if (totalMinutes <= 0) {
      return '';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours == 0) {
      return '$minutes min';
    }

    if (minutes == 0) {
      return '$hours hr';
    }

    return '$hours hr $minutes min';
  }

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year}';
  }
}

class _AlbumArtwork extends StatelessWidget {
  const _AlbumArtwork({required this.album, required this.artworkPath});

  final LibraryAlbum album;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = artworkPath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        key: ValueKey<String>('album-profile-artwork-${album.albumId}'),
        width: 156,
        height: 156,
        child: path == null
            ? _fallback(theme)
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _fallback(theme);
                },
              ),
      ),
    );
  }

  Widget _fallback(ThemeData theme) {
    return ColoredBox(
      key: const ValueKey<String>('album-profile-artwork-fallback'),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.album_rounded,
          size: 82,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _AvailabilityNotice extends StatelessWidget {
  const _AvailabilityNotice({required this.unavailableTrackCount});

  final int unavailableTrackCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trackLabel = unavailableTrackCount == 1 ? 'track' : 'tracks';

    return Container(
      key: const ValueKey<String>('album-profile-availability-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$unavailableTrackCount '
        '$trackLabel unavailable',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.controller});

  final AlbumProfileController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          key: const ValueKey<String>('album-profile-shuffle-button'),
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
          key: const ValueKey<String>('album-profile-play-all-button'),
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

class _TracksList extends StatelessWidget {
  const _TracksList({
    required this.controller,
    required this.onChangeArtwork,
    required this.onClearArtwork,
  });

  final AlbumProfileController controller;
  final Future<void> Function(LibraryTrack track) onChangeArtwork;
  final Future<void> Function(LibraryTrack track) onClearArtwork;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.tracks;

    if (tracks.isEmpty) {
      return const _EmptySection(message: 'No tracks yet');
    }

    return Column(
      key: const ValueKey<String>('album-profile-tracks-list'),
      children: [
        for (final track in tracks)
          _TrackTile(
            track: track,
            isPlayable: controller.isTrackPlayable(track),
            canEditArtwork: controller.canEditTrackArtwork,
            onPlay: () => controller.playTrack(track),
            onPlayNext: () => controller.playNext(track),
            onAddToQueue: () => controller.addToQueue(track),
            onChangeArtwork: () => onChangeArtwork(track),
            onClearArtwork: () => onClearArtwork(track),
          ),
      ],
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.isPlayable,
    required this.canEditArtwork,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onChangeArtwork,
    required this.onClearArtwork,
  });

  final LibraryTrack track;
  final bool isPlayable;
  final bool canEditArtwork;

  final Future<void> Function() onPlay;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onAddToQueue;
  final Future<void> Function() onChangeArtwork;
  final Future<void> Function() onClearArtwork;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey<String>('album-track-${track.songId}'),
      contentPadding: EdgeInsets.zero,
      enabled: isPlayable,
      leading: SizedBox(
        width: 32,
        child: Center(child: Text('${track.trackNumber}')),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: _subtitle(track),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatDuration(track.durationSeconds),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          PopupMenuButton<_TrackMenuAction>(
            key: ValueKey<String>('album-track-menu-${track.songId}'),
            enabled: isPlayable || canEditArtwork,
            onSelected: (action) {
              switch (action) {
                case _TrackMenuAction.playNext:
                  unawaited(onPlayNext());
                case _TrackMenuAction.addToQueue:
                  unawaited(onAddToQueue());
                case _TrackMenuAction.changeArtwork:
                  unawaited(onChangeArtwork());
                case _TrackMenuAction.clearArtwork:
                  unawaited(onClearArtwork());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _TrackMenuAction.playNext,
                enabled: isPlayable,
                child: const ListTile(
                  leading: Icon(Icons.skip_next_rounded),
                  title: Text('Play next'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _TrackMenuAction.addToQueue,
                enabled: isPlayable,
                child: const ListTile(
                  leading: Icon(Icons.queue_music_rounded),
                  title: Text('Add to queue'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _TrackMenuAction.changeArtwork,
                enabled: canEditArtwork,
                child: const ListTile(
                  leading: Icon(Icons.image_rounded),
                  title: Text('Change artwork'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _TrackMenuAction.clearArtwork,
                enabled: canEditArtwork,
                child: const ListTile(
                  leading: Icon(Icons.hide_image_rounded),
                  title: Text('Clear artwork'),
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

  Widget? _subtitle(LibraryTrack track) {
    final parts = <String>[];

    if (track.featuredArtists.isNotEmpty) {
      parts.add('feat. ${track.featuredArtists.join(', ')}');
    }

    final editionTitle = track.albumEditionTitle.trim();

    if (editionTitle.isNotEmpty && editionTitle.toLowerCase() != 'standard') {
      parts.add(editionTitle);
    }

    if (parts.isEmpty) {
      return null;
    }

    return Text(
      parts.join(' • '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _formatDuration(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    final remainder = safeSeconds % 60;

    return '$minutes:'
        '${remainder.toString().padLeft(2, '0')}';
  }
}

enum _AlbumArtworkMenuAction { change, clear }

enum _TrackMenuAction { playNext, addToQueue, changeArtwork, clearArtwork }

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

class _AlbumProfileLoadError extends StatelessWidget {
  const _AlbumProfileLoadError({required this.onRetry});

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
              'Could not load this album.',
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

class _AlbumNotFound extends StatelessWidget {
  const _AlbumNotFound();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.album_outlined, size: 48),
            SizedBox(height: 16),
            Text('Album not found', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
