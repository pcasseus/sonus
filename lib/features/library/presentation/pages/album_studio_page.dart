import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/models/library_album_edition.dart';
import '../../application/models/library_track.dart';
import '../controllers/album_profile_controller.dart';

class AlbumStudioPage extends StatefulWidget {
  const AlbumStudioPage({
    super.key,
    required this.controller,
    required this.userId,
  });

  final AlbumProfileController controller;
  final String? userId;

  @override
  State<AlbumStudioPage> createState() => _AlbumStudioPageState();
}

class _AlbumStudioPageState extends State<AlbumStudioPage> {
  bool _autoRenumber = false;
  bool _isSavingOrder = false;

  AlbumProfileController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final edition = controller.selectedEdition;
        final tracks = controller.tracks;

        return Scaffold(
          key: const ValueKey<String>('album-studio-page'),
          appBar: AppBar(title: const Text('Album Studio')),
          body: edition == null
              ? const Center(
                  child: Text('No album edition is available to edit.'),
                )
              : Column(
                  children: [
                    if (controller.editions.length > 1)
                      _EditionSelector(controller: controller),
                    SwitchListTile(
                      key: const ValueKey<String>('album-studio-auto-renumber'),
                      title: const Text('Auto-renumber after reorder'),
                      subtitle: const Text(
                        'Keeps each track on its current disc and '
                        'renumbers tracks within each disc.',
                      ),
                      value: _autoRenumber,
                      onChanged: _isSavingOrder
                          ? null
                          : (value) {
                              setState(() {
                                _autoRenumber = value;
                              });
                            },
                    ),
                    if (_isSavingOrder)
                      const LinearProgressIndicator(
                        key: ValueKey<String>('album-studio-reorder-progress'),
                      ),
                    Expanded(
                      child: tracks.isEmpty
                          ? const Center(
                              child: Text('No tracks in this edition.'),
                            )
                          : _StudioTrackList(
                              controller: controller,
                              tracks: tracks,
                              autoRenumber: _autoRenumber,
                              isBusy: _isSavingOrder,
                              userId: widget.userId,
                              onReorderStarted: () {
                                setState(() {
                                  _isSavingOrder = true;
                                });
                              },
                              onReorderFinished: () {
                                if (!mounted) {
                                  return;
                                }

                                setState(() {
                                  _isSavingOrder = false;
                                });
                              },
                              onEditPlacement: _editPlacement,
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _editPlacement(LibraryTrack track) async {
    final multiDisc = _usesMultipleDiscs(controller.tracks);

    final draft = await showDialog<_TrackPlacementDraft>(
      context: context,
      builder: (dialogContext) {
        return _TrackPlacementDialog(
          track: track,
          initiallyShowDisc: multiDisc || track.discNumber != 1,
        );
      },
    );

    if (!mounted || draft == null) {
      return;
    }

    try {
      final changed = await controller.updateSelectedEditionTrackPlacement(
        userId: widget.userId,
        track: track,
        discNumber: draft.discNumber,
        trackNumber: draft.trackNumber,
      );

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Track placement updated.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update track placement.')),
      );
    }
  }
}

class _EditionSelector extends StatelessWidget {
  const _EditionSelector({required this.controller});

  final AlbumProfileController controller;

  @override
  Widget build(BuildContext context) {
    final selectedEdition = controller.selectedEdition;

    if (selectedEdition == null || controller.editions.length < 2) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<String>(
          key: const ValueKey<String>('album-studio-edition-selector'),
          segments: [
            for (final edition in controller.editions)
              ButtonSegment<String>(
                value: edition.editionId,
                label: Text(_editionDisplayLabel(edition)),
              ),
          ],
          selected: {selectedEdition.editionId},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            if (selection.isEmpty) {
              return;
            }

            unawaited(controller.selectEdition(selection.first));
          },
        ),
      ),
    );
  }
}

class _StudioTrackList extends StatelessWidget {
  const _StudioTrackList({
    required this.controller,
    required this.tracks,
    required this.autoRenumber,
    required this.isBusy,
    required this.userId,
    required this.onReorderStarted,
    required this.onReorderFinished,
    required this.onEditPlacement,
  });

  final AlbumProfileController controller;
  final List<LibraryTrack> tracks;
  final bool autoRenumber;
  final bool isBusy;
  final String? userId;
  final VoidCallback onReorderStarted;
  final VoidCallback onReorderFinished;
  final Future<void> Function(LibraryTrack track) onEditPlacement;

  @override
  Widget build(BuildContext context) {
    final multiDisc = _usesMultipleDiscs(tracks);

    return ReorderableListView.builder(
      key: const ValueKey<String>('album-studio-track-list'),
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      itemCount: tracks.length,
      onReorderItem: isBusy
          ? (_, _) {}
          : (oldIndex, newIndex) {
              unawaited(
                _reorder(context, oldIndex: oldIndex, newIndex: newIndex),
              );
            },
      itemBuilder: (context, index) {
        final track = tracks[index];

        return Card(
          key: ValueKey<String>('album-studio-track-${track.songId}'),
          child: ListTile(
            leading: SizedBox(
              width: 40,
              child: Center(
                child: Text(
                  multiDisc
                      ? '${track.discNumber}-${track.trackNumber}'
                      : '${track.trackNumber}',
                  key: ValueKey<String>(
                    'album-studio-placement-${track.songId}',
                  ),
                ),
              ),
            ),
            title: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: multiDisc
                ? Text('Disc ${track.discNumber} • Track ${track.trackNumber}')
                : Text('Track ${track.trackNumber}'),
            onTap: isBusy ? null : () => onEditPlacement(track),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: ValueKey<String>(
                    'album-studio-edit-placement-${track.songId}',
                  ),
                  tooltip: 'Edit track placement',
                  onPressed: isBusy ? null : () => onEditPlacement(track),
                  icon: const Icon(Icons.numbers_rounded),
                ),
                ReorderableDragStartListener(
                  index: index,
                  enabled: !isBusy,
                  child: Padding(
                    key: ValueKey<String>('album-studio-drag-${track.songId}'),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: const Icon(Icons.drag_handle_rounded),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _reorder(
    BuildContext context, {
    required int oldIndex,
    required int newIndex,
  }) async {
    final targetIndex = newIndex;

    if (targetIndex == oldIndex) {
      return;
    }

    final orderedIds = [for (final track in tracks) track.songId];

    final moved = orderedIds.removeAt(oldIndex);
    orderedIds.insert(targetIndex, moved);

    onReorderStarted();

    try {
      await controller.reorderSelectedEdition(
        userId: userId,
        orderedSongIds: orderedIds,
        autoRenumber: autoRenumber,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reorder tracks.')),
        );
      }
    } finally {
      onReorderFinished();
    }
  }
}

class _TrackPlacementDialog extends StatefulWidget {
  const _TrackPlacementDialog({
    required this.track,
    required this.initiallyShowDisc,
  });

  final LibraryTrack track;
  final bool initiallyShowDisc;

  @override
  State<_TrackPlacementDialog> createState() => _TrackPlacementDialogState();
}

class _TrackPlacementDialogState extends State<_TrackPlacementDialog> {
  late final TextEditingController _trackController;
  late final TextEditingController _discController;
  late bool _showDisc;

  @override
  void initState() {
    super.initState();

    _trackController = TextEditingController(
      text: '${widget.track.trackNumber}',
    );
    _discController = TextEditingController(text: '${widget.track.discNumber}');
    _showDisc = widget.initiallyShowDisc;
  }

  @override
  void dispose() {
    _trackController.dispose();
    _discController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: ValueKey<String>(
        'album-studio-placement-dialog-${widget.track.songId}',
      ),
      title: Text(widget.track.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey<String>('album-studio-track-number-field'),
              controller: _trackController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Track number'),
            ),
            if (_showDisc) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey<String>('album-studio-disc-number-field'),
                controller: _discController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Disc number'),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey<String>('album-studio-show-disc-number'),
                  onPressed: () {
                    setState(() {
                      _showDisc = true;
                    });
                  },
                  child: const Text('Edit disc number'),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey<String>('album-studio-save-placement'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    final trackNumber = int.tryParse(_trackController.text.trim());
    final discNumber = int.tryParse(_discController.text.trim());

    if (trackNumber == null ||
        discNumber == null ||
        trackNumber < 0 ||
        discNumber < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Track and disc numbers must be zero or greater.'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      _TrackPlacementDraft(trackNumber: trackNumber, discNumber: discNumber),
    );
  }
}

class _TrackPlacementDraft {
  const _TrackPlacementDraft({
    required this.trackNumber,
    required this.discNumber,
  });

  final int trackNumber;
  final int discNumber;
}

bool _usesMultipleDiscs(List<LibraryTrack> tracks) {
  if (tracks.isEmpty) {
    return false;
  }

  final discs = <int>{for (final track in tracks) track.discNumber};

  return discs.length > 1 || discs.any((disc) => disc != 1);
}

String _editionDisplayLabel(LibraryAlbumEdition edition) {
  final title = edition.title.trim();

  if (title.isNotEmpty) {
    return title;
  }

  return edition.type.name;
}
