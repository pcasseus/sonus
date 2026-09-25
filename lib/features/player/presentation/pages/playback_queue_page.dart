import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/controllers/playback_coordinator.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/playback_track.dart';
import '../controllers/playback_state_controller.dart';

class PlaybackQueuePage extends StatelessWidget {
  const PlaybackQueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlaybackStateController>().state;
    final coordinator = context.read<PlaybackCoordinator>();

    return Scaffold(
      key: const ValueKey<String>('playback-queue-page'),
      appBar: AppBar(title: const Text('Queue'), centerTitle: true),
      body: state.queue.isEmpty
          ? const _EmptyQueue()
          : _QueueContent(state: state, coordinator: coordinator),
    );
  }
}

class _QueueContent extends StatelessWidget {
  const _QueueContent({required this.state, required this.coordinator});

  final PlaybackState state;
  final PlaybackCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    final queue = state.queue;

    return SafeArea(
      top: false,
      child: Column(
        children: [
          if (queue.hasCurrentTrack)
            _CurrentTrackSummary(
              track: queue.currentTrack!,
              currentIndex: queue.currentIndex,
              totalTracks: queue.length,
            ),
          Expanded(
            child: ReorderableListView.builder(
              key: const ValueKey<String>('playback-queue-list'),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: queue.length,
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) {
                if (newIndex == oldIndex) {
                  return;
                }

                unawaited(
                  coordinator.moveQueueTrack(
                    oldIndex: oldIndex,
                    newIndex: newIndex,
                  ),
                );
              },
              itemBuilder: (context, index) {
                final track = queue.tracks[index];
                final isCurrent = index == queue.currentIndex;

                return _QueueTrackRow(
                  key: ValueKey<String>('queue-track-${track.songId}'),
                  track: track,
                  index: index,
                  isCurrent: isCurrent,
                  coordinator: coordinator,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentTrackSummary extends StatelessWidget {
  const _CurrentTrackSummary({
    required this.track,
    required this.currentIndex,
    required this.totalTracks,
  });

  final PlaybackTrack track;
  final int currentIndex;
  final int totalTracks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      key: const ValueKey<String>('queue-current-summary'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NOW PLAYING',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${track.artistName} - ${currentIndex + 1} of $totalTracks',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueTrackRow extends StatelessWidget {
  const _QueueTrackRow({
    super.key,
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.coordinator,
  });

  final PlaybackTrack track;
  final int index;
  final bool isCurrent;
  final PlaybackCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: isCurrent
            ? colorScheme.primaryContainer.withValues(alpha: 0.55)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey<String>('queue-track-open-${track.songId}'),
          borderRadius: BorderRadius.circular(16),
          onTap: isCurrent
              ? null
              : () {
                  unawaited(coordinator.skipToIndex(index));
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                _QueueArtwork(track: track),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isCurrent) ...[
                            Icon(
                              Icons.graphic_eq_rounded,
                              key: ValueKey<String>(
                                'queue-current-${track.songId}',
                              ),
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: isCurrent
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        track.artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey<String>('queue-remove-${track.songId}'),
                  tooltip: 'Remove ${track.title} from queue',
                  onPressed: () {
                    unawaited(coordinator.removeFromQueue(index));
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
                ReorderableDragStartListener(
                  key: ValueKey<String>('queue-drag-${track.songId}'),
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: colorScheme.onSurfaceVariant,
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

class _QueueArtwork extends StatelessWidget {
  const _QueueArtwork({required this.track});

  final PlaybackTrack track;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final path = track.artworkPath?.trim();

    return SizedBox.square(
      dimension: 52,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: colorScheme.surfaceContainerHighest,
          child: path != null && path.isNotEmpty
              ? Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      _QueueArtworkFallback(colorScheme: colorScheme),
                )
              : _QueueArtworkFallback(colorScheme: colorScheme),
        ),
      ),
    );
  }
}

class _QueueArtworkFallback extends StatelessWidget {
  const _QueueArtworkFallback({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      key: const ValueKey<String>('playback-queue-empty'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.queue_music_rounded,
              size: 72,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Your queue is empty',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Play or queue a song to see it here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
