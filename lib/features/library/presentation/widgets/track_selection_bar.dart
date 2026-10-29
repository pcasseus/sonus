import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../application/models/library_track.dart';
import '../controllers/track_selection_controller.dart';

/// Wraps a song list that supports multi-select. While [controller] is in
/// selection mode a bar above [child] shows the count, Select all, Clear
/// and the bulk actions; Escape or Back leaves selection mode.
class TrackSelectionScope extends StatefulWidget {
  const TrackSelectionScope({
    super.key,
    required this.controller,
    required this.visibleTracks,
    required this.child,
  });

  final TrackSelectionController controller;

  /// The songs on screen, in display order: Select all picks these and
  /// bulk actions follow this order.
  final List<LibraryTrack> visibleTracks;
  final Widget child;

  @override
  State<TrackSelectionScope> createState() => _TrackSelectionScopeState();
}

class _TrackSelectionScopeState extends State<TrackSelectionScope> {
  final FocusNode _focus = FocusNode(debugLabel: 'track-selection');
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(TrackSelectionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onSelectionChanged);
      widget.controller.addListener(_onSelectionChanged);
    }
  }

  /// Keeps keyboard focus inside the list once selection starts, so
  /// Escape reaches it.
  void _onSelectionChanged() {
    final isActive = widget.controller.isActive;
    if (isActive && !_wasActive && !_focus.hasFocus) _focus.requestFocus();
    _wasActive = isActive;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isActive = controller.isActive;

    return PopScope(
      canPop: !isActive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.exit();
      },
      child: CallbackShortcuts(
        bindings: {
          if (isActive)
            const SingleActivator(LogicalKeyboardKey.escape): controller.exit,
        },
        child: Focus(
          focusNode: _focus,
          child: Column(
            children: [
              if (isActive)
                TrackSelectionBar(
                  controller: controller,
                  visibleTracks: widget.visibleTracks,
                ),
              Expanded(
                key: const ValueKey<String>('track-selection-content'),
                child: widget.child,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSelectionChanged);
    _focus.dispose();
    super.dispose();
  }
}

class TrackSelectionBar extends StatelessWidget {
  const TrackSelectionBar({
    super.key,
    required this.controller,
    required this.visibleTracks,
  });

  final TrackSelectionController controller;
  final List<LibraryTrack> visibleTracks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = controller.selectedIn(visibleTracks);
    final hasSelection = selected.isNotEmpty;
    final allSelected = controller.allSelectedIn(visibleTracks);
    final count = selected.length;

    return Material(
      key: const ValueKey<String>('track-selection-bar'),
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const ValueKey<String>('track-selection-close'),
                    tooltip: 'Leave selection',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: controller.exit,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        count == 1 ? '1 selected' : '$count selected',
                        key: const ValueKey<String>('track-selection-count'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    key: const ValueKey<String>('track-selection-all'),
                    onPressed: allSelected
                        ? null
                        : () => controller.selectAll(
                            visibleTracks.map((track) => track.songId),
                          ),
                    icon: const Icon(Icons.select_all_rounded),
                    label: const Text('Select all'),
                  ),
                  TextButton.icon(
                    key: const ValueKey<String>('track-selection-clear'),
                    onPressed: hasSelection ? controller.clear : null,
                    icon: const Icon(Icons.deselect_rounded),
                    label: const Text('Clear'),
                  ),
                  TextButton.icon(
                    key: const ValueKey<String>('track-selection-queue'),
                    onPressed: hasSelection
                        ? () => unawaited(_addToQueue(context, selected))
                        : null,
                    icon: const Icon(Icons.queue_music_rounded),
                    label: const Text('Add to queue'),
                  ),
                  TextButton.icon(
                    key: const ValueKey<String>('track-selection-playlist'),
                    onPressed: hasSelection
                        ? () => unawaited(_addToPlaylist(context, selected))
                        : null,
                    icon: const Icon(Icons.playlist_add_rounded),
                    label: const Text('Add to playlist'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addToQueue(
    BuildContext context,
    List<LibraryTrack> tracks,
  ) async {
    final playback = context.read<PlaybackCoordinator?>();
    final messenger = ScaffoldMessenger.of(context);

    if (playback == null) {
      _show(messenger, 'The player is still starting. Try again in a moment.');
      return;
    }

    try {
      final added = await playback.addTracksToQueue(tracks);
      controller.exit();
      _show(messenger, queueMessage(added: added, total: tracks.length));
    } catch (error, stackTrace) {
      developer.log(
        'Adding ${tracks.length} songs to the queue failed '
        '(${error.runtimeType})',
        name: 'sonus.library',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      _show(messenger, 'Could not add the songs to the queue.');
    }
  }

  Future<void> _addToPlaylist(
    BuildContext context,
    List<LibraryTrack> tracks,
  ) async {
    final updated = await showAddTracksToPlaylistFlow(context, tracks);
    if (updated == true) controller.exit();
  }

  static void _show(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The confirmation after adding [total] selected songs to the queue, of
/// which [added] could be played.
String queueMessage({required int added, required int total}) {
  final skipped = total - added;
  final head = added == 0
      ? 'No songs were added to the queue.'
      : 'Added ${added == 1 ? '1 song' : '$added songs'} to the queue.';

  if (skipped == 0) return head;

  return skipped == 1
      ? '$head 1 unavailable song was skipped.'
      : '$head $skipped unavailable songs were skipped.';
}
