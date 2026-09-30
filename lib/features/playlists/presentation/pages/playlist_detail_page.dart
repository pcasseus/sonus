import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../library/application/models/library_track.dart';
import '../../../library/presentation/pages/album_profile_page.dart';
import '../../../library/presentation/pages/artist_profile_page.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../shell/presentation/widgets/shell_playback_slot.dart';
import '../../application/models/playlist_track.dart';
import '../../application/services/playlist_service.dart';
import '../controllers/playlist_detail_controller.dart';

class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.playlistId,
    required this.initialName,
  });

  final String playlistId;
  final String initialName;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  PlaylistService? _service;
  PlaylistDetailController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final service = context.watch<PlaylistService?>();

    if (identical(service, _service)) {
      return;
    }

    _controller?.dispose();
    _controller = null;
    _service = service;

    if (service == null) {
      return;
    }

    final controller = PlaylistDetailController(
      service: service,
      playlistId: widget.playlistId,
      playbackCoordinator: context.read<PlaybackCoordinator?>(),
    );

    _controller = controller;

    unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      key: const ValueKey<String>('playlist-detail-page'),
      appBar: AppBar(
        title: AnimatedBuilder(
          animation: controller ?? _NoopListenable.instance,
          builder: (_, _) {
            return Text(
              controller?.detail?.playlist.name ?? widget.initialName,
            );
          },
        ),
        actions: [
          if (controller != null)
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                return PopupMenuButton<_DetailAction>(
                  key: const ValueKey<String>('playlist-detail-menu'),
                  enabled: !controller.isMutating,
                  onSelected: (action) {
                    switch (action) {
                      case _DetailAction.rename:
                        unawaited(_rename(controller));
                      case _DetailAction.delete:
                        unawaited(_delete(controller));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _DetailAction.rename,
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Rename playlist'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _DetailAction.delete,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded),
                        title: Text('Delete playlist'),
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
          ? const Center(child: Text('Loading playlist...'))
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) => _buildBody(controller),
            ),
      bottomNavigationBar: const ShellPlaybackSlot(),
    );
  }

  Widget _buildBody(PlaylistDetailController controller) {
    if (controller.isLoading && controller.detail == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.hasError && controller.detail == null) {
      return _DetailError(onRetry: controller.load);
    }

    if (controller.isNotFound) {
      return const _PlaylistNotFound();
    }

    final detail = controller.detail;

    if (detail == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final visibleTracks = controller.tracks
        .where((entry) => controller.isTrackVisible(entry.track))
        .toList(growable: false);

    return Column(
      children: [
        _PlaylistDetailHeader(
          playlistName: detail.playlist.name,
          trackCount: visibleTracks.length,
          tracks: visibleTracks,
          hasPlayableTracks: controller.hasPlayableTracks,
          isShuffleEnabled: controller.isShuffleEnabled,
          isBusy: controller.isMutating,
          onPlayAll: controller.playAll,
          onToggleShuffle: controller.toggleShuffle,
        ),
        if (controller.hasError)
          _DetailErrorBanner(onRetry: controller.refresh),
        Expanded(
          child: visibleTracks.isEmpty
              ? const _EmptyPlaylistDetail()
              : RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ReorderableListView.builder(
                    key: const PageStorageKey<String>('playlist-detail-tracks'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 120),
                    itemCount: visibleTracks.length,
                    // ignore: deprecated_member_use
                    onReorder: (oldIndex, newIndex) {
                      unawaited(
                        controller.reorderVisible(
                          oldIndex: oldIndex,
                          newIndex: newIndex,
                        ),
                      );
                    },
                    itemBuilder: (context, index) {
                      final entry = visibleTracks[index];

                      return _PlaylistTrackTile(
                        key: ValueKey<String>(entry.item.id),
                        entry: entry,
                        index: index,
                        isPlayable: controller.isTrackPlayable(entry.track),
                        onPlay: () => controller.playTrack(entry.track),
                        onPlayNext: () => controller.playNext(entry.track),
                        onAddToQueue: () => controller.addToQueue(entry.track),
                        onRemove: () => _removeTrack(controller, entry),
                        onGoToAlbum: () => _openAlbum(entry.track),
                        onGoToArtist: () => _openArtist(entry.track),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _rename(PlaylistDetailController controller) async {
    final currentName = controller.detail?.playlist.name ?? widget.initialName;

    final name = await _showNameDialog(initialValue: currentName);

    if (!mounted || name == null) {
      return;
    }

    final changed = await controller.rename(name);

    if (!mounted || changed) {
      return;
    }

    _showError('Could not rename playlist.');
  }

  Future<void> _delete(PlaylistDetailController controller) async {
    final name = controller.detail?.playlist.name ?? widget.initialName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete playlist?'),
          content: Text(
            'Delete "$name"? Your music files will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    final deleted = await controller.deletePlaylist();

    if (!mounted) {
      return;
    }

    if (deleted) {
      Navigator.of(context).pop();
      return;
    }

    _showError('Could not delete playlist.');
  }

  Future<void> _removeTrack(
    PlaylistDetailController controller,
    PlaylistTrack entry,
  ) async {
    final removed = await controller.removeTrack(entry);

    if (!mounted || removed) {
      return;
    }

    _showError('Could not remove song from playlist.');
  }

  Future<String?> _showNameDialog({required String initialValue}) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return _RenamePlaylistDialog(initialValue: initialValue);
      },
    );
  }

  void _openAlbum(LibraryTrack track) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumProfilePage(
          albumId: track.albumId,
          initialAlbumTitle: track.albumTitle,
        ),
      ),
    );
  }

  void _openArtist(LibraryTrack track) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistProfilePage(
          artistId: track.artistId,
          initialArtistName: track.artistName,
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

class _PlaylistDetailHeader extends StatelessWidget {
  const _PlaylistDetailHeader({
    required this.playlistName,
    required this.trackCount,
    required this.tracks,
    required this.hasPlayableTracks,
    required this.isShuffleEnabled,
    required this.isBusy,
    required this.onPlayAll,
    required this.onToggleShuffle,
  });

  final String playlistName;
  final int trackCount;
  final List<PlaylistTrack> tracks;
  final bool hasPlayableTracks;
  final bool isShuffleEnabled;
  final bool isBusy;
  final Future<void> Function() onPlayAll;
  final Future<void> Function() onToggleShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        children: [
          _DetailCover(tracks: tracks),
          const SizedBox(height: 16),
          Text(
            playlistName,
            key: const ValueKey<String>('playlist-detail-title'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            trackCount == 1 ? '1 song' : '$trackCount songs',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey<String>('playlist-play-all-button'),
                  onPressed: hasPlayableTracks && !isBusy
                      ? () => unawaited(onPlayAll())
                      : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play all'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: isShuffleEnabled
                    ? FilledButton.tonalIcon(
                        key: const ValueKey<String>('playlist-shuffle-button'),
                        onPressed: hasPlayableTracks && !isBusy
                            ? () => unawaited(onToggleShuffle())
                            : null,
                        icon: const Icon(Icons.shuffle_on_rounded),
                        label: const Text('Shuffle on'),
                      )
                    : OutlinedButton.icon(
                        key: const ValueKey<String>('playlist-shuffle-button'),
                        onPressed: hasPlayableTracks && !isBusy
                            ? () => unawaited(onToggleShuffle())
                            : null,
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Shuffle'),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailCover extends StatelessWidget {
  const _DetailCover({required this.tracks});

  final List<PlaylistTrack> tracks;

  @override
  Widget build(BuildContext context) {
    String? path;

    for (final entry in tracks) {
      final candidate = entry.track.artworkPath?.trim();

      if (candidate != null && candidate.isNotEmpty) {
        path = candidate;
        break;
      }
    }

    final colors = Theme.of(context).colorScheme;

    return SizedBox.square(
      dimension: 190,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: path == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.primaryContainer,
                      colors.secondaryContainer,
                    ],
                  ),
                ),
                child: Icon(
                  Icons.queue_music_rounded,
                  size: 76,
                  color: colors.onPrimaryContainer,
                ),
              )
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) {
                  return ColoredBox(
                    color: colors.surfaceContainerHighest,
                    child: Icon(
                      Icons.queue_music_rounded,
                      size: 70,
                      color: colors.onSurfaceVariant,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _PlaylistTrackTile extends StatelessWidget {
  const _PlaylistTrackTile({
    super.key,
    required this.entry,
    required this.index,
    required this.isPlayable,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onRemove,
    required this.onGoToAlbum,
    required this.onGoToArtist,
  });

  final PlaylistTrack entry;
  final int index;
  final bool isPlayable;

  final Future<void> Function() onPlay;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onAddToQueue;
  final Future<void> Function() onRemove;

  final VoidCallback onGoToAlbum;
  final VoidCallback onGoToArtist;

  @override
  Widget build(BuildContext context) {
    final track = entry.track;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: isPlayable
            ? theme.colorScheme.surfaceContainerLow
            : theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('playlist-track-${entry.item.id}'),
          onTap: isPlayable ? () => unawaited(onPlay()) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 2, 7),
            child: Row(
              children: [
                _TrackArtwork(track: track, isPlayable: isPlayable),
                const SizedBox(width: 12),
                Expanded(
                  child: _TrackMetadata(track: track, isPlayable: isPlayable),
                ),
                PopupMenuButton<_TrackAction>(
                  tooltip: 'Song options',
                  onSelected: (action) {
                    switch (action) {
                      case _TrackAction.playNext:
                        unawaited(onPlayNext());
                      case _TrackAction.addToQueue:
                        unawaited(onAddToQueue());
                      case _TrackAction.goToAlbum:
                        onGoToAlbum();
                      case _TrackAction.goToArtist:
                        onGoToArtist();
                      case _TrackAction.remove:
                        unawaited(onRemove());
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _TrackAction.playNext,
                      enabled: isPlayable,
                      child: const ListTile(
                        leading: Icon(Icons.skip_next_rounded),
                        title: Text('Play next'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _TrackAction.addToQueue,
                      enabled: isPlayable,
                      child: const ListTile(
                        leading: Icon(Icons.queue_music_rounded),
                        title: Text('Add to queue'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _TrackAction.goToAlbum,
                      child: ListTile(
                        leading: Icon(Icons.album_outlined),
                        title: Text('Go to album'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: _TrackAction.goToArtist,
                      child: ListTile(
                        leading: Icon(Icons.person_outline_rounded),
                        title: Text('Go to artist'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _TrackAction.remove,
                      child: ListTile(
                        leading: Icon(Icons.playlist_remove_rounded),
                        title: Text('Remove from playlist'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.drag_handle_rounded),
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

class _TrackArtwork extends StatelessWidget {
  const _TrackArtwork({required this.track, required this.isPlayable});

  final LibraryTrack track;
  final bool isPlayable;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final path = track.artworkPath?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: 52,
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
                color: colors.surface.withValues(alpha: 0.58),
                child: Center(
                  child: Icon(
                    track.isBlocked
                        ? Icons.block_rounded
                        : Icons.cloud_off_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
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
    final colors = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(
        Icons.music_note_rounded,
        color: colors.onSurfaceVariant.withValues(alpha: isPlayable ? 1 : 0.6),
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
    final colors = theme.colorScheme;

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
                ? colors.onSurface
                : colors.onSurface.withValues(alpha: 0.58),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          track.artistName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        if (!isPlayable) ...[
          const SizedBox(height: 3),
          Text(
            track.isBlocked ? 'Blacklisted' : 'Unavailable',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyPlaylistDetail extends StatelessWidget {
  const _EmptyPlaylistDetail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 120),
      children: [
        Icon(
          Icons.playlist_add_rounded,
          size: 56,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 18),
        Text(
          'This playlist is empty',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add songs from Sonus track menus.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PlaylistNotFound extends StatelessWidget {
  const _PlaylistNotFound();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'This playlist no longer exists.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.tonalIcon(
        onPressed: () {
          unawaited(onRetry());
        },
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
      ),
    );
  }
}

class _DetailErrorBanner extends StatelessWidget {
  const _DetailErrorBanner({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded),
              const SizedBox(width: 8),
              const Expanded(child: Text('Playlist could not refresh.')),
              TextButton(
                onPressed: () {
                  unawaited(onRetry());
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenamePlaylistDialog extends StatefulWidget {
  const _RenamePlaylistDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_RenamePlaylistDialog> createState() => _RenamePlaylistDialogState();
}

class _RenamePlaylistDialogState extends State<_RenamePlaylistDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.text.trim();

    return AlertDialog(
      title: const Text('Rename playlist'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: value.isEmpty
              ? null
              : () => Navigator.of(context).pop(value),
          child: const Text('Save'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

enum _DetailAction { rename, delete }

enum _TrackAction { playNext, addToQueue, goToAlbum, goToArtist, remove }

class _NoopListenable extends ChangeNotifier {
  _NoopListenable._();

  static final _NoopListenable instance = _NoopListenable._();
}
