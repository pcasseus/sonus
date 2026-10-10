import 'dart:async';

import 'package:flutter/material.dart';

import '../../../artwork/application/models/cover_art_archive_image.dart';
import '../../../artwork/application/services/cover_art_candidate_discovery_service.dart';
import '../../../artwork/application/services/cover_art_album_edition_import_service.dart';
import '../../application/models/external_metadata_candidate.dart';
import '../../application/models/external_metadata_search_query.dart';
import '../../application/models/library_album_edition.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/external_metadata_proposal_service.dart';
import '../../application/services/metadata_provider.dart';
import '../widgets/musicbrainz_search_dialog.dart';
import '../widgets/cover_art_album_search_dialog.dart';
import '../widgets/cover_art_image_selection_dialog.dart';
import '../../application/models/library_track.dart';
import '../controllers/album_profile_controller.dart';

class AlbumStudioPage extends StatefulWidget {
  const AlbumStudioPage({
    super.key,
    required this.controller,
    required this.userId,
    this.onEditDetails,
    this.onChangeArtwork,
    this.onClearArtwork,
    this.metadataProvider,
    this.coverArtCandidateDiscoveryService,
    this.coverArtAlbumEditionImportService,
    this.externalMetadataApplicationService,
    this.externalMetadataProposalService,
  });

  final AlbumProfileController controller;
  final String? userId;
  final Future<void> Function()? onEditDetails;
  final Future<void> Function()? onChangeArtwork;
  final Future<void> Function()? onClearArtwork;
  final MetadataProvider? metadataProvider;
  final CoverArtCandidateDiscoveryService? coverArtCandidateDiscoveryService;
  final CoverArtAlbumEditionImportService? coverArtAlbumEditionImportService;
  final ExternalMetadataApplicationService? externalMetadataApplicationService;
  final ExternalMetadataProposalService? externalMetadataProposalService;

  @override
  State<AlbumStudioPage> createState() => _AlbumStudioPageState();
}

class _AlbumStudioPageState extends State<AlbumStudioPage> {
  bool _autoRenumber = false;
  bool _isSavingOrder = false;
  bool _isApplyingMusicBrainz = false;
  bool _isSearchingCoverArt = false;

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
          body: Column(
            children: [
              _AlbumStudioManagement(
                onEditDetails: widget.onEditDetails,
                onChangeArtwork: widget.onChangeArtwork,
                onClearArtwork: widget.onClearArtwork,
                onSearchCoverArt:
                    !_isSearchingCoverArt &&
                        widget.metadataProvider != null &&
                        widget.coverArtCandidateDiscoveryService != null &&
                        widget.coverArtAlbumEditionImportService != null &&
                        controller.album != null &&
                        edition != null
                    ? _searchCoverArt
                    : null,
                onSearchMusicBrainz:
                    widget.metadataProvider != null &&
                        widget.externalMetadataApplicationService != null &&
                        widget.externalMetadataProposalService != null &&
                        !_isApplyingMusicBrainz
                    ? _searchMusicBrainz
                    : null,
              ),
              if (edition == null)
                const Expanded(
                  child: Center(
                    child: Text('No album edition is available to edit.'),
                  ),
                )
              else ...[
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
                      ? const Center(child: Text('No tracks in this edition.'))
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
            ],
          ),
        );
      },
    );
  }

  Future<void> _searchCoverArt() async {
    if (_isSearchingCoverArt) return;

    final album = controller.album;
    final selectedEditionId = controller.selectedEdition?.editionId;
    final provider = widget.metadataProvider;
    final discovery = widget.coverArtCandidateDiscoveryService;
    final importService = widget.coverArtAlbumEditionImportService;

    if (album == null ||
        selectedEditionId == null ||
        provider == null ||
        discovery == null ||
        importService == null) {
      return;
    }

    setState(() {
      _isSearchingCoverArt = true;
    });

    try {
      final candidate = await showDialog<ExternalMetadataCandidate>(
        context: context,
        builder: (_) => CoverArtAlbumSearchDialog(
          provider: provider,
          query: ExternalMetadataSearchQuery(
            entityKind: ExternalMetadataEntityKind.album,
            title: album.title,
            artistName: album.artistName,
          ),
        ),
      );

      if (!mounted || candidate == null) {
        return;
      }

      try {
        final images = await discovery.discover(candidate);

        if (!mounted) return;

        final image = await showDialog<CoverArtArchiveImage>(
          context: context,
          builder: (_) => CoverArtImageSelectionDialog(
            images: images,
            albumTitle: candidate.displayName,
          ),
        );

        if (!mounted || image == null) return;

        try {
          final result = await importService.importImage(
            albumEditionId: selectedEditionId,
            image: image,
            userId: widget.userId,
          );

          if (!mounted) return;

          if (!result.applied) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                key: ValueKey<String>(
                  'album-studio-cover-art-import-protected',
                ),
                content: Text(
                  'Existing album artwork is protected and was not replaced.',
                ),
              ),
            );
            return;
          }

          if (result.changed) {
            await controller.refresh();
            if (!mounted) return;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              key: ValueKey<String>(
                result.changed
                    ? 'album-studio-cover-art-import-success'
                    : 'album-studio-cover-art-import-unchanged',
              ),
              content: Text(
                result.changed
                    ? 'Album artwork updated.'
                    : 'Album artwork is already up to date.',
              ),
            ),
          );
        } catch (_) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              key: ValueKey<String>('album-studio-cover-art-import-error'),
              content: Text('Could not import album artwork.'),
            ),
          );
        }
      } catch (_) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: ValueKey<String>('album-studio-cover-art-search-error'),
            content: Text('Could not retrieve Cover Art Archive artwork.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingCoverArt = false;
        });
      }
    }
  }

  Future<void> _searchMusicBrainz() async {
    final album = controller.album;
    final provider = widget.metadataProvider;
    final applicationService = widget.externalMetadataApplicationService;
    final proposalService = widget.externalMetadataProposalService;

    if (album == null ||
        provider == null ||
        applicationService == null ||
        proposalService == null ||
        _isApplyingMusicBrainz) {
      return;
    }

    setState(() {
      _isApplyingMusicBrainz = true;
    });

    try {
      final selection = await showDialog<MusicBrainzSearchSelection>(
        context: context,
        builder: (dialogContext) {
          return MusicBrainzSearchDialog(
            provider: provider,
            query: ExternalMetadataSearchQuery(
              entityKind: ExternalMetadataEntityKind.album,
              title: album.title,
              artistName: album.artistName,
            ),
            previewer: (candidate) {
              return proposalService.previewAlbum(
                albumId: album.albumId,
                candidate: candidate,
              );
            },
            applier: (candidate) {
              return applicationService.applyAlbumCandidate(
                userId: widget.userId,
                albumId: album.albumId,
                candidate: candidate,
              );
            },
          );
        },
      );

      if (!mounted || selection == null) {
        return;
      }

      await controller.refresh();

      if (!mounted) {
        return;
      }

      final result = selection.result;

      final message = result.requiresReview
          ? 'MusicBrainz match selected. Some fields still require review.'
          : result.hasProtectedFields
          ? 'MusicBrainz match selected. Protected fields were not changed.'
          : result.entityChanged
          ? 'MusicBrainz metadata applied.'
          : 'MusicBrainz metadata already matched this album.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey<String>(
            'album-studio-musicbrainz-result-message',
          ),
          content: Text(message),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isApplyingMusicBrainz = false;
        });
      }
    }
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

class _AlbumStudioManagement extends StatelessWidget {
  const _AlbumStudioManagement({
    required this.onEditDetails,
    required this.onChangeArtwork,
    required this.onClearArtwork,
    required this.onSearchCoverArt,
    required this.onSearchMusicBrainz,
  });

  final Future<void> Function()? onEditDetails;
  final Future<void> Function()? onChangeArtwork;
  final Future<void> Function()? onClearArtwork;
  final Future<void> Function()? onSearchCoverArt;
  final Future<void> Function()? onSearchMusicBrainz;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Card(
        child: Column(
          children: [
            ListTile(
              key: const ValueKey<String>('album-studio-edit-details'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit album details'),
              subtitle: const Text(
                'Title, artist, edition, release date, and genre',
              ),
              enabled: onEditDetails != null,
              onTap: onEditDetails == null
                  ? null
                  : () {
                      unawaited(onEditDetails!());
                    },
            ),
            const Divider(height: 1),
            ListTile(
              key: const ValueKey<String>('album-studio-search-musicbrainz'),
              leading: const Icon(Icons.travel_explore_rounded),
              title: const Text('Search MusicBrainz'),
              subtitle: const Text(
                'Find a MusicBrainz album match and apply allowed metadata.',
              ),
              enabled: onSearchMusicBrainz != null,
              onTap: onSearchMusicBrainz == null
                  ? null
                  : () {
                      unawaited(onSearchMusicBrainz!());
                    },
            ),
            const Divider(height: 1),
            ListTile(
              key: const ValueKey<String>('album-studio-search-cover-art'),
              leading: const Icon(Icons.image_search_rounded),
              title: const Text('Search Cover Art Archive'),
              subtitle: const Text(
                'Find album artwork without changing MusicBrainz metadata.',
              ),
              enabled: onSearchCoverArt != null,
              onTap: onSearchCoverArt == null
                  ? null
                  : () {
                      unawaited(onSearchCoverArt!());
                    },
            ),
            const Divider(height: 1),
            ListTile(
              key: const ValueKey<String>('album-studio-change-artwork'),
              leading: const Icon(Icons.image_rounded),
              title: const Text('Change artwork'),
              enabled: onChangeArtwork != null,
              onTap: onChangeArtwork == null
                  ? null
                  : () {
                      unawaited(onChangeArtwork!());
                    },
            ),
            ListTile(
              key: const ValueKey<String>('album-studio-clear-artwork'),
              leading: const Icon(Icons.hide_image_rounded),
              title: const Text('Clear artwork'),
              enabled: onClearArtwork != null,
              onTap: onClearArtwork == null
                  ? null
                  : () {
                      unawaited(onClearArtwork!());
                    },
            ),
          ],
        ),
      ),
    );
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
