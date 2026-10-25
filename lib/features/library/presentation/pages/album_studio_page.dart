import '../../data/services/edition_follow_up_dismissals.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../core/design/widgets/sonus_segmented_selector.dart';

import '../../../artwork/application/models/cover_art_archive_image.dart';
import '../../../artwork/application/services/cover_art_candidate_discovery_service.dart';
import '../../../artwork/application/services/cover_art_album_edition_import_service.dart';
import '../../application/models/external_metadata_candidate.dart';
import '../../application/models/external_metadata_search_query.dart';
import '../../application/models/library_album_edition.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/album_edition_management_service.dart';
import '../../application/services/library_organization_service.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/external_metadata_proposal_service.dart';
import '../../application/services/metadata_provider.dart';
import '../widgets/musicbrainz_search_dialog.dart';
import '../widgets/cover_art_album_search_dialog.dart';
import '../widgets/cover_art_image_selection_dialog.dart';
import '../widgets/album_studio/album_studio_editions_section.dart';
import '../widgets/album_studio/album_studio_release_type.dart';
import '../../application/models/library_track.dart';
import '../controllers/album_profile_controller.dart';

class AlbumStudioPage extends StatefulWidget {
  const AlbumStudioPage({
    super.key,
    required this.controller,
    required this.userId,
    this.onEditDetails,
    this.onChangeArtwork,
    this.onRepositionArtwork,
    this.onClearArtwork,
    this.metadataProvider,
    this.coverArtCandidateDiscoveryService,
    this.coverArtAlbumEditionImportService,
    this.externalMetadataApplicationService,
    this.externalMetadataProposalService,
    this.editionManagement,
    this.editionFollowUpDismissals,
    this.organization,
    this.library,
  });

  final AlbumProfileController controller;
  final String? userId;
  final Future<void> Function()? onEditDetails;
  final Future<void> Function()? onChangeArtwork;

  /// Moves or resets the selected edition's cropped cover (SN-45).
  final Future<void> Function()? onRepositionArtwork;
  final Future<void> Function()? onClearArtwork;
  final MetadataProvider? metadataProvider;
  final CoverArtCandidateDiscoveryService? coverArtCandidateDiscoveryService;
  final CoverArtAlbumEditionImportService? coverArtAlbumEditionImportService;
  final ExternalMetadataApplicationService? externalMetadataApplicationService;
  final ExternalMetadataProposalService? externalMetadataProposalService;

  /// Edition management; the section is hidden without it.
  final AlbumEditionManagementService? editionManagement;

  /// Remembers "keep Deluxe as it is" answers (tests inject an in-memory
  /// store; the app uses device preferences).
  final EditionFollowUpDismissals? editionFollowUpDismissals;

  /// Release type (soundtrack, cast recording, compilation).
  final LibraryOrganizationService? organization;

  /// Reads the album's songs for "Choose songs".
  final LibraryQueryRepository? library;

  @override
  State<AlbumStudioPage> createState() => _AlbumStudioPageState();
}

class _AlbumStudioPageState extends State<AlbumStudioPage> {
  bool _autoRenumber = false;
  bool _isSavingOrder = false;
  bool _isApplyingMusicBrainz = false;
  bool _isSearchingCoverArt = false;
  bool _isSorting = false;

  // Album tools start collapsed so the tracks get the screen; the choice
  // lasts while the page is open.
  bool _toolsExpanded = false;

  AlbumProfileController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final edition = controller.selectedEdition;
        final tracks = controller.tracks;
        final tokens = SonusTheme.of(context);
        final gutter = tokens.metrics.pageGutter;
        // Room for anything anchored at the bottom of the app, such as a
        // persistent mini-player that reserves its space.
        final bottom = 32 + MediaQuery.paddingOf(context).bottom;

        // Everything scrolls together: the tools, edition and order
        // controls form the list's header, so they never take space away
        // from the tracks and there is no nested scrolling.
        final header = Padding(
          padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StudioSummary(controller: controller),
              const SizedBox(height: 14),
              _AlbumTools(
                expanded: _toolsExpanded,
                onToggle: () {
                  setState(() {
                    _toolsExpanded = !_toolsExpanded;
                  });
                },
                onEditDetails: widget.onEditDetails,
                onChangeArtwork: widget.onChangeArtwork,
                onRepositionArtwork: widget.onRepositionArtwork,
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
              if (widget.organization != null && controller.album != null) ...[
                const SizedBox(height: 14),
                AlbumStudioReleaseType(
                  albumId: controller.album!.albumId,
                  service: widget.organization!,
                ),
              ],
              if (widget.editionManagement != null) ...[
                const SizedBox(height: 14),
                AlbumStudioEditionsSection(
                  controller: controller,
                  service: widget.editionManagement!,
                  dismissals: widget.editionFollowUpDismissals,
                  library: widget.library,
                  userId: widget.userId,
                ),
              ],
              if (edition != null) ...[
                if (controller.editions.length > 1) ...[
                  const SizedBox(height: 14),
                  _EditionSelector(controller: controller),
                ],
                const SizedBox(height: 14),
                _TrackOrderSection(
                  count: tracks.length,
                  autoRenumber: _autoRenumber,
                  isSaving: _isSavingOrder || _isSorting,
                  onSortByDiscAndTrack: tracks.length < 2
                      ? null
                      : _sortByDiscAndTrack,
                  onAutoRenumberChanged: (value) {
                    setState(() {
                      _autoRenumber = value;
                    });
                  },
                ),
              ],
            ],
          ),
        );

        return Scaffold(
          key: const ValueKey<String>('album-studio-page'),
          appBar: AppBar(title: const Text('Album Studio')),
          body: edition == null
              ? ListView(
                  key: const ValueKey<String>('album-studio-scroll'),
                  padding: EdgeInsets.only(bottom: bottom),
                  children: [
                    header,
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('No album edition is available to edit.'),
                      ),
                    ),
                  ],
                )
              : _StudioTrackList(
                  controller: controller,
                  tracks: tracks,
                  header: header,
                  bottomPadding: bottom,
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
        );
      },
    );
  }

  /// "Sort by disc & track" (J3): back to automatic order for this edition.
  Future<void> _sortByDiscAndTrack() async {
    if (_isSorting) return;
    setState(() => _isSorting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final changed = await controller.sortSelectedEditionByDiscAndTrack(
        userId: widget.userId,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            changed
                ? 'Sorted by disc and track number.'
                : 'Already in disc and track order.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not sort the tracks.')),
      );
    } finally {
      if (mounted) setState(() => _isSorting = false);
    }
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
            reviewedApplier: (candidate, confirmedFields) {
              return applicationService.confirmReviewedAlbumCandidate(
                userId: widget.userId,
                albumId: album.albumId,
                candidate: candidate,
                confirmedFields: confirmedFields,
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

/// The album being edited: artwork, title, edition and track count.
class _StudioSummary extends StatelessWidget {
  const _StudioSummary({required this.controller});

  final AlbumProfileController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final album = controller.album;
    final edition = controller.selectedEdition;
    final editionPath = edition?.artworkPath?.trim();
    final path = editionPath != null && editionPath.isNotEmpty
        ? editionPath
        : controller.artworkPath;
    const size = 56.0;
    final count = controller.tracks.length;

    return MergeSemantics(
      child: Row(
        children: [
          SonusArtworkFrame(
            key: const ValueKey<String>('album-studio-artwork'),
            size: size,
            child: path == null
                ? const _ArtworkFallback()
                : Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    // Decoded at its display size, never at full resolution.
                    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) =>
                        const _ArtworkFallback(),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album?.title ?? 'Album',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (album != null)
                  Text(
                    album.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                Text(
                  [
                    if (edition != null) _editionDisplayLabel(edition),
                    '$count ${count == 1 ? 'track' : 'tracks'}',
                  ].join(' • '),
                  style: theme.textTheme.bodySmall?.copyWith(
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

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback();

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return ColoredBox(
      color: colors.artworkPlaceholder,
      child: Icon(Icons.album_rounded, color: colors.onArtworkPlaceholder),
    );
  }
}

/// Album details, metadata search and artwork actions, behind one header
/// so they stay one tap away without taking room from the tracks.
class _AlbumTools extends StatelessWidget {
  const _AlbumTools({
    required this.expanded,
    required this.onToggle,
    required this.onEditDetails,
    required this.onChangeArtwork,
    this.onRepositionArtwork,
    required this.onClearArtwork,
    required this.onSearchCoverArt,
    required this.onSearchMusicBrainz,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Future<void> Function()? onEditDetails;
  final Future<void> Function()? onChangeArtwork;
  final Future<void> Function()? onRepositionArtwork;
  final Future<void> Function()? onClearArtwork;
  final Future<void> Function()? onSearchCoverArt;
  final Future<void> Function()? onSearchMusicBrainz;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return Material(
      key: const ValueKey<String>('album-studio-tools'),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        side: BorderSide(color: colors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: tokens.motion.short,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: expanded,
              child: InkWell(
                key: const ValueKey<String>('album-studio-tools-toggle'),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, color: colors.textSecondary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Album tools',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            // One line at large text, so the header stays
                            // short; screen readers still hear all of it.
                            Text(
                              'Details, MusicBrainz, Cover Art Archive and '
                              'artwork',
                              maxLines: largeText ? 1 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ExcludeSemantics(
                        child: AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: tokens.motion.short,
                          child: Icon(
                            Icons.expand_more_rounded,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (expanded) ...[
              Divider(height: 1, color: colors.divider),
              _tool(
                key: 'album-studio-edit-details',
                icon: Icons.edit_outlined,
                title: 'Edit album details',
                subtitle: 'Title, artist, edition, release date, and genre',
                action: onEditDetails,
              ),
              _tool(
                key: 'album-studio-search-musicbrainz',
                icon: Icons.travel_explore_rounded,
                title: 'Search MusicBrainz',
                subtitle:
                    'Find a MusicBrainz album match and apply allowed '
                    'metadata.',
                action: onSearchMusicBrainz,
              ),
              _tool(
                key: 'album-studio-search-cover-art',
                icon: Icons.image_search_rounded,
                title: 'Search Cover Art Archive',
                subtitle:
                    'Find album artwork without changing MusicBrainz '
                    'metadata.',
                action: onSearchCoverArt,
              ),
              _tool(
                key: 'album-studio-change-artwork',
                icon: Icons.image_rounded,
                title: 'Change artwork',
                action: onChangeArtwork,
              ),
              if (onRepositionArtwork != null)
                _tool(
                  key: 'album-studio-reposition-artwork',
                  icon: Icons.crop_rounded,
                  title: 'Reposition cover',
                  subtitle: 'Move or zoom this edition\'s cover, or reset it.',
                  action: onRepositionArtwork,
                ),
              _tool(
                key: 'album-studio-clear-artwork',
                icon: Icons.hide_image_rounded,
                title: 'Clear artwork',
                action: onClearArtwork,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tool({
    required String key,
    required IconData icon,
    required String title,
    String? subtitle,
    required Future<void> Function()? action,
  }) {
    return ListTile(
      key: ValueKey<String>(key),
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      enabled: action != null,
      onTap: action == null
          ? null
          : () {
              unawaited(action());
            },
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

    // Its own scroll storage, so it never shares a slot with the page.
    return KeyedSubtree(
      key: const PageStorageKey<String>('album-studio-edition-selector-scroll'),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SonusSegmentedSelector<String>(
          key: const ValueKey<String>('album-studio-edition-selector'),
          segments: [
            for (final edition in controller.editions)
              SonusSegment<String>(
                value: edition.editionId,
                label: _editionDisplayLabel(edition),
              ),
          ],
          selected: selectedEdition.editionId,
          onChanged: (editionId) {
            unawaited(controller.selectEdition(editionId));
          },
        ),
      ),
    );
  }
}

/// The heading and controls above the reorderable tracks.
class _TrackOrderSection extends StatelessWidget {
  const _TrackOrderSection({
    required this.count,
    required this.autoRenumber,
    required this.isSaving,
    required this.onAutoRenumberChanged,
    required this.onSortByDiscAndTrack,
  });

  final int count;
  final bool autoRenumber;
  final bool isSaving;
  final ValueChanged<bool> onAutoRenumberChanged;
  final Future<void> Function()? onSortByDiscAndTrack;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Track order',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            Text(
              '$count',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey<String>('album-studio-sort-disc-track'),
            onPressed: isSaving || onSortByDiscAndTrack == null
                ? null
                : () {
                    unawaited(onSortByDiscAndTrack!());
                  },
            icon: const Icon(Icons.sort_rounded),
            label: const Text('Sort by disc & track'),
          ),
        ),
        SwitchListTile(
          key: const ValueKey<String>('album-studio-auto-renumber'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Auto-renumber after reorder'),
          subtitle: const Text('Renumbers tracks within their disc.'),
          value: autoRenumber,
          onChanged: isSaving ? null : onAutoRenumberChanged,
        ),
        if (isSaving)
          const LinearProgressIndicator(
            key: ValueKey<String>('album-studio-reorder-progress'),
          ),
      ],
    );
  }
}

class _StudioTrackList extends StatelessWidget {
  const _StudioTrackList({
    required this.controller,
    required this.tracks,
    required this.header,
    required this.bottomPadding,
    required this.autoRenumber,
    required this.isBusy,
    required this.userId,
    required this.onReorderStarted,
    required this.onReorderFinished,
    required this.onEditPlacement,
  });

  final AlbumProfileController controller;
  final List<LibraryTrack> tracks;
  final Widget header;
  final double bottomPadding;
  final bool autoRenumber;
  final bool isBusy;
  final String? userId;
  final VoidCallback onReorderStarted;
  final VoidCallback onReorderFinished;
  final Future<void> Function(LibraryTrack track) onEditPlacement;

  @override
  Widget build(BuildContext context) {
    final multiDisc = _usesMultipleDiscs(tracks);
    final gutter = SonusTheme.of(context).metrics.pageGutter;

    return ReorderableListView.builder(
      key: const ValueKey<String>('album-studio-track-list'),
      buildDefaultDragHandles: false,
      header: header,
      footer: tracks.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No tracks in this edition.')),
            )
          : null,
      padding: EdgeInsets.only(bottom: bottomPadding),
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

        return Padding(
          key: ValueKey<String>('album-studio-track-${track.songId}'),
          padding: EdgeInsets.fromLTRB(gutter, 3, gutter, 3),
          child: _StudioTrackRow(
            track: track,
            index: index,
            multiDisc: multiDisc,
            isBusy: isBusy,
            onEditPlacement: onEditPlacement,
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

class _StudioTrackRow extends StatelessWidget {
  const _StudioTrackRow({
    required this.track,
    required this.index,
    required this.multiDisc,
    required this.isBusy,
    required this.onEditPlacement,
  });

  final LibraryTrack track;
  final int index;
  final bool multiDisc;
  final bool isBusy;
  final Future<void> Function(LibraryTrack track) onEditPlacement;

  /// Text scale above which the number column and placement button give
  /// their width to the title; tapping the row still edits the placement.
  static const double _largeTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    const tabular = [FontFeature.tabularFigures()];
    final scaler = MediaQuery.textScalerOf(context);
    final largeText = scaler.scale(1) > _largeTextScale;

    final placement = multiDisc
        ? 'Disc ${track.discNumber} • Track ${track.trackNumber}'
        : 'Track ${track.trackNumber}';
    final details = [
      _formatDuration(track.durationSeconds),
      if (track.featuredArtists.isNotEmpty)
        'feat. ${track.featuredArtists.join(', ')}',
    ];
    final detailStyle = TextStyle(
      color: colors.textSecondary,
      fontFeatures: tabular,
    );

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        side: BorderSide(color: colors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 56,
        textColor: colors.textPrimary,
        iconColor: colors.textSecondary,
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        // At large text the number column gives its width to the title;
        // the placement is still spelled out on the line below. Otherwise
        // at least 40px, growing with the text, so "1-10" never wraps.
        leading: largeText
            ? null
            : ConstrainedBox(
                constraints: BoxConstraints(minWidth: scaler.scale(40)),
                child: Text(
                  multiDisc
                      ? '${track.discNumber}-${track.trackNumber}'
                      : '${track.trackNumber}',
                  key: ValueKey<String>(
                    'album-studio-placement-${track.songId}',
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabular,
                  ),
                ),
              ),
        title: Text(
          track.title,
          maxLines: largeText ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        // The placement stays its own text; duration and credits follow and
        // wrap onto the next line when space runs out.
        subtitle: Wrap(
          children: [
            Text(placement, style: detailStyle),
            for (final detail in details)
              Text(' • $detail', style: detailStyle),
          ],
        ),
        onTap: isBusy ? null : () => onEditPlacement(track),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!largeText)
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
              child: Tooltip(
                message: 'Drag to reorder',
                child: Padding(
                  key: ValueKey<String>('album-studio-drag-${track.songId}'),
                  // A 48px target around the 24px handle.
                  padding: const EdgeInsets.all(12),
                  child: const Icon(Icons.drag_handle_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
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
