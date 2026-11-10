import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/sonus_text_scale.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../artwork/application/models/cover_art_archive_image.dart';
import '../../../artwork/application/services/cover_art_album_edition_import_service.dart';
import '../../../artwork/application/services/cover_art_candidate_discovery_service.dart';
import '../../application/models/external_metadata_candidate.dart';
import '../../application/models/external_metadata_search_query.dart';
import '../../application/models/library_album_edition.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/models/release_display_title.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/album_edition_management_service.dart';
import '../../application/services/album_edition_track_ordering_service.dart';
import '../../application/services/artist_creation_service.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/external_metadata_proposal_service.dart';
import '../../application/services/library_organization_service.dart';
import '../../application/services/metadata_provider.dart';
import '../../data/services/edition_follow_up_dismissals.dart';
import '../../domain/entities/album_edition.dart';
import '../../domain/entities/release_date.dart';
import '../../domain/services/album_edition_track_order.dart';
import '../controllers/album_profile_controller.dart';
import '../widgets/album_studio/album_studio_editions_section.dart';
import '../widgets/album_studio/album_studio_release_type.dart';
import '../widgets/album_studio/release_date_editor.dart';
import '../widgets/album_studio/release_studio_format.dart';
import '../widgets/album_studio/release_studio_leaked.dart';
import '../widgets/album_studio/release_studio_live.dart';
import '../widgets/cover_art_album_search_dialog.dart';
import '../widgets/cover_art_image_selection_dialog.dart';
import '../widgets/musicbrainz_search_dialog.dart';

/// Release Studio (SN-45, SN-50 A-Q6A/B): one screen to edit a release.
///
/// - **Shared details** (collapsible, at the top): artist or project, genre,
///   format, Live, Leaked, kind and a MusicBrainz lookup. They apply to
///   every edition, so no edition changes them.
/// - **Edition tabs** below, primary first and marked "Primary"; a release
///   with one edition shows its sections without tabs. Each edition has its
///   own name and release date, artwork, edition actions and tracklist, in
///   expandable sections.
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

/// The section that opens expanded: the shared details (with the edition's
/// name and date), or one of the selected edition's sections.
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

  late bool _sharedExpanded =
      widget.initialSection == ReleaseStudioSection.details;

  late final Set<ReleaseStudioSection> _expandedParts = {widget.initialSection};

  /// The heading of the section opened on arrival, scrolled to the top so
  /// that section gets the screen.
  final GlobalKey _initialPartKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    if (widget.initialSection != ReleaseStudioSection.details) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _initialPartKey.currentContext;
        if (mounted && target != null && target.mounted) {
          unawaited(Scrollable.ensureVisible(target));
        }
      });
    }
  }

  void _togglePart(ReleaseStudioSection part) {
    setState(() {
      if (!_expandedParts.remove(part)) {
        _expandedParts.add(part);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          key: const ValueKey<String>('release-studio-page'),
          appBar: AppBar(title: const Text('Edit Release')),
          body: _body(context),
        );
      },
    );
  }

  double get _bottomPadding => 32 + MediaQuery.paddingOf(context).bottom;

  /// One scroll view: the shared details, the edition tabs, the selected
  /// edition's sections, then its tracks when the tracklist is open.
  Widget _body(BuildContext context) {
    final gutter = SonusTheme.of(context).metrics.pageGutter;
    final edition = controller.selectedEdition;
    final tracksOpen = _expandedParts.contains(ReleaseStudioSection.tracklist);

    return CustomScrollView(
      key: const ValueKey<String>('release-studio-scroll'),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StudioSummary(controller: controller),
                if (_isSavingDetails) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(
                    key: ValueKey<String>('release-studio-saving'),
                  ),
                ],
                const SizedBox(height: 8),
                _SectionHeader(
                  key: const ValueKey<String>('release-studio-section-shared'),
                  title: 'Shared details',
                  subtitle: 'Used by every edition.',
                  icon: Icons.tune_rounded,
                  expanded: _sharedExpanded,
                  onToggle: () {
                    setState(() => _sharedExpanded = !_sharedExpanded);
                  },
                ),
                if (_sharedExpanded) _sharedDetails(context),
                if (controller.editions.length > 1) ...[
                  const SizedBox(height: 16),
                  _EditionTabs(controller: controller),
                ],
                _part(
                  ReleaseStudioSection.details,
                  name: 'name',
                  title: 'Name and release date',
                  icon: Icons.event_note_rounded,
                  content: _nameAndDate,
                ),
                _part(
                  ReleaseStudioSection.artwork,
                  name: 'artwork',
                  title: 'Artwork',
                  icon: Icons.image_outlined,
                  content: _artwork,
                ),
                _part(
                  ReleaseStudioSection.editions,
                  name: 'editions',
                  title: 'Edition',
                  icon: Icons.library_music_outlined,
                  content: _editions,
                ),
                // Last, so its tracks follow it in the scroll view.
                _part(
                  ReleaseStudioSection.tracklist,
                  name: 'tracklist',
                  title: 'Tracklist',
                  icon: Icons.queue_music_rounded,
                  content: _tracklistHeader,
                ),
              ],
            ),
          ),
        ),
        if (tracksOpen && edition != null)
          _StudioTrackList(
            controller: controller,
            tracks: controller.tracks,
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
          ),
        SliverPadding(padding: EdgeInsets.only(bottom: _bottomPadding)),
      ],
    );
  }

  /// One of the selected edition's expandable sections.
  Widget _part(
    ReleaseStudioSection part, {
    required String name,
    required String title,
    required IconData icon,
    required Widget Function(BuildContext context) content,
  }) {
    final expanded = _expandedParts.contains(part);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          key: ValueKey<String>('release-studio-section-$name'),
          anchorKey: part == widget.initialSection ? _initialPartKey : null,
          title: title,
          icon: icon,
          expanded: expanded,
          onToggle: () => _togglePart(part),
        ),
        if (expanded) Builder(builder: content),
      ],
    );
  }

  // Shared details ---------------------------------------------------------

  Widget _sharedDetails(BuildContext context) {
    final album = controller.album;
    final canEdit = controller.canEditAlbumProfile(widget.userId);
    final organization = widget.organization;
    final genres = _differingEditionGenres;

    return Padding(
      key: const ValueKey<String>('release-studio-details'),
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StudioCard(
            children: [
              _DetailRow(
                key: const ValueKey<String>('release-studio-owner'),
                label: 'Artist or project',
                value: album?.artistName ?? '',
                onEdit: canEdit && !_isSavingDetails && widget.library != null
                    ? _changeOwner
                    : null,
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
          if (genres.length > 1) ...[
            const SizedBox(height: 8),
            _GenreReviewNote(genres: genres),
          ],
          if (organization != null && album != null) ...[
            const SizedBox(height: 16),
            ReleaseStudioFormat(
              key: ValueKey<String>('release-studio-format-$_detailsVersion'),
              albumId: album.albumId,
              service: organization,
            ),
            const SizedBox(height: 16),
            ReleaseStudioLive(
              key: ValueKey<String>('release-studio-live-$_detailsVersion'),
              albumId: album.albumId,
              service: organization,
            ),
            const SizedBox(height: 16),
            ReleaseStudioLeaked(
              key: ValueKey<String>('release-studio-leaked-$_detailsVersion'),
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
            'A match can fill in the name, release date, format, kind and '
            'Live. Anything you set yourself is kept.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: SonusTheme.of(context).colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // Name and release date --------------------------------------------------

  Widget _nameAndDate(BuildContext context) {
    final canEdit = controller.canEditAlbumProfile(widget.userId);
    final edition = controller.selectedEdition;
    final perEdition = edition != null && controller.editions.length > 1;
    final releaseDate = _shownReleaseDate;
    final canEditDate = canEdit && !_isSavingDetails;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: _StudioCard(
        children: [
          // The selected edition's title is the one name to edit (SN-50
          // A-Q4); the stored base title is never changed here.
          _DetailRow(
            key: const ValueKey<String>('release-studio-name'),
            label: perEdition
                ? 'Name of ${_editionDisplayLabel(edition)}'
                : 'Name',
            value: _shownName ?? '',
            onEdit:
                canEdit &&
                    !_isSavingDetails &&
                    edition != null &&
                    widget.editionManagement != null
                ? _rename
                : null,
          ),
          _DetailRow(
            key: const ValueKey<String>('release-studio-date'),
            label: perEdition
                ? 'Release date of ${_editionDisplayLabel(edition)}'
                : 'Release date',
            value: releaseDate == null ? 'Not set' : releaseDate.label,
            onEdit: canEditDate ? _editReleaseDate : null,
            action: canEditDate
                ? IconButton(
                    key: const ValueKey<String>('release-studio-date-calendar'),
                    tooltip: 'Choose the release day on a calendar',
                    icon: const Icon(Icons.calendar_month_rounded),
                    onPressed: _pickReleaseDay,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  /// Saves one release-level field; the others keep their values.
  Future<void> _saveDetails({
    String? artistId,
    Object? releaseDate = _unchanged,
    Object? genre = _unchanged,
    required String message,
  }) async {
    final release = identical(releaseDate, _unchanged)
        ? controller.album?.releaseDateValue
        : releaseDate as ReleaseDate?;
    final album = controller.album;
    if (album == null) return;

    setState(() => _isSavingDetails = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final changed = await controller.updateProfile(
        userId: widget.userId,
        title: album.title,
        artistId: artistId ?? album.artistId,
        editionTitle: album.primaryEditionTitle ?? album.title,
        editionType: album.primaryEditionType ?? AlbumEditionType.standard,
        releaseDate: identical(releaseDate, _unchanged)
            ? album.releaseDate
            : release?.instant,
        releaseDatePrecision: identical(releaseDate, _unchanged)
            ? album.releaseDatePrecision
            : release?.precision,
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

  /// The selected edition's name as the release shows it.
  String? get _shownName {
    final album = controller.album;
    final edition = controller.selectedEdition;
    if (album == null) return null;
    if (edition == null) return album.displayTitle;
    return releaseDisplayTitle(
      baseTitle: album.displayTitle,
      editionTitle: edition.title,
    );
  }

  /// Genre is shared by the release (SN-50 A1); editions that still hold
  /// different genres are pointed out, never rewritten (A-Q17B).
  List<String> get _differingEditionGenres {
    final genres = <String, String>{};
    for (final edition in controller.editions) {
      final genre = edition.genre?.trim() ?? '';
      if (genre.isEmpty) continue;
      genres.putIfAbsent(genre.toLowerCase(), () => genre);
    }
    return genres.values.toList(growable: false);
  }

  Future<void> _rename() async {
    final edition = controller.selectedEdition;
    final management = widget.editionManagement;
    final current = _shownName;
    if (edition == null || management == null || current == null) return;

    final name = await _askForText(
      title: controller.editions.length > 1
          ? 'Rename ${_editionDisplayLabel(edition)}'
          : 'Rename release',
      label: 'Release name',
      initial: current,
      fieldKey: 'release-studio-name-field',
      saveKey: 'release-studio-save-name',
      required: true,
    );
    if (name == null || name.trim() == current.trim() || !mounted) return;

    setState(() => _isSavingDetails = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await management.updateEdition(
        editionId: edition.editionId,
        title: name,
        userId: widget.userId,
      );
      await controller.refresh();
      messenger.showSnackBar(const SnackBar(content: Text('Release renamed.')));
    } on AlbumEditionManagementException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(AlbumStudioEditionsSection.messageFor(error.refusal)),
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Release name could not be saved (${error.runtimeType})',
        name: 'sonus.library.release_studio',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('The name could not be saved.')),
      );
    } finally {
      if (mounted) setState(() => _isSavingDetails = false);
    }
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

  /// Whether the date row edits a non-primary edition's own date rather
  /// than going through the release's details.
  bool get _datesOtherEdition {
    final edition = controller.selectedEdition;
    return edition != null && !edition.isPrimary;
  }

  /// The date shown: the selected edition's own (SN-50 A-Q6C). A
  /// non-primary edition without one shows "Not set", never the primary's.
  ReleaseDate? get _shownReleaseDate => _datesOtherEdition
      ? controller.selectedEdition!.releaseDateValue
      : controller.album?.releaseDateValue;

  Future<void> _saveReleaseDate(ReleaseDate? date, String message) async {
    if (!_datesOtherEdition) {
      await _saveDetails(releaseDate: date, message: message);
      return;
    }

    setState(() => _isSavingDetails = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final saved = await controller.updateSelectedEditionReleaseDate(
        userId: widget.userId,
        releaseDate: date,
      );
      if (saved) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error, stackTrace) {
      developer.log(
        'Edition release date could not be saved (${error.runtimeType})',
        name: 'sonus.library.release_studio',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('The release date could not be saved.')),
      );
    } finally {
      if (mounted) setState(() => _isSavingDetails = false);
    }
  }

  Future<void> _editReleaseDate() async {
    if (controller.album == null) return;

    final edit = await showReleaseDateEditor(
      context,
      current: _shownReleaseDate,
    );
    switch (edit) {
      case null:
        return;
      case ReleaseDateCleared():
        await _saveReleaseDate(null, 'Release date cleared.');
      case ReleaseDateSet(:final date):
        await _saveReleaseDate(date, 'Release date saved: ${date.label}.');
    }
  }

  /// The calendar beside the release date: opens at the saved date.
  Future<void> _pickReleaseDay() async {
    final current = _shownReleaseDate;
    final now = DateTime.now();
    final last = DateTime(now.year + 5, 12, 31);
    var start = current == null
        ? now
        : DateTime(current.year, current.month ?? 1, current.day ?? 1);
    if (start.isAfter(last)) start = last;

    final picked = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime(1900),
      lastDate: last,
      initialDatePickerMode: current?.day == null
          ? DatePickerMode.year
          : DatePickerMode.day,
      helpText: 'Release day',
    );
    if (picked == null || !mounted) return;
    final date = ReleaseDate.of(picked.year, picked.month, picked.day)!;
    await _saveReleaseDate(date, 'Release date saved: ${date.label}.');
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
    if (artistId == null) return;
    if (artistId == album.artistId) {
      await _confirmOwner(album.artistName);
      return;
    }
    await _saveDetails(
      artistId: artistId,
      message: 'The release now belongs to its new artist.',
    );
  }

  /// Choosing the current owner again keeps it as the user's choice.
  Future<void> _confirmOwner(String owner) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (await controller.confirmOwner()) {
        messenger.showSnackBar(
          SnackBar(content: Text('$owner is kept as the owner.')),
        );
      }
    } catch (error, stackTrace) {
      developer.log(
        'Could not keep the release owner (${error.runtimeType})',
        name: 'sonus.library.release_studio',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('The owner could not be saved.')),
      );
    }
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

  // Artwork ---------------------------------------------------------------

  Widget _artwork(BuildContext context) {
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

    return Padding(
      key: const ValueKey<String>('release-studio-artwork'),
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                tileKey: const ValueKey<String>(
                  'album-studio-search-cover-art',
                ),
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
      ),
    );
  }

  // Edition actions --------------------------------------------------------

  Widget _editions(BuildContext context) {
    final management = widget.editionManagement;

    return Padding(
      key: const ValueKey<String>('release-studio-editions'),
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: management == null
          ? const _SectionNote('Editions cannot be changed here.')
          : AlbumStudioEditionsSection(
              controller: controller,
              service: management,
              dismissals: widget.editionFollowUpDismissals,
              library: widget.library,
              userId: widget.userId,
              view: AlbumStudioEditionsView.editions,
            ),
    );
  }

  // Tracklist -------------------------------------------------------------

  /// What sits above the tracks: the edition's songs and the order tools.
  Widget _tracklistHeader(BuildContext context) {
    final edition = controller.selectedEdition;
    final tracks = controller.tracks;
    final management = widget.editionManagement;

    if (edition == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No album edition is available to edit.')),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (management != null) ...[
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

    final edition = controller.selectedEdition;
    final AlbumEditionTrackPlacementResult? result;
    try {
      result = await controller.updateSelectedEditionTrackPlacement(
        userId: widget.userId,
        track: track,
        discNumber: draft.discNumber,
        trackNumber: draft.trackNumber,
      );
    } catch (error, stackTrace) {
      developer.log(
        'Track placement could not be saved (${error.runtimeType})',
        name: 'sonus.library.release_studio',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update track placement.')),
      );
      return;
    }

    if (!mounted || result == null) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Track placement updated.')));

    if (result.manualNumbersKept > 0 && edition != null) {
      await _offerManualRenumber(edition, result.manualNumbersKept);
    }
  }

  /// A disc move renumbers only inferred numbers; hand-set ones change
  /// only after the user agrees (SN-50 A-Q7A), as in Choose songs.
  Future<void> _offerManualRenumber(
    LibraryAlbumEdition edition,
    int count,
  ) async {
    final management = widget.editionManagement;
    if (management == null) return;

    final confirmed = await confirmManualRenumber(
      context,
      editionTitle: edition.title,
      count: count,
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await management.renumberEdition(
        editionId: edition.editionId,
        overwriteManual: true,
        userId: widget.userId,
      );
      await controller.refresh();
      messenger.showSnackBar(
        const SnackBar(content: Text('Tracks renumbered.')),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Edition renumbering failed (${error.runtimeType})',
        name: 'sonus.library.release_studio',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('The tracks could not be renumbered. Nothing changed.'),
        ),
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
            key: const ValueKey<String>('release-studio-summary-artwork'),
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
                  album?.displayTitle ?? 'Album',
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

/// A collapsible section's heading: one full-width button that says whether
/// the section is open, for touch, keyboard and screen readers alike.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    this.subtitle,
    this.anchorKey,
  });

  /// Lets the page scroll this heading into view.
  final GlobalKey? anchorKey;
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final subtitle = this.subtitle;

    return Padding(
      key: anchorKey,
      padding: const EdgeInsets.only(top: 8),
      child: MergeSemantics(
        child: Semantics(
          expanded: expanded,
          child: Material(
            color: colors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
              side: BorderSide(color: colors.divider),
            ),
            child: ListTile(
              minTileHeight: 56,
              leading: Icon(icon, color: colors.textSecondary),
              title: Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              subtitle: subtitle == null
                  ? null
                  : Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
              trailing: Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: colors.textSecondary,
              ),
              onTap: onToggle,
            ),
          ),
        ),
      ),
    );
  }
}

/// The release's editions as tabs, the primary first and marked "Primary"
/// (SN-50 A-Q6B). Choosing a tab shows that edition's sections below.
class _EditionTabs extends StatelessWidget {
  const _EditionTabs({required this.controller});

  final AlbumProfileController controller;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final editions = [
      ...controller.editions.where((edition) => edition.isPrimary),
      ...controller.editions.where((edition) => !edition.isPrimary),
    ];
    final selectedId = controller.selectedEdition?.editionId;
    final selected = editions.indexWhere((e) => e.editionId == selectedId);
    final height = MediaQuery.textScalerOf(context).scale(48);

    // Keyed by the editions and the selection, so a selection made
    // elsewhere (such as after a delete) always shows here.
    return DefaultTabController(
      key: ValueKey<String>(
        '${[for (final e in editions) e.editionId].join('|')}#$selected',
      ),
      length: editions.length,
      initialIndex: selected < 0 ? 0 : selected,
      child: TabBar(
        key: const ValueKey<String>('release-studio-edition-tabs'),
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: colors.textPrimary,
        unselectedLabelColor: colors.textSecondary,
        onTap: (index) {
          unawaited(controller.selectEdition(editions[index].editionId));
        },
        tabs: [
          for (final edition in editions)
            Tab(
              key: ValueKey<String>(
                'release-studio-edition-tab-${edition.editionId}',
              ),
              height: height,
              child: Semantics(
                label: edition.isPrimary
                    ? '${_editionDisplayLabel(edition)}, primary edition'
                    : _editionDisplayLabel(edition),
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_editionDisplayLabel(edition)),
                    if (edition.isPrimary) ...[
                      const SizedBox(width: 6),
                      DecoratedBox(
                        key: const ValueKey<String>(
                          'release-studio-edition-tab-primary',
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.divider),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'Primary',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
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

    if (tracks.isEmpty) {
      return const SliverToBoxAdapter(
        key: ValueKey<String>('album-studio-track-list'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No tracks in this edition.')),
        ),
      );
    }

    // A sliver of the page's own scroll view, so dragging a track near the
    // edge scrolls the whole page and nothing scrolls inside it.
    return SliverReorderableList(
      key: const ValueKey<String>('album-studio-track-list'),
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

  // Above sonusLargeTextScale the number column and placement button give
  // their width to the title; tapping the row still edits the placement.

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    const tabular = [FontFeature.tabularFigures()];
    final scaler = MediaQuery.textScalerOf(context);
    final largeText = scaler.scale(1) > sonusLargeTextScale;

    final placement = multiDisc
        ? 'Disc ${track.discNumber} • Track ${track.trackNumber}'
        : 'Track ${track.trackNumber}';
    final details = [
      // BUG-09: a member whose file is gone is listed, and says so.
      if (!track.hasAvailableFile) 'File unavailable',
      if (isBonus) 'Bonus track',
      _formatDuration(track.durationSeconds),
      if (track.releaseCreditLine.isNotEmpty) track.releaseCreditLine,
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
          track.displayTitle,
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
      title: Text(widget.track.displayTitle),
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
                decoration: const InputDecoration(
                  labelText: 'Disc number',
                  helperText:
                      'A song moved to another disc goes to the end of it.',
                  helperMaxLines: 3,
                ),
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

bool _usesMultipleDiscs(List<LibraryTrack> tracks) =>
    spansMultipleDiscs(tracks.map((track) => track.discNumber));

String _editionDisplayLabel(LibraryAlbumEdition edition) {
  final title = edition.title.trim();

  if (title.isNotEmpty) {
    return title;
  }

  return editionTypeLabel(edition.type);
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
    this.action,
  });

  final String label;
  final String value;
  final VoidCallback? onEdit;

  /// A second action beside the edit icon, such as a calendar.
  final Widget? action;

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
          : action == null
          ? Icon(Icons.edit_outlined, color: colors.textSecondary)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme.merge(
                  data: IconThemeData(color: colors.textSecondary),
                  child: action!,
                ),
                Icon(Icons.edit_outlined, color: colors.textSecondary),
              ],
            ),
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

/// Points out editions that hold different genres (SN-50 A-Q6F). Text and
/// an icon carry the message; nothing is blocked or rewritten.
class _GenreReviewNote extends StatelessWidget {
  const _GenreReviewNote({required this.genres});

  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return MergeSemantics(
      child: Row(
        key: const ValueKey<String>('release-studio-genre-review'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.rule_rounded,
            size: 20,
            color: colors.textSecondary,
            semanticLabel: 'Review',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Editions have different genres: ${genres.join(', ')}. '
              'Pick one to use for the release.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
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
                  : '${_editionDisplayLabel(edition)} has no cover yet. '
                        'Using the primary edition\'s cover.',
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
