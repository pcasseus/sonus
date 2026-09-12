import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_track.dart';
import '../../application/models/library_track_order.dart';
import '../../application/repositories/library_query_repository.dart';
import '../controllers/library_tracks_controller.dart';

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
      artworkAssignmentService: context.read<ArtworkAssignmentService?>(),
      artworkFilePicker: context.read<ArtworkFilePicker?>(),
    );

    unawaited(_controller!.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (controller == null) {
      return const SizedBox(
        key: ValueKey<String>('app-destination-tracks'),
        child: Center(child: Text('Loading tracks…')),
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
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.music_note_rounded, size: 56),
                  SizedBox(height: 16),
                  Center(
                    child: Text(
                      'No tracks yet',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Center(
                    child: Text('Import music to start building your library.'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              _TracksToolbar(controller: controller),
              const Divider(height: 1),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ListView.builder(
                    key: const PageStorageKey<String>('tracks-list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: controller.tracks.length,
                    itemBuilder: (context, index) {
                      final track = controller.tracks[index];

                      return _TrackTile(
                        track: track,
                        isPlayable: controller.isTrackPlayable(track),
                        canEditArtwork: controller.canEditArtwork,
                        onPlay: () => controller.playTrack(track),
                        onPlayNext: () => controller.playNext(track),
                        onAddToQueue: () => controller.addToQueue(track),
                        onChangeArtwork: () =>
                            _changeArtwork(controller, track),
                        onClearArtwork: () => _clearArtwork(controller, track),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
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

class _TracksToolbar extends StatelessWidget {
  const _TracksToolbar({required this.controller});

  final LibraryTracksController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<LibraryTrackOrder>(
              key: const ValueKey<String>('tracks-order-dropdown'),
              initialValue: controller.order,
              decoration: const InputDecoration(
                labelText: 'Order',
                border: OutlineInputBorder(),
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
          const SizedBox(width: 12),
          IconButton.filledTonal(
            key: const ValueKey<String>('tracks-shuffle-button'),
            tooltip: controller.isShuffleEnabled ? 'Shuffle on' : 'Shuffle off',
            onPressed: () {
              unawaited(controller.toggleShuffle());
            },
            icon: Icon(
              controller.isShuffleEnabled
                  ? Icons.shuffle_on_rounded
                  : Icons.shuffle_rounded,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const ValueKey<String>('tracks-play-all-button'),
            onPressed: controller.playAll,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play'),
          ),
        ],
      ),
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
    final subtitleParts = <String>[
      track.artistName,
      if (track.albumTitle.trim().isNotEmpty) track.albumTitle,
    ];

    return ListTile(
      key: ValueKey<String>('track-${track.songId}'),
      enabled: isPlayable,
      leading: SizedBox(
        width: 40,
        child: Center(
          child: Text(
            '${track.trackNumber}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleParts.join(' • '),
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
            key: ValueKey<String>('track-menu-${track.songId}'),
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

  String _formatDuration(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    final remainder = safeSeconds % 60;

    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

enum _TrackMenuAction { playNext, addToQueue, changeArtwork, clearArtwork }

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
