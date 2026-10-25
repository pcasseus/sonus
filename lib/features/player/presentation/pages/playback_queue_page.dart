import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_image.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
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
    final colors = SonusTheme.of(context).colors;

    return Scaffold(
      key: const ValueKey<String>('playback-queue-page'),
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Queue'),
        centerTitle: true,
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: state.queue.isEmpty
          ? const SonusStateView(
              key: ValueKey<String>('playback-queue-empty'),
              icon: Icons.queue_music_rounded,
              title: 'Your queue is empty',
              message: 'Play or queue a song to see it here.',
            )
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
    final gutter = SonusTheme.of(context).metrics.pageGutter;

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
              padding: EdgeInsets.fromLTRB(gutter - 4, 8, gutter - 4, 24),
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
                  count: queue.length,
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
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final gutter = tokens.metrics.pageGutter;

    return Container(
      key: const ValueKey<String>('queue-current-summary'),
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(gutter, 12, gutter, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.raisedSurface,
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          SonusArtworkImage(path: track.artworkPath, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NOW PLAYING',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.accentPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${track.artistName} · ${currentIndex + 1} of '
                  '$totalTracks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
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
    required this.count,
    required this.isCurrent,
    required this.coordinator,
  });

  final PlaybackTrack track;
  final int index;
  final int count;
  final bool isCurrent;
  final PlaybackCoordinator coordinator;

  void _move(int newIndex) {
    unawaited(coordinator.moveQueueTrack(oldIndex: index, newIndex: newIndex));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final radius = BorderRadius.circular(tokens.metrics.cardRadius);

    // Dragging needs a pointer; these give keyboard and screen-reader users
    // the same reordering.
    return Semantics(
      customSemanticsActions: {
        if (index > 0)
          const CustomSemanticsAction(label: 'Move up'): () => _move(index - 1),
        if (index < count - 1)
          const CustomSemanticsAction(label: 'Move down'): () =>
              _move(index + 1),
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Material(
          color: isCurrent ? colors.selection : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            key: ValueKey<String>('queue-track-open-${track.songId}'),
            borderRadius: radius,
            onTap: isCurrent
                ? null
                : () {
                    unawaited(coordinator.skipToIndex(index));
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
              child: Row(
                children: [
                  SonusArtworkImage(path: track.artworkPath, size: 48),
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
                                semanticLabel: 'Now playing',
                                size: 18,
                                color: colors.accentPrimary,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: isCurrent
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey<String>('queue-remove-${track.songId}'),
                    tooltip: 'Remove ${track.title} from queue',
                    color: colors.textSecondary,
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
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
