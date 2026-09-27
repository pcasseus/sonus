import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../account/application/controllers/account_controller.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/models/library_track_order.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/artist_creation_service.dart';
import '../../application/services/song_block_service.dart';
import '../../application/services/track_profile_editing_service.dart';
import '../controllers/library_tracks_controller.dart';
import '../widgets/track_profile_edit_dialog.dart';

class TracksPage extends StatefulWidget {
  const TracksPage({super.key});

  @override
  State<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends State<TracksPage> {
  LibraryTracksController? _controller;
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

    _controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: context.read<PlaybackCoordinator>(),
      trackProfileEditingService: context.read<TrackProfileEditingService?>(),
      songBlockService: context.read<SongBlockService?>(),
      artworkAssignmentService: context.read<ArtworkAssignmentService?>(),
      artworkFilePicker: context.read<ArtworkFilePicker?>(),
    );

    unawaited(_controller!.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final accountController = context.watch<AccountController?>();
    final userId = accountController?.user?.id;

    if (controller == null) {
      return const SizedBox(
        key: ValueKey<String>('app-destination-tracks'),
        child: Center(child: Text('Loading tracks...')),
      );
    }

    return SizedBox(
      key: const ValueKey<String>('app-destination-tracks'),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.isLoading && controller.tracks.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.hasError && controller.tracks.isEmpty) {
            return _LibraryLoadError(
              message: 'Could not load your tracks.',
              onRetry: controller.load,
            );
          }

          if (controller.isEmpty) {
            return RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 72, 24, 120),
                children: const [_EmptyTracksState()],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: CustomScrollView(
              key: const PageStorageKey<String>('tracks-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _TracksHeader(trackCount: controller.tracks.length),
                ),
                SliverToBoxAdapter(
                  child: _TracksControls(controller: controller),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  sliver: SliverList.separated(
                    itemCount: controller.tracks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final track = controller.tracks[index];

                      return _TrackTile(
                        track: track,
                        isPlayable: controller.isTrackPlayable(track),
                        canEditArtwork: controller.canEditArtwork,
                        canEditTrack: controller.canEditTrack(userId),
                        canSetBlocked: controller.canSetTrackBlocked(userId),
                        onPlay: () => controller.playTrack(track),
                        onPlayNext: () => controller.playNext(track),
                        onAddToQueue: () => controller.addToQueue(track),
                        onEditTrack: () =>
                            _editTrack(controller, track, userId),
                        onChangeArtwork: () =>
                            _changeArtwork(controller, track),
                        onClearArtwork: () => _clearArtwork(controller, track),
                        onSetBlocked: (isBlocked) => _setTrackBlocked(
                          controller,
                          track,
                          userId,
                          isBlocked,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _editTrack(
    LibraryTracksController controller,
    LibraryTrack track,
    String? userId,
  ) async {
    if (userId == null || userId.trim().isEmpty) {
      return;
    }

    try {
      final repository = _repository;

      if (repository == null) {
        return;
      }

      final artists = await repository.getArtists();
      final albums = await repository.getAlbums();

      if (!mounted) {
        return;
      }

      final artistCreationService = context.read<ArtistCreationService?>();

      final draft = await showDialog<TrackProfileEditDraft>(
        context: context,
        builder: (dialogContext) {
          return TrackProfileEditDialog(
            track: track,
            artists: artists,
            albums: albums,
            onCreateArtist: artistCreationService == null
                ? null
                : (name) async {
                    final artist = await artistCreationService.createOrReuse(
                      userId: userId,
                      name: name,
                    );

                    return LibraryArtist(
                      artistId: artist.id,
                      name: artist.name,
                      albumCount: 0,
                      songCount: 0,
                      dateAdded: artist.createdAt,
                    );
                  },
          );
        },
      );

      if (!mounted || draft == null) {
        return;
      }

      final changed = await controller.updateTrack(
        userId: userId,
        track: track,
        title: draft.title,
        trackNumber: draft.trackNumber,
        discNumber: draft.discNumber,
        featuredArtists: draft.featuredArtists,
        isSingle: draft.isSingle,
        artistId: draft.artistId,
        albumId: draft.albumId,
        albumEditionId: draft.albumEditionId,
      );

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Song details updated.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update song details.')),
      );
    }
  }

  Future<void> _setTrackBlocked(
    LibraryTracksController controller,
    LibraryTrack track,
    String? userId,
    bool isBlocked,
  ) async {
    if (userId == null ||
        userId.trim().isEmpty ||
        !controller.canSetTrackBlocked(userId)) {
      return;
    }

    try {
      final changed = await controller.setTrackBlocked(
        userId: userId,
        track: track,
        isBlocked: isBlocked,
      );

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isBlocked ? 'Song blocked.' : 'Song unblocked.'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update song blocking.')),
      );
    }
  }

  Future<void> _changeArtwork(
    LibraryTracksController controller,
    LibraryTrack track,
  ) async {
    try {
      final changed = await controller.changeArtwork(track);

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

  Future<void> _clearArtwork(
    LibraryTracksController controller,
    LibraryTrack track,
  ) async {
    try {
      final changed = await controller.clearArtwork(track);

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

class _TracksHeader extends StatelessWidget {
  const _TracksHeader({required this.trackCount});

  final int trackCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tracks',
                  key: const ValueKey<String>('tracks-page-title'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _trackCountLabel(trackCount),
                  key: const ValueKey<String>('tracks-count-label'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _trackCountLabel(int count) {
    return count == 1
        ? '1 song in your library'
        : '$count songs in your library';
  }
}

class _TracksControls extends StatelessWidget {
  const _TracksControls({required this.controller});

  final LibraryTracksController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<LibraryTrackOrder>(
                    key: const ValueKey<String>('tracks-order-dropdown'),
                    initialValue: controller.order,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Sort by',
                      prefixIcon: const Icon(Icons.sort_rounded),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colorScheme.primary),
                      ),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: LibraryTrackOrder.title,
                        child: Text('Song name'),
                      ),
                      DropdownMenuItem(
                        value: LibraryTrackOrder.artist,
                        child: Text('Artist name'),
                      ),
                      DropdownMenuItem(
                        value: LibraryTrackOrder.dateAdded,
                        child: Text('Date added'),
                      ),
                    ],
                    onChanged: (order) {
                      if (order != null) {
                        unawaited(controller.setOrder(order));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey<String>('tracks-play-all-button'),
                    onPressed: controller.playAll,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play all'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: controller.isShuffleEnabled
                      ? FilledButton.tonalIcon(
                          key: const ValueKey<String>('tracks-shuffle-button'),
                          onPressed: () {
                            unawaited(controller.toggleShuffle());
                          },
                          icon: const Icon(Icons.shuffle_on_rounded),
                          label: const Text('Shuffle on'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        )
                      : OutlinedButton.icon(
                          key: const ValueKey<String>('tracks-shuffle-button'),
                          onPressed: () {
                            unawaited(controller.toggleShuffle());
                          },
                          icon: const Icon(Icons.shuffle_rounded),
                          label: const Text('Shuffle'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.isPlayable,
    required this.canEditArtwork,
    required this.canEditTrack,
    required this.canSetBlocked,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onEditTrack,
    required this.onChangeArtwork,
    required this.onClearArtwork,
    required this.onSetBlocked,
  });

  final LibraryTrack track;
  final bool isPlayable;
  final bool canEditArtwork;
  final bool canEditTrack;
  final bool canSetBlocked;

  final Future<void> Function() onPlay;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onAddToQueue;
  final Future<void> Function() onEditTrack;
  final Future<void> Function() onChangeArtwork;
  final Future<void> Function() onClearArtwork;
  final Future<void> Function(bool isBlocked) onSetBlocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: isPlayable
          ? colorScheme.surfaceContainerLow
          : colorScheme.surfaceContainerLow.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('track-${track.songId}'),
        onTap: isPlayable
            ? () {
                unawaited(onPlay());
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              _TrackArtwork(track: track, isPlayable: isPlayable),
              const SizedBox(width: 12),
              Expanded(
                child: _TrackMetadata(track: track, isPlayable: isPlayable),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(track.durationSeconds),
                key: ValueKey<String>('track-duration-${track.songId}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              PopupMenuButton<_TrackMenuAction>(
                key: ValueKey<String>('track-menu-${track.songId}'),
                enabled:
                    isPlayable ||
                    canEditArtwork ||
                    canEditTrack ||
                    canSetBlocked,
                tooltip: 'Song options',
                onSelected: (action) {
                  switch (action) {
                    case _TrackMenuAction.playNext:
                      unawaited(onPlayNext());
                    case _TrackMenuAction.addToQueue:
                      unawaited(onAddToQueue());
                    case _TrackMenuAction.editDetails:
                      unawaited(onEditTrack());
                    case _TrackMenuAction.changeArtwork:
                      unawaited(onChangeArtwork());
                    case _TrackMenuAction.clearArtwork:
                      unawaited(onClearArtwork());
                    case _TrackMenuAction.toggleBlocked:
                      unawaited(onSetBlocked(!track.isSongBlocked));
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
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _TrackMenuAction.editDetails,
                    enabled: canEditTrack,
                    child: const ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit song details'),
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
                    value: _TrackMenuAction.toggleBlocked,
                    enabled: canSetBlocked,
                    child: ListTile(
                      leading: Icon(
                        track.isSongBlocked
                            ? Icons.lock_open_rounded
                            : Icons.block_rounded,
                      ),
                      title: Text(
                        track.isSongBlocked ? 'Unblock song' : 'Block song',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuDivider(),
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
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    final remainder = safeSeconds % 60;

    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

class _TrackArtwork extends StatelessWidget {
  const _TrackArtwork({required this.track, required this.isPlayable});

  final LibraryTrack track;
  final bool isPlayable;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final path = track.artworkPath?.trim();

    return SizedBox.square(
      dimension: 54,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (path != null && path.isNotEmpty)
              Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _ArtworkFallback(isPlayable: isPlayable),
              )
            else
              _ArtworkFallback(isPlayable: isPlayable),
            if (!isPlayable)
              ColoredBox(
                color: colorScheme.surface.withValues(alpha: 0.58),
                child: Center(
                  child: Icon(
                    track.isBlocked
                        ? Icons.block_rounded
                        : Icons.cloud_off_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.isPlayable});

  final bool isPlayable;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: isPlayable
              ? colorScheme.onSurfaceVariant
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _TrackMetadata extends StatelessWidget {
  const _TrackMetadata({required this.track, required this.isPlayable});

  final LibraryTrack track;
  final bool isPlayable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final artistParts = <String>[
      track.artistName,
      if (track.featuredArtists.isNotEmpty)
        'feat. ${track.featuredArtists.join(', ')}',
    ];

    final albumTitle = track.albumTitle.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isPlayable
                ? colorScheme.onSurface
                : colorScheme.onSurface.withValues(alpha: 0.58),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          artistParts.join(' '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (albumTitle.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(
            albumTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
            ),
          ),
        ],
        if (!isPlayable) ...[
          const SizedBox(height: 3),
          Text(
            track.isBlocked ? 'Blocked' : 'Unavailable',
            key: ValueKey<String>(
              track.isBlocked
                  ? 'track-blocked-${track.songId}'
                  : 'track-unavailable-${track.songId}',
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyTracksState extends StatelessWidget {
  const _EmptyTracksState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.library_music_rounded,
            size: 42,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'No tracks yet',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Import music to start building your library.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

enum _TrackMenuAction {
  playNext,
  addToQueue,
  editDetails,
  changeArtwork,
  clearArtwork,
  toggleBlocked,
}

class _LibraryLoadError extends StatelessWidget {
  const _LibraryLoadError({required this.message, required this.onRetry});

  final String message;
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
            Text(message, textAlign: TextAlign.center),
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
