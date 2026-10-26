import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../core/design/widgets/sonus_segmented_selector.dart';
import '../../../artwork/application/models/cover_art_archive_image.dart';
import '../../../artwork/application/services/cover_art_album_edition_import_service.dart';
import '../../../artwork/application/services/cover_art_candidate_discovery_service.dart';
import '../../application/models/external_metadata_candidate.dart';
import '../../application/models/external_metadata_search_query.dart';
import '../../application/models/library_album_edition.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/album_edition_management_service.dart';
import '../../application/services/artist_creation_service.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/external_metadata_proposal_service.dart';
import '../../application/services/library_organization_service.dart';
import '../../application/services/metadata_provider.dart';
import '../../data/services/edition_follow_up_dismissals.dart';
import '../../domain/entities/album_edition.dart';
import '../controllers/album_profile_controller.dart';
import '../widgets/album_studio/album_studio_editions_section.dart';
import '../widgets/album_studio/album_studio_release_type.dart';
import '../widgets/album_studio/release_studio_format.dart';
import '../widgets/cover_art_album_search_dialog.dart';
import '../widgets/cover_art_image_selection_dialog.dart';
import '../widgets/musicbrainz_search_dialog.dart';

/// Release Studio (SN-45): one place to edit a release, in four sections.
///
/// - **Details:** name, owning artist or project, release date, format
///   (Single, EP, Album), kind (soundtrack, cast recording, compilation),
///   genre, and a MusicBrainz lookup.
/// - **Artwork:** the selected edition's cover: replace and crop,
///   reposition, find on Cover Art Archive, or remove. Each edition keeps
///   its own cover.
/// - **Editions:** Standard, Deluxe and others: create (a new edition
///   starts with the Standard songs), rename, make primary, delete.
/// - **Tracklist:** which songs an edition lists, their order, disc and
///   track numbers, and which are bonus tracks.
///
/// Every action exists once. Songs, files and listening history are never
/// deleted or duplicated here.
class ReleaseStudioPage extends StatefulWidget {
  const ReleaseStudioPage({
    super.key,
    required this.controller,
    required this.userId,
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
    this.artistCreation,
    this.initialSection = ReleaseStudioSection.details,
  });

  final AlbumProfileController controller;
  final String? userId;

  /// Picks a new cover for the selected edition and crops it.
  final Future<void> Function()? onChangeArtwork;

  /// Moves or resets the selected edition's cropped cover.
  final Future<void> Function()? onRepositionArtwork;
  final Future<void> Function()? onClearArtwork;
  final MetadataProvider? metadataProvider;
  final CoverArtCandidateDiscoveryService? coverArtCandidateDiscoveryService;
  final CoverArtAlbumEditionImportService? coverArtAlbumEditionImportService;
  final ExternalMetadataApplicationService? externalMetadataApplicationService;
  final ExternalMetadataProposalService? externalMetadataProposalService;

  /// Edition management; editing editions is unavailable without it.
  final AlbumEditionManagementService? editionManagement;

  /// Remembers "keep Deluxe as it is" answers (tests inject an in-memory
  /// store; the app uses device preferences).
  final EditionFollowUpDismissals? editionFollowUpDismissals;

  /// Format and kind of release.
  final LibraryOrganizationService? organization;

  /// Artists for the owner field, and the album's songs for the tracklist.
  final LibraryQueryRepository? library;

  /// Creates (or reuses, by name) a new owner, such as a soundtrack's own
  /// project; without it only existing artists can own the release.
  final ArtistCreationService? artistCreation;

  final ReleaseStudioSection initialSection;

  @override
  State<ReleaseStudioPage> createState() => _ReleaseStudioPageState();
}

enum ReleaseStudioSection { details, artwork, editions, tracklist }

class _ReleaseStudioPageState extends State<ReleaseStudioPage> {
  bool _autoRenumber = false;
  bool _isSavingOrder = false;
  bool _isApplyingMusicBrainz = false;
  bool _isSearchingCoverArt = false;
  bool _isSorting = false;
  bool _isSavingDetails = false;

  /// Bumped after a MusicBrainz apply, so the format reloads.
  int _detailsVersion = 0;

  AlbumProfileController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);

    return DefaultTabController(
      length: ReleaseStudioSection.values.length,
      initialIndex: widget.initialSection.index,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Scaffold(
            key: const ValueKey<String>('release-studio-page'),
            appBar: AppBar(
              title: const Text('Edit Release'),
              bottom: TabBar(
                key: const ValueKey<String>('release-studio-tabs'),
                // Large text keeps every label whole; it scrolls instead.
                isScrollable: scaler.scale(1) > 1.3,
                tabAlignment: scaler.scale(1) > 1.3
                    ? TabAlignment.start
                    : TabAlignment.fill,
                tabs: const [
                  Tab(
                    key: ValueKey<String>('release-studio-tab-details'),
                    text: 'Details',
                  ),
                  Tab(
                    key: ValueKey<String>('release-studio-tab-artwork'),
                    text: 'Artwork',
                  ),
                  Tab(
                    key: ValueKey<String>('release-studio-tab-editions'),
                    text: 'Editions',
                  ),
                  Tab(
                    key: ValueKey<String>('release-studio-tab-tracklist'),
                    text: 'Tracklist',
                  ),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _detailsTab(context),
                _artworkTab(context),
                _editionsTab(context),
                _tracklistTab(context),
              ],
            ),
          );
        },
      ),
    );
  }

  double get _bottomPadding => 32 + MediaQuery.paddingOf(context).bottom;

  EdgeInsets _tabPadding(BuildContext context) {
    final gutter = SonusTheme.of(context).metrics.pageGutter;
    return EdgeInsets.fromLTRB(gutter, 16, gutter, _bottomPadding);
  }

  // Details ---------------------------------------------------------------

  Widget _detailsTab(BuildContext context) {
    final album = controller.album;
    final canEdit = controller.canEditAlbumProfile(widget.userId);
    final organization = widget.organization;
    final releaseDate = album?.releaseDate;

    return ListView(
      key: const ValueKey<String>('release-studio-details'),
      padding: _tabPadding(context),
      children: [
        _StudioSummary(controller: controller),
        const SizedBox(height: 16),
        _StudioCard(
          children: [
            _DetailRow(
              key: const ValueKey<String>('release-studio-name'),
              label: 'Name',
              value: album?.title ?? '',
              onEdit: canEdit && !_isSavingDetails ? _rename : null,
            ),
            _DetailRow(
              key: const ValueKey<String>('release-studio-owner'),
              label: 'Artist or project',
              value: album?.artistName ?? '',
              onEdit: canEdit && !_isSavingDetails && widget.library != null
                  ? _changeOwner
                  : null,
            ),
            _DetailRow(
              key: const ValueKey<String>('release-studio-date'),
              label: 'Release date',
              value: releaseDate == null ? 'Not set' : _formatDate(releaseDate),
              onEdit: canEdit && !_isSavingDetails ? _editReleaseDate : null,
            ),
            _DetailRow(
              key: const ValueKey<String>('release-studio-genre'),
              label: 'Genre',
              value: (album?.genre ?? '').trim().isEmpty
                  ? 'Not set'
                  : album!.genre!,
              onEdit: canEdit && !_isSavingDetails ? _editGenre : null,
            ),
          ],
        ),
        if (_isSavingDetails) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(
            key: ValueKey<String>('release-studio-saving'),
          ),
        ],
        if (organization != null && album != null) ...[
          const SizedBox(height: 16),
          ReleaseStudioFormat(
            key: ValueKey<String>('release-studio-format-$_detailsVersion'),
            albumId: album.albumId,
            service: organization,
          ),
          const SizedBox(height: 16),
          AlbumStudioReleaseType(
            key: ValueKey<String>('release-studio-kind-$_detailsVersion'),
            albumId: album.albumId,
            service: organization,
          ),
        ],
        const SizedBox(height: 16),
        _StudioCard(
          children: [
            _ActionRow(
              tileKey: const ValueKey<String>(
                'album-studio-search-musicbrainz',
              ),
              icon: Icons.travel_explore_rounded,
              title: 'Look up on MusicBrainz',
              subtitle: 'Find this release and review what would change.',
              onTap:
                  widget.metadataProvider != null &&
                      widget.externalMetadataApplicationService != null &&
                      widget.externalMetadataProposalService != null &&
                      !_isApplyingMusicBrainz
                  ? _searchMusicBrainz
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'A match can fill in the name, format and kind. Anything you set '
          'yourself is kept.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: SonusTheme.of(context).colors.textSecondary,
          ),
        ),
      ],
    );
  }

  /// Saves one release-level field; the others keep their values.
  Future<void> _saveDetails({
    String? title,
    String? artistId,
    Object? releaseDate = _unchanged,
    Object? genre = _unchanged,
    required String message,
  }) async {
    final album = controller.album;
    if (album == null) return;

    setState(() => _isSavingDetails = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final changed = await controller.updateProfile(
        userId: widget.userId,
        title: title ?? album.title,
        artistId: artistId ?? album.artistId,
        editionTitle: album.primaryEditionTitle ?? album.title,
        editionType: album.primaryEditionType ?? AlbumEditionType.standard,
        releaseDate: identical(releaseDate, _unchanged)
            ? album.releaseDate
            : releaseDate as DateTime?,
        genre: identical(genre, _unchanged) ? album.genre : genre as String?,
      );
      if (changed) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The release could not be saved.')),
      );
    } finally {
      if (mounted) setState(() => _isSavingDetails = false);
    }
  }

  static const Object _unchanged = Object();

  Future<void> _rename() async {
    final album = controller.album;
    if (album == null) return;

    final name = await _askForText(
      title: 'Rename release',
      label: 'Release name',
      initial: album.title,
      fieldKey: 'release-studio-name-field',
      saveKey: 'release-studio-save-name',
      required: true,
    );
    if (name == null || name == album.title) return;
    await _saveDetails(title: name, message: 'Release renamed.');
  }

  Future<void> _editGenre() async {
    final album = controller.album;
    if (album == null) return;

    final genre = await _askForText(
      title: 'Genre',
      label: 'Genre',
      initial: album.genre ?? '',
      fieldKey: 'release-studio-genre-field',
      saveKey: 'release-studio-save-genre',
    );
    if (genre == null) return;
    await _saveDetails(
      genre: genre.isEmpty ? null : genre,
      message: 'Genre saved.',
    );
  }

  Future<void> _editReleaseDate() async {
    final album = controller.album;
    if (album == null) return;

    final text = await _askForText(
      title: 'Release date',
      label: 'Date (YYYY-MM-DD)',
      initial: album.releaseDate == null ? '' : _formatDate(album.releaseDate!),
      fieldKey: 'release-studio-date-field',
      saveKey: 'release-studio-save-date',
      validator: (value) => value.isEmpty || _parseDate(value) != null
          ? null
          : 'Use a real date, such as 2024-06-21.',
    );
    if (text == null) return;
    await _saveDetails(
      releaseDate: text.isEmpty ? null : _parseDate(text),
      message: text.isEmpty ? 'Release date cleared.' : 'Release date saved.',
    );
  }

  Future<void> _changeOwner() async {
    final album = controller.album;
    final library = widget.library;
    if (album == null || library == null) return;

    final List<LibraryArtist> artists;
    try {
      artists = await library.getArtists();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Artists could not be read.')),
      );
      return;
    }
    if (!mounted) return;

    final artistId = await showDialog<String>(
      context: context,
      builder: (context) => _OwnerDialog(
        artists: artists,
        currentArtistId: album.artistId,
        canCreate: widget.artistCreation != null,
      ),
    );
    if (artistId == _OwnerDialog.newOwner) {
      await _createOwner();
      return;
    }
    if (artistId == null || artistId == album.artistId) return;
    await _saveDetails(
      artistId: artistId,
      message: 'The release now belongs to its new artist.',
    );
  }

  /// Names a new artist or project (the release title, such as a
  /// soundtrack's, is suggested) and makes it the owner. An existing artist
  /// with that name is reused, never duplicated.
  Future<void> _createOwner() async {
    final album = controller.album;
    final creation = widget.artistCreation;
    if (album == null || creation == null) return;

    final name = await _askForText(
      title: 'New artist or project',
      label: 'Name',
      initial: album.title,
      fieldKey: 'release-studio-new-owner-field',
      saveKey: 'release-studio-new-owner-save',
      required: true,
    );
    if (name == null || name.isEmpty || !mounted) return;

    final String artistId;
    try {
      artistId = (await creation.createOrReuse(
        userId: widget.userId,
        name: name,
      )).id;
    } catch (error, stackTrace) {
      developer.log(
        'Could not create the release owner (${error.runtimeType})',
        name: 'sonus.library.release_studio',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The new owner could not be created.')),
      );
      return;
    }
    if (!mounted || artistId == album.artistId) return;
    await _saveDetails(
      artistId: artistId,
      message: 'The release now belongs to $name.',
    );
  }

  Future<String?> _askForText({
    required String title,
    required String label,
    required String initial,
    required String fieldKey,
    required String saveKey,
    bool required = false,
    String? Function(String value)? validator,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _TextFieldDialog(
        title: title,
        label: label,
        initial: initial,
        fieldKey: fieldKey,
        saveKey: saveKey,
        validator: (value) {
          if (required && value.isEmpty) return 'Enter a name.';
          return validator?.call(value);
        },
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  // Artwork ---------------------------------------------------------------

  Widget _artworkTab(BuildContext context) {
    final edition = controller.selectedEdition;
    final canSearch =
        !_isSearchingCoverArt &&
        widget.metadataProvider != null &&
        widget.coverArtCandidateDiscoveryService != null &&
        widget.coverArtAlbumEditionImportService != null &&
        controller.album != null &&
        edition != null;
    // Without editions the cover is the album's own.
    final hasOwnCover =
        edition == null || (edition.artworkPath ?? '').trim().isNotEmpty;

    return ListView(
      key: const ValueKey<String>('release-studio-artwork'),
      padding: _tabPadding(context),
      children: [
        if (controller.editions.length > 1) ...[
          const _SectionNote(
            'Each edition keeps its own cover. Choose the edition to change.',
          ),
          const SizedBox(height: 8),
          _EditionSelector(controller: controller),
          const SizedBox(height: 16),
        ],
        _CoverPreview(controller: controller),
        const SizedBox(height: 16),
        _StudioCard(
          children: [
            _ActionRow(
              tileKey: const ValueKey<String>('album-studio-change-artwork'),
              icon: Icons.add_photo_alternate_outlined,
              title: 'Replace cover',
              subtitle: 'Choose an image, then crop and position it.',
              onTap: widget.onChangeArtwork,
            ),
            if (widget.onRepositionArtwork != null)
              _ActionRow(
                tileKey: const ValueKey<String>(
                  'album-studio-reposition-artwork',
                ),
                icon: Icons.crop_rounded,
                title: 'Crop, zoom or reposition',
                subtitle: 'Reset to the full original image from here too.',
                onTap: hasOwnCover ? widget.onRepositionArtwork : null,
              ),
            _ActionRow(
              tileKey: const ValueKey<String>('album-studio-search-cover-art'),
              icon: Icons.image_search_rounded,
              title: 'Find on Cover Art Archive',
              subtitle: 'Covers published for this release online.',
              onTap: canSearch ? _searchCoverArt : null,
            ),
            _ActionRow(
              tileKey: const ValueKey<String>('album-studio-clear-artwork'),
              icon: Icons.hide_image_outlined,
              title: 'Remove cover',
              subtitle: 'Only for this edition.',
              onTap: hasOwnCover ? widget.onClearArtwork : null,
            ),
          ],
        ),
      ],
    );
  }

  // Editions --------------------------------------------------------------

  Widget _editionsTab(BuildContext context) {
    final management = widget.editionManagement;

    return ListView(
      key: const ValueKey<String>('release-studio-editions'),
      padding: _tabPadding(context),
      children: [
        if (controller.editions.length > 1) ...[
          _EditionSelector(controller: controller),
          const SizedBox(height: 16),
        ],
        if (management == null)
          const _SectionNote('Editions cannot be changed here.')
        else
          AlbumStudioEditionsSection(
            controller: controller,
            service: management,
            dismissals: widget.editionFollowUpDismissals,
            library: widget.library,
            userId: widget.userId,
            view: AlbumStudioEditionsView.editions,
          ),
      ],
    );
  }

  // Tracklist -------------------------------------------------------------

  Widget _tracklistTab(BuildContext context) {
    final edition = controller.selectedEdition;
    final tracks = controller.tracks;
    final gutter = SonusTheme.of(context).metrics.pageGutter;
    final management = widget.editionManagement;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.editions.length > 1) ...[
            _EditionSelector(controller: controller),
            const SizedBox(height: 14),
          ],
          if (management != null && edition != null) ...[
            AlbumStudioEditionsSection(
              controller: controller,
              service: management,
              dismissals: widget.editionFollowUpDismissals,
              library: widget.library,
              userId: widget.userId,
              view: AlbumStudioEditionsView.tracklist,
            ),
            const SizedBox(height: 14),
          ],
          if (edition != null)
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
      ),
    );

    if (edition == null) {
      return ListView(
        key: const ValueKey<String>('album-studio-scroll'),
        padding: EdgeInsets.only(bottom: _bottomPadding),
        children: [
          header,
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('No album edition is available to edit.'),
            ),
          ),
        ],
      );
    }

    return _StudioTrackList(
      controller: controller,
      tracks: tracks,
      header: header,
      bottomPadding: _bottomPadding,
      autoRenumber: _autoRenumber,
      isBusy: _isSavingOrder,
      userId: widget.userId,
      bonusSongIds: _bonusSongIds(),
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
    );
  }

  /// The primary edition's songs, read once per primary edition, so a
  /// non-primary edition's bonus tracks can be told apart.
  Set<String>? _primarySongIds;
  String? _primarySongsEditionId;

  /// Songs of the selected edition that the primary edition does not
  /// list: its bonus tracks. None on the primary edition itself.
  Set<String> _bonusSongIds() {
    final selected = controller.selectedEdition;
    final primary = controller.editions.where((e) => e.isPrimary).firstOrNull;
    if (selected == null || primary == null || selected.isPrimary) {
      return const {};
    }
    if (_primarySongsEditionId != primary.editionId) {
      _primarySongsEditionId = primary.editionId;
      _primarySongIds = null;
      unawaited(_loadPrimarySongs(primary.editionId));
    }
    final primarySongs = _primarySongIds;
    if (primarySongs == null) return const {};
    return {
      for (final track in controller.tracks)
        if (!primarySongs.contains(track.songId)) track.songId,
    };
  }

  Future<void> _loadPrimarySongs(String editionId) async {
    final Object? library = widget.library;
    if (library is! AlbumEditionQueryRepository) return;
    try {
      final tracks = await library.getTracksByAlbumEditionId(editionId);
      if (!mounted || _primarySongsEditionId != editionId) return;
      setState(() {
        _primarySongIds = {for (final track in tracks) track.songId};
      });
    } catch (_) {
      // Bonus labels are a convenience; the tracklist works without them.
    }
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

      setState(() => _detailsVersion++);

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
    this.bonusSongIds = const {},
  });

  final AlbumProfileController controller;
  final List<LibraryTrack> tracks;

  /// Songs this edition adds to the primary edition.
  final Set<String> bonusSongIds;
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
            isBonus: bonusSongIds.contains(track.songId),
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
    this.isBonus = false,
  });

  final LibraryTrack track;
  final int index;
  final bool multiDisc;
  final bool isBusy;

  /// Not on the primary edition: a bonus track of this edition.
  final bool isBonus;
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
      if (isBonus) 'Bonus track',
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

/// A bordered group of rows, in the studio's card style.
class _StudioCard extends StatelessWidget {
  const _StudioCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;

    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        side: BorderSide(color: colors.divider),
      ),
      child: Column(
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) Divider(height: 1, color: colors.divider),
            child,
          ],
        ],
      ),
    );
  }
}

/// One release field: its label, its value, and the one way to change it.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    super.key,
    required this.label,
    required this.value,
    required this.onEdit,
  });

  final String label;
  final String value;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);

    return ListTile(
      minTileHeight: 56,
      enabled: onEdit != null,
      onTap: onEdit,
      title: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: colors.textSecondary,
        ),
      ),
      subtitle: Text(
        value,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: onEdit == null
          ? null
          : Icon(Icons.edit_outlined, color: colors.textSecondary),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.tileKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final onTap = this.onTap;

    return ListTile(
      key: tileKey,
      minTileHeight: 56,
      enabled: onTap != null,
      leading: Icon(icon, color: colors.textSecondary),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap == null ? null : () => unawaited(onTap()),
    );
  }
}

class _SectionNote extends StatelessWidget {
  const _SectionNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: SonusTheme.of(context).colors.textSecondary,
      ),
    );
  }
}

/// The selected edition's cover, as large as the screen comfortably allows.
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});

  final AlbumProfileController controller;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final edition = controller.selectedEdition;
    final own = edition?.artworkPath?.trim();
    final hasOwn = own != null && own.isNotEmpty;
    final path = hasOwn ? own : controller.artworkPath;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth.clamp(120.0, 240.0);
        return Column(
          children: [
            SonusArtworkFrame(
              key: const ValueKey<String>('album-studio-artwork'),
              size: size,
              child: path == null
                  ? const _ArtworkFallback()
                  : Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      cacheWidth:
                          (size * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const _ArtworkFallback(),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              edition == null
                  ? 'Cover'
                  : hasOwn
                  ? 'Cover for ${_editionDisplayLabel(edition)}'
                  : path == null
                  ? '${_editionDisplayLabel(edition)} has no cover yet'
                  : '${_editionDisplayLabel(edition)} shows the main '
                        'edition\'s cover',
              key: const ValueKey<String>('release-studio-cover-caption'),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        );
      },
    );
  }
}

class _TextFieldDialog extends StatefulWidget {
  const _TextFieldDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.fieldKey,
    required this.saveKey,
    required this.validator,
  });

  final String title;
  final String label;
  final String initial;
  final String fieldKey;
  final String saveKey;
  final String? Function(String value) validator;

  @override
  State<_TextFieldDialog> createState() => _TextFieldDialogState();
}

class _TextFieldDialogState extends State<_TextFieldDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final value = _text.text.trim();
    final error = widget.validator(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: TextField(
          key: ValueKey<String>(widget.fieldKey),
          controller: _text,
          autofocus: true,
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: _error,
          ),
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: ValueKey<String>(widget.saveKey),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Picks the artist or project that owns the release.
class _OwnerDialog extends StatefulWidget {
  const _OwnerDialog({
    required this.artists,
    required this.currentArtistId,
    this.canCreate = false,
  });

  /// Returned when a new artist or project should own the release.
  static const String newOwner = ':new-owner';

  final List<LibraryArtist> artists;
  final String currentArtistId;
  final bool canCreate;

  @override
  State<_OwnerDialog> createState() => _OwnerDialogState();
}

class _OwnerDialogState extends State<_OwnerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final matches = [
      for (final artist in widget.artists)
        if (query.isEmpty || artist.name.toLowerCase().contains(query)) artist,
    ];

    return AlertDialog(
      key: const ValueKey<String>('release-studio-owner-dialog'),
      title: const Text('Artist or project'),
      content: SizedBox(
        width: 360,
        height: 360,
        child: Column(
          children: [
            Text(
              'The release moves to this artist\'s catalog. Songs, credits '
              'and streams stay as they are.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey<String>('release-studio-owner-search'),
              decoration: const InputDecoration(
                labelText: 'Search artists',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (widget.canCreate)
                    ListTile(
                      key: const ValueKey<String>('release-studio-owner-new'),
                      minTileHeight: 48,
                      leading: const Icon(Icons.add_rounded),
                      title: const Text('New artist or project…'),
                      subtitle: const Text(
                        'For example, a soundtrack that owns itself',
                      ),
                      onTap: () =>
                          Navigator.of(context).pop(_OwnerDialog.newOwner),
                    ),
                  for (final artist in matches)
                    ListTile(
                      key: ValueKey<String>(
                        'release-studio-owner-${artist.artistId}',
                      ),
                      minTileHeight: 48,
                      title: Text(artist.name),
                      selected: artist.artistId == widget.currentArtistId,
                      trailing: artist.artistId == widget.currentArtistId
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.of(context).pop(artist.artistId),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
