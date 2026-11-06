import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../../data/engines/support/sonus_shuffle_order.dart';
import '../../../../core/design/sonus_artwork_palette.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_image.dart';
import '../../../../core/design/widgets/sonus_artwork_atmosphere_builder.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../application/controllers/playback_coordinator.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/models/playback_track.dart';
import '../controllers/playback_state_controller.dart';

class PlaybackQueuePage extends StatelessWidget {
  const PlaybackQueuePage({super.key, this.artworkPalette});

  /// Where the current song's artwork colours come from; the app-wide
  /// cache by default.
  final SonusArtworkPalette? artworkPalette;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlaybackStateController>().state;
    final coordinator = context.read<PlaybackCoordinator>();
    final colors = SonusTheme.of(context).colors;

    // A subtle wash of the current song's artwork behind the list (SN-50
    // D-Q18); flat theme colours when Decoration is off, High contrast or
    // Low effects is on, or text would lose contrast.
    return SonusArtworkAtmosphereBuilder(
      artworkPath: state.queue.currentTrack?.artworkPath,
      palette: artworkPalette,
      builder: (context, atmosphere) => Scaffold(
        key: const ValueKey<String>('playback-queue-page'),
        backgroundColor: colors.background,
        appBar: AppBar(
          title: const Text('Queue'),
          centerTitle: true,
          backgroundColor: atmosphere.background,
          actions: [
            IconButton(
              key: const ValueKey<String>('playback-queue-clear'),
              tooltip: 'Clear queue',
              icon: const Icon(Icons.clear_all_rounded),
              onPressed: state.queue.hasCurrentTrack && state.queue.length > 1
                  ? () => _confirmClear(context, coordinator, state)
                  : null,
            ),
          ],
        ),
        body: DecoratedBox(
          key: const ValueKey<String>('playback-queue-atmosphere'),
          decoration: BoxDecoration(
            color: atmosphere.isTinted ? null : colors.background,
            gradient: atmosphere.isTinted
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [atmosphere.background, colors.background],
                  )
                : null,
          ),
          child: state.queue.isEmpty
              ? const SonusStateView(
                  key: ValueKey<String>('playback-queue-empty'),
                  icon: Icons.queue_music_rounded,
                  title: 'Your queue is empty',
                  message: 'Play or queue a song to see it here.',
                )
              : _QueueContent(state: state, coordinator: coordinator),
        ),
      ),
    );
  }
}

/// Asks before clearing (SN-50 A2): only the other queue entries go; the
/// song playing now keeps playing, and nothing leaves the library.
Future<void> _confirmClear(
  BuildContext context,
  PlaybackCoordinator coordinator,
  PlaybackState state,
) async {
  final others = state.queue.length - 1;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey<String>('playback-queue-clear-dialog'),
      title: const Text('Clear queue?'),
      content: Text(
        '${others == 1 ? '1 other song' : '$others other songs'} will be '
        'removed from the queue. The song playing now keeps playing. Your '
        'library and playlists are not changed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey<String>('playback-queue-clear-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Clear'),
        ),
      ],
    ),
  );
  if (confirmed == true) await coordinator.clearQueue();
}

class _QueueContent extends StatelessWidget {
  const _QueueContent({required this.state, required this.coordinator});

  final PlaybackState state;
  final PlaybackCoordinator coordinator;

  /// One identity per queue entry, for row keys: the song's id for its first
  /// occurrence and `songId#n` for its nth. A song can be queued more than
  /// once, and rows with equal keys break the reorderable list. Unlike an
  /// index, this follows a distinct song's row through moves and removals.
  static List<String> entryIds(List<PlaybackTrack> tracks) {
    final seen = <String, int>{};

    return [
      for (final track in tracks)
        switch (seen.update(track.songId, (n) => n + 1, ifAbsent: () => 1)) {
          1 => track.songId,
          final n => '${track.songId}#$n',
        },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final queue = state.queue;
    final gutter = SonusTheme.of(context).metrics.pageGutter;
    final ids = entryIds(queue.tracks);
    // Played in this cycle, per entry: before the current one in play
    // order (the shuffle order while shuffled).
    final played = playedQueueIndices(
      length: queue.length,
      currentIndex: queue.currentIndex,
      shuffleOrder: state.shuffleEnabled ? coordinator.shuffleOrder : null,
    );

    // The current song is the highlighted row; there is no separate
    // summary card repeating it (SN-50 D-Q18).
    return SafeArea(
      top: false,
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
            coordinator.moveQueueTrack(oldIndex: oldIndex, newIndex: newIndex),
          );
        },
        itemBuilder: (context, index) {
          final track = queue.tracks[index];
          final isCurrent = index == queue.currentIndex;

          return _QueueTrackRow(
            key: ValueKey<String>('queue-track-${ids[index]}'),
            entryId: ids[index],
            track: track,
            index: index,
            count: queue.length,
            isCurrent: isCurrent,
            isPlayed: !isCurrent && played.contains(index),
            coordinator: coordinator,
          );
        },
      ),
    );
  }
}

class _QueueTrackRow extends StatelessWidget {
  const _QueueTrackRow({
    super.key,
    required this.entryId,
    required this.track,
    required this.index,
    required this.count,
    required this.isCurrent,
    required this.coordinator,
    this.isPlayed = false,
  });

  /// This entry's identity in the queue (see [_QueueContent.entryIds]).
  final String entryId;
  final PlaybackTrack track;
  final int index;
  final int count;
  final bool isCurrent;

  /// Already played in this cycle: dimmed and labelled, still selectable.
  final bool isPlayed;
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
            key: ValueKey<String>('queue-track-open-$entryId'),
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
                  Opacity(
                    opacity: isPlayed ? 0.45 : 1,
                    child: SonusArtworkImage(path: track.artworkPath, size: 48),
                  ),
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
                                key: ValueKey<String>('queue-current-$entryId'),
                                semanticLabel: 'Now playing',
                                size: 18,
                                color: colors.accentPrimary,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                track.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: isPlayed
                                      ? colors.textSecondary
                                      : colors.textPrimary,
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
                          isPlayed
                              ? 'Played · ${track.displayArtist}'
                              : track.displayArtist,
                          key: isPlayed
                              ? ValueKey<String>('queue-played-$entryId')
                              : null,
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
                    key: ValueKey<String>('queue-remove-$entryId'),
                    tooltip: 'Remove ${track.displayTitle} from queue',
                    color: colors.textSecondary,
                    onPressed: () {
                      unawaited(coordinator.removeFromQueue(index));
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                  ReorderableDragStartListener(
                    key: ValueKey<String>('queue-drag-$entryId'),
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
