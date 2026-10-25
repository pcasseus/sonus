import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_artwork_palette.dart';
import '../../../../core/design/sonus_atmosphere_colors.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../../core/design/widgets/sonus_track_tile.dart';

import '../../../library/application/models/library_track.dart';
import '../../../library/presentation/pages/album_profile_page.dart';
import '../../../library/presentation/pages/artist_profile_page.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/playlist_track.dart';
import '../../application/services/playlist_service.dart';
import '../controllers/playlist_detail_controller.dart';
import '../widgets/playlist_cover.dart';

class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.playlistId,
    required this.initialName,
    this.artworkPalette,
  });

  final String playlistId;
  final String initialName;

  /// Where artwork colours come from; the app-wide cache by default.
  final SonusArtworkPalette? artworkPalette;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  PlaylistService? _service;
  PlaylistDetailController? _controller;

  // Artwork atmosphere, as on the Album Profile: theme colours first, the
  // cover's colours once extracted.
  SonusArtworkPalette get _palette =>
      widget.artworkPalette ?? SonusArtworkPalette.shared;
  String? _atmospherePath;
  Brightness? _atmosphereBrightness;
  SonusArtworkColors? _artworkColors;

  /// Never sets state synchronously, so it is safe to call while building.
  void _requestAtmosphere(String? artworkPath, Brightness brightness) {
    if (artworkPath == _atmospherePath && brightness == _atmosphereBrightness) {
      return;
    }
    _atmospherePath = artworkPath;
    _atmosphereBrightness = brightness;

    unawaited(
      _palette.colorsFor(artworkPath, brightness: brightness).then((colors) {
        if (!mounted ||
            artworkPath != _atmospherePath ||
            brightness != _atmosphereBrightness ||
            colors == _artworkColors) {
          return;
        }
        setState(() {
          _artworkColors = colors;
        });
      }),
    );
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    _requestAtmosphere(_coverPath(controller), Theme.of(context).brightness);
  }

  /// The first visible song's artwork, used as the playlist's cover.
  String? _coverPath(PlaylistDetailController controller) {
    for (final entry in controller.tracks) {
      if (!controller.isTrackVisible(entry.track)) continue;
      final path = entry.track.artworkPath?.trim();
      if (path != null && path.isNotEmpty) return path;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final service = context.watch<PlaylistService?>();

    if (identical(service, _service)) {
      return;
    }

    _controller?.removeListener(_onControllerChanged);
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

    controller.addListener(_onControllerChanged);
    unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final tokens = SonusTheme.of(context);

    if (controller != null) {
      _requestAtmosphere(_coverPath(controller), Theme.of(context).brightness);
    }

    final target = SonusArtworkAtmosphere.resolve(
      colors: tokens.colors,
      decoration: tokens.decoration,
      artwork: _artworkColors,
    );
    final reduceMotion =
        tokens.motion.reduced || MediaQuery.disableAnimationsOf(context);

    return TweenAnimationBuilder<SonusAtmosphereColors>(
      tween: SonusAtmosphereColorsTween(end: SonusAtmosphereColors.of(target)),
      duration: reduceMotion ? Duration.zero : tokens.motion.baseMedium,
      curve: tokens.motion.curve,
      builder: (context, atmosphere, _) =>
          _buildPage(context, controller, atmosphere),
    );
  }

  Widget _buildPage(
    BuildContext context,
    PlaylistDetailController? controller,
    SonusAtmosphereColors atmosphere,
  ) {
    return Scaffold(
      key: const ValueKey<String>('playlist-detail-page'),
      backgroundColor: atmosphere.background,
      appBar: AppBar(
        backgroundColor: atmosphere.background,
        surfaceTintColor: Colors.transparent,
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
              builder: (context, _) => _buildBody(controller, atmosphere),
            ),
    );
  }

  Widget _buildBody(
    PlaylistDetailController controller,
    SonusAtmosphereColors atmosphere,
  ) {
    if (controller.isLoading && controller.detail == null) {
      return const SonusStateView.loading();
    }

    if (controller.hasError && controller.detail == null) {
      return _DetailError(onRetry: controller.load);
    }

    if (controller.isNotFound) {
      return const _PlaylistNotFound();
    }

    final detail = controller.detail;

    if (detail == null) {
      return const SonusStateView.loading();
    }

    final visibleTracks = controller.tracks
        .where((entry) => controller.isTrackVisible(entry.track))
        .toList(growable: false);
    final gutter = SonusTheme.of(context).metrics.pageGutter;
    final bottomInset = 120 + MediaQuery.paddingOf(context).bottom;

    // The header scrolls with the songs, so small screens keep the list in
    // view.
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlaylistDetailHeader(
          playlistName: detail.playlist.name,
          trackCount: visibleTracks.length,
          coverPath: _coverPath(controller),
          atmosphere: atmosphere,
          hasPlayableTracks: controller.hasPlayableTracks,
          isShuffleEnabled: controller.isShuffleEnabled,
          isBusy: controller.isMutating,
          onPlayAll: controller.playAll,
          onToggleShuffle: controller.toggleShuffle,
        ),
        if (controller.hasError)
          _DetailErrorBanner(onRetry: controller.refresh),
      ],
    );

    if (visibleTracks.isEmpty) {
      return RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: header),
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyPlaylistDetail(),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ReorderableListView.builder(
        key: const PageStorageKey<String>('playlist-detail-tracks'),
        physics: const AlwaysScrollableScrollPhysics(),
        header: header,
        buildDefaultDragHandles: false,
        padding: EdgeInsets.fromLTRB(gutter - 6, 0, gutter - 6, bottomInset),
        itemCount: visibleTracks.length,
        // ignore: deprecated_member_use
        onReorder: (oldIndex, newIndex) {
          unawaited(
            controller.reorderVisible(oldIndex: oldIndex, newIndex: newIndex),
          );
        },
        itemBuilder: (context, index) {
          final entry = visibleTracks[index];

          return _PlaylistTrackTile(
            key: ValueKey<String>(entry.item.id),
            entry: entry,
            index: index,
            count: visibleTracks.length,
            isPlayable: controller.isTrackPlayable(entry.track),
            tileColor: atmosphere.surface,
            onPlay: () => controller.playTrack(entry.track),
            onPlayNext: () => controller.playNext(entry.track),
            onAddToQueue: () => controller.addToQueue(entry.track),
            onRemove: () => _removeTrack(controller, entry),
            // Same index convention as dragging: a move down targets the
            // slot after the next song.
            onMove: (offset) => controller.reorderVisible(
              oldIndex: index,
              newIndex: offset < 0 ? index - 1 : index + 2,
            ),
            onGoToAlbum: () => _openAlbum(entry.track),
            onGoToArtist: () => _openArtist(entry.track),
          );
        },
      ),
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
              key: const ValueKey<String>('playlist-delete-confirm-button'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
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
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }
}

class _PlaylistDetailHeader extends StatelessWidget {
  const _PlaylistDetailHeader({
    required this.playlistName,
    required this.trackCount,
    required this.coverPath,
    required this.atmosphere,
    required this.hasPlayableTracks,
    required this.isShuffleEnabled,
    required this.isBusy,
    required this.onPlayAll,
    required this.onToggleShuffle,
  });

  final String playlistName;
  final int trackCount;
  final String? coverPath;
  final SonusAtmosphereColors atmosphere;
  final bool hasPlayableTracks;
  final bool isShuffleEnabled;
  final bool isBusy;
  final Future<void> Function() onPlayAll;
  final Future<void> Function() onToggleShuffle;

  /// From this width the cover sits beside the title, keeping songs in view.
  static const double wideLayoutWidth = 560;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: atmosphere.isTinted
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [atmosphere.surface, atmosphere.background],
              )
            : null,
        color: atmosphere.isTinted ? null : atmosphere.background,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tokens.metrics.pageGutter,
          8,
          tokens.metrics.pageGutter,
          16,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= wideLayoutWidth) {
              final size = (constraints.maxWidth * 0.26).clamp(120.0, 200.0);
              return Row(
                children: [
                  PlaylistCover(size: size, artworkPath: coverPath),
                  const SizedBox(width: 24),
                  Expanded(child: _details(context, centered: false)),
                ],
              );
            }

            final size = (constraints.maxWidth * 0.5).clamp(120.0, 220.0);
            return Column(
              children: [
                PlaylistCover(size: size, artworkPath: coverPath),
                const SizedBox(height: 16),
                _details(context, centered: true),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _details(BuildContext context, {required bool centered}) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(tokens.metrics.controlRadius);
    final canPlay = hasPlayableTracks && !isBusy;

    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          playlistName,
          key: const ValueKey<String>('playlist-detail-title'),
          textAlign: centered ? TextAlign.center : TextAlign.start,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          trackCount == 1 ? '1 song' : '$trackCount songs',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey<String>('playlist-play-all-button'),
                onPressed: canPlay ? () => unawaited(onPlayAll()) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: atmosphere.accent,
                  foregroundColor: atmosphere.onAccent,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: radius),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play all', maxLines: 1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: isShuffleEnabled
                  ? FilledButton.tonalIcon(
                      key: const ValueKey<String>('playlist-shuffle-button'),
                      onPressed: canPlay
                          ? () => unawaited(onToggleShuffle())
                          : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: radius),
                      ),
                      icon: const Icon(Icons.shuffle_on_rounded),
                      label: const Text('Shuffle on', maxLines: 1),
                    )
                  : OutlinedButton.icon(
                      key: const ValueKey<String>('playlist-shuffle-button'),
                      onPressed: canPlay
                          ? () => unawaited(onToggleShuffle())
                          : null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: colors.textPrimary,
                        side: BorderSide(color: colors.border),
                        shape: RoundedRectangleBorder(borderRadius: radius),
                      ),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Shuffle', maxLines: 1),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaylistTrackTile extends StatelessWidget {
  const _PlaylistTrackTile({
    super.key,
    required this.entry,
    required this.index,
    required this.count,
    required this.isPlayable,
    required this.tileColor,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onRemove,
    required this.onMove,
    required this.onGoToAlbum,
    required this.onGoToArtist,
  });

  final PlaylistTrack entry;
  final int index;
  final int count;
  final bool isPlayable;
  final Color tileColor;

  final Future<void> Function() onPlay;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onAddToQueue;
  final Future<void> Function() onRemove;

  /// Moves the song by one place; -1 is up, 1 is down.
  final Future<void> Function(int offset) onMove;

  final VoidCallback onGoToAlbum;
  final VoidCallback onGoToArtist;

  @override
  Widget build(BuildContext context) {
    final track = entry.track;
    final theme = Theme.of(context);
    final colors = SonusTheme.of(context).colors;

    return SonusTrackTile(
      inkKey: ValueKey<String>('playlist-track-${entry.item.id}'),
      leadingNumber: '${index + 1}',
      title: track.title,
      subtitle: track.artistName,
      artworkPath: track.artworkPath,
      duration: sonusFormatDuration(track.durationSeconds),
      enabled: isPlayable,
      tileColor: tileColor,
      onTap: () => unawaited(onPlay()),
      status: isPlayable
          ? null
          : Text(
              track.isBlocked ? 'Blacklisted' : 'Unavailable',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<_TrackAction>(
            tooltip: 'Song options',
            onSelected: (action) {
              switch (action) {
                case _TrackAction.playNext:
                  unawaited(onPlayNext());
                case _TrackAction.addToQueue:
                  unawaited(onAddToQueue());
                case _TrackAction.moveUp:
                  unawaited(onMove(-1));
                case _TrackAction.moveDown:
                  unawaited(onMove(1));
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
              // Reordering without dragging, for keyboards and screen
              // readers; uses the same reorder as the drag handle.
              PopupMenuItem(
                key: ValueKey<String>('playlist-move-up-${entry.item.id}'),
                value: _TrackAction.moveUp,
                enabled: index > 0,
                child: const ListTile(
                  leading: Icon(Icons.arrow_upward_rounded),
                  title: Text('Move up'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                key: ValueKey<String>('playlist-move-down-${entry.item.id}'),
                value: _TrackAction.moveDown,
                enabled: index < count - 1,
                child: const ListTile(
                  leading: Icon(Icons.arrow_downward_rounded),
                  title: Text('Move down'),
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
            child: Semantics(
              label: 'Drag to reorder',
              child: SizedBox.square(
                dimension: 48,
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPlaylistDetail extends StatelessWidget {
  const _EmptyPlaylistDetail();

  @override
  Widget build(BuildContext context) {
    return const SonusStateView(
      icon: Icons.playlist_add_rounded,
      title: 'This playlist is empty',
      message: 'Add songs from Sonus track menus.',
    );
  }
}

class _PlaylistNotFound extends StatelessWidget {
  const _PlaylistNotFound();

  @override
  Widget build(BuildContext context) {
    return const SonusStateView(
      icon: Icons.playlist_remove_rounded,
      title: 'This playlist no longer exists.',
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return SonusStateView(
      icon: Icons.error_outline_rounded,
      isError: true,
      title: 'Could not load this playlist.',
      action: FilledButton.tonalIcon(
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
    final tokens = SonusTheme.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tokens.metrics.pageGutter,
        0,
        tokens.metrics.pageGutter,
        8,
      ),
      child: Semantics(
        liveRegion: true,
        child: Material(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Playlist could not refresh.',
                    style: TextStyle(color: scheme.onErrorContainer),
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
        key: const ValueKey<String>('playlist-rename-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(labelText: 'Playlist name'),
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

enum _TrackAction {
  playNext,
  addToQueue,
  moveUp,
  moveDown,
  goToAlbum,
  goToArtist,
  remove,
}

class _NoopListenable extends ChangeNotifier {
  _NoopListenable._();

  static final _NoopListenable instance = _NoopListenable._();
}
