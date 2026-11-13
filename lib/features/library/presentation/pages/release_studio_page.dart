import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/sonus_text_scale.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
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
import '../../application/models/external_metadata_candidate.dart';
import '../../application/services/metadata_provider.dart';
import '../../data/services/edition_follow_up_dismissals.dart';
import '../../domain/deletion/permanent_deletion_impact.dart';
import '../../domain/entities/album_edition_disc_label.dart';
import '../../domain/entities/album_edition.dart';
import '../../domain/entities/release_date.dart';
import '../../domain/services/album_edition_track_order.dart';
import '../../domain/services/genre_catalog.dart';
import '../controllers/album_profile_controller.dart';
import '../widgets/album_studio/album_studio_editions_section.dart';
import '../widgets/album_studio/album_studio_release_type.dart';
import '../widgets/album_studio/release_date_editor.dart';
import '../widgets/album_studio/release_studio_format.dart';
import '../widgets/album_studio/release_studio_leaked.dart';
import '../widgets/album_studio/release_studio_live.dart';
import '../widgets/album_studio/studio_disc_actions.dart';
import '../controllers/track_selection_controller.dart';
import '../../application/services/edition_disc_layout.dart';
import '../widgets/musicbrainz_search_dialog.dart';
import '../widgets/permanent_deletion/permanent_deletion_sheet.dart';

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
  bool _isSavingOrder = false;

  /// Discs added with "Add disc" that have no songs yet, per edition
  /// (REF-13). A disc exists in the library once a song is moved onto it.
  final Map<String, Set<int>> _addedDiscs = {};
  bool _isApplyingMusicBrainz = false;
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

  /// Songs of the tracklist selected to move together (PATCH-03), and the
  /// edition they were selected on: choosing another edition ends it.
  final TrackSelectionController _selection = TrackSelectionController();
  String? _selectionEditionId;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, _selection]),
      builder: (context, _) {
        _endSelectionOnOtherEdition();
        final selecting = _selection.isActive;
        return PopScope(
          // Back ends selection first, as on other song lists.
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _selection.exit();
          },
          child: CallbackShortcuts(
            bindings: {
              if (selecting)
                const SingleActivator(LogicalKeyboardKey.escape):
                    _selection.exit,
            },
            child: Scaffold(
              key: const ValueKey<String>('release-studio-page'),
              appBar: AppBar(title: const Text('Edit Release')),
              body: _body(context),
              bottomNavigationBar: selecting
                  ? StudioSelectionBar(
                      count: _selection.selectedIn(controller.tracks).length,
                      allSelected: _selection.allSelectedIn(controller.tracks),
                      isBusy: _isSavingOrder,
                      onSelectAll: () => _selection.selectAll([
                        for (final track in controller.tracks) track.songId,
                      ]),
                      onMoveToDisc: () => unawaited(_moveSelected()),
                      onCancel: _selection.exit,
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }

  void _endSelectionOnOtherEdition() {
    if (!_selection.isActive) return;
    final edition = controller.selectedEdition?.editionId;
    if (edition == _selectionEditionId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          controller.selectedEdition?.editionId != _selectionEditionId) {
        _selection.exit();
      }
    });
  }

  void _startSelection([String? songId]) {
    _selectionEditionId = controller.selectedEdition?.editionId;
    _selection.start(songId);
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
            tracks: controller.tracks,
            extraDiscs: _addedDiscs[edition.editionId] ?? const {},
            discLabels: controller.discLabels,
            isBusy: _isSavingOrder,
            bonusSongIds: _bonusSongIds(),
            onArrange: _arrange,
            onRenameDisc: _renameDisc,
            onDeleteDisc: _deleteDisc,
            onEditPlacement: _editPlacement,
            onDeletePermanently: _deleteUnavailableSong,
            selection: _selection,
            onStartSelection: _startSelection,
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
                value: GenreCatalog.display(album?.genre) == null
                    ? 'Not set'
                    : GenreCatalog.display(album!.genre)!,
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
            // BUG-10: one editor for every precision; its own calendar
            // fills the year, month and day.
            onEdit: canEditDate ? _editReleaseDate : null,
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

    final genre = await showDialog<String>(
      context: context,
      builder: (_) => _GenreDialog(
        initial: album.genre ?? '',
        known: [?album.genre, ..._differingEditionGenres],
      ),
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
              // REF-18: Cover Art Archive search is no longer offered here.
              // Covers it supplied earlier stay, with their provenance.
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
            isSaving: _isSavingOrder || _isSorting,
            onSortByDiscAndTrack: tracks.length < 2
                ? null
                : _sortByDiscAndTrack,
            onAddDisc: tracks.isEmpty ? null : () => _addDisc(edition),
            onSelect: tracks.isEmpty || _selection.isActive
                ? null
                : _startSelection,
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

  /// The chosen album looked up by its identity, which also gives its
  /// genres (REF-17). If that fails, the search result is used and simply
  /// suggests no genre.
  Future<ExternalMetadataCandidate> _inFull(
    MetadataProvider provider,
    ExternalMetadataCandidate candidate,
  ) async {
    try {
      return await provider.lookup(
            entityKind: ExternalMetadataEntityKind.album,
            providerEntityId: candidate.providerEntityId,
          ) ??
          candidate;
    } catch (error, stackTrace) {
      developer.log(
        'MusicBrainz album lookup failed (${error.runtimeType}); '
        'previewing the search result',
        name: 'sonus.library.release_studio',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return candidate;
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
            previewer: (candidate) async {
              return proposalService.previewAlbum(
                albumId: album.albumId,
                candidate: await _inFull(provider, candidate),
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

  /// Deletes a song whose file is unavailable, through the same
  /// permanent-deletion sheet and service as everywhere else (preview,
  /// typed confirmation, ledger, sync and every safeguard). The file is
  /// never touched. Just before deleting, the song is checked again: one
  /// whose file came back, or that left this release, is not deleted.
  Future<void> _deleteUnavailableSong(LibraryTrack track) async {
    final messenger = ScaffoldMessenger.of(context);
    final deleted = await showPermanentDeletion(
      context,
      target: PermanentDeletionTarget.song(track.songId),
      name: track.displayTitle,
      artworkPath: track.artworkPath,
      beforeDelete: () => _stillUnavailable(track.songId),
    );
    if (!mounted) return;
    // The tracklist shows what is there now, deleted or not.
    await controller.refresh();
    if (!deleted || !mounted) return;
    messenger.showSnackBar(
      SnackBar(
        key: const ValueKey<String>('album-studio-delete-done'),
        content: Text('${track.displayTitle} was permanently deleted.'),
      ),
    );
  }

  /// Null while [songId] is still on this edition with its file
  /// unavailable; otherwise why it must not be deleted from here.
  Future<String?> _stillUnavailable(String songId) async {
    await controller.refresh();
    LibraryTrack? current;
    for (final track in controller.tracks) {
      if (track.songId == songId) current = track;
    }
    if (current == null) {
      return 'This song is no longer on this edition.';
    }
    if (current.hasAvailableFile) {
      return 'Its music file is available again, so it stays in your '
          'library.';
    }
    return null;
  }

  /// Adds the next disc as an empty section to move songs onto (REF-13).
  void _addDisc(LibraryAlbumEdition edition) {
    final added = _addedDiscs[edition.editionId] ?? const <int>{};
    final discs = {
      for (final track in controller.tracks) shownDisc(track.discNumber),
      ...added,
    };
    final next = (discs.isEmpty ? 1 : discs.reduce(max)) + 1;
    setState(() {
      _addedDiscs[edition.editionId] = {...added, next};
    });
  }

  /// The selected edition as shown: each song, in order, on its disc.
  List<EditionPlacement> _shownPlacements(String editionId) => _placementsOf(
    _studioEntries(
      controller.tracks,
      extraDiscs: _addedDiscs[editionId] ?? const {},
    ),
  );

  /// Every disc shown for [editionId], with or without songs.
  List<int> _shownDiscs(String editionId) => {
    for (final track in controller.tracks) shownDisc(track.discNumber),
    ...?_addedDiscs[editionId],
  }.toList()..sort();

  /// The tracklist [placements] describes, disc by disc, for a preview.
  List<DiscPreview> _preview(
    List<EditionPlacement> placements,
    Map<int, String> labels,
  ) {
    final titles = {
      for (final track in controller.tracks) track.songId: track.displayTitle,
    };
    final discs = discsOf(placements);
    return [
      for (final disc in discs)
        DiscPreview(
          title: discs.length > 1
              ? discTitle(disc, label: labels[disc])
              : 'Tracks',
          songs: [
            for (final p in placements)
              if (shownDisc(p.discNumber) == disc) titles[p.songId] ?? '',
          ],
        ),
    ];
  }

  /// "Move to Disc" for the selected songs (PATCH-03): they keep their
  /// order and go to the end of the disc chosen; both discs are numbered
  /// again. Selection ends once they have moved, and stays if not.
  Future<void> _moveSelected() async {
    final edition = controller.selectedEdition;
    if (edition == null || _isSavingOrder) return;
    final selected = _selection.selectedIn(controller.tracks);
    if (selected.isEmpty) return;

    final discs = _shownDiscs(edition.editionId);
    final target = await chooseDestinationDisc(
      context,
      count: selected.length,
      discs: discs,
      labels: controller.discLabels,
      newDisc: (discs.isEmpty ? 1 : discs.last) + 1,
    );
    if (target == null || !mounted) return;

    final placements = movedToDisc(_shownPlacements(edition.editionId), {
      for (final track in selected) track.songId,
    }, target);
    if (await _arrange(placements) && mounted) _selection.exit();
  }

  /// "Delete Disc" (PATCH-02). An empty disc goes after a confirmation. A
  /// disc with songs asks first whether they move to another disc or
  /// leave this edition, then shows the edition as it will be. Songs are
  /// never deleted, and their history and playlists stay.
  Future<void> _deleteDisc(int disc) async {
    final edition = controller.selectedEdition;
    if (edition == null || _isSavingOrder) return;
    final editionId = edition.editionId;
    final current = _shownPlacements(editionId);
    final songIds = songsOnDisc(current, disc);
    final discName = discTitle(disc, label: controller.discLabels[disc]);

    int? moveTo;
    var removing = <String>{};
    if (songIds.isNotEmpty) {
      final others = [
        for (final d in _shownDiscs(editionId))
          if (d != disc) d,
      ];
      final blocked = await _whyNotRemovable(editionId, songIds);
      if (!mounted) return;
      final choice = await chooseDiscDeletion(
        context,
        discName: discName,
        songCount: songIds.length,
        removeBlockedReason: blocked,
      );
      if (choice == null || !mounted) return;
      if (choice is MoveDiscSongs) {
        moveTo = others.length == 1
            ? others.single
            : await chooseDestinationDisc(
                context,
                count: songIds.length,
                discs: others,
                labels: controller.discLabels,
              );
        if (moveTo == null || !mounted) return;
      } else {
        removing = songIds.toSet();
      }
    }

    final placements = afterDeletingDisc(current, disc, moveTo: moveTo);
    final confirmed = await confirmDiscLayout(
      context,
      title: 'Delete $discName?',
      confirmLabel: 'Delete Disc $disc',
      discs: _preview(
        placements,
        labelsAfterDeletingDisc(controller.discLabels, disc),
      ),
      removed: [
        for (final track in controller.tracks)
          if (removing.contains(track.songId)) track.displayTitle,
      ],
    );
    if (!confirmed || !mounted) return;

    await _commitDiscDeletion(
      editionId: editionId,
      disc: disc,
      placements: placements,
      removing: removing,
      moveTo: moveTo,
    );
  }

  /// Why the songs of a disc cannot leave this edition, or null when they
  /// can: each must stay on another edition, and the edition keeps a song.
  Future<String?> _whyNotRemovable(
    String editionId,
    List<String> songIds,
  ) async {
    if (songIds.length == controller.tracks.length) {
      return 'An edition keeps at least one song, so these can only be '
          'moved.';
    }
    final Object? library = widget.library;
    if (library is! AlbumEditionQueryRepository) {
      return 'Sonus could not check the other editions, so these can only '
          'be moved.';
    }
    try {
      final elsewhere = <String>{};
      for (final other in controller.editions) {
        if (other.editionId == editionId) continue;
        for (final track in await library.getTracksByAlbumEditionId(
          other.editionId,
        )) {
          elsewhere.add(track.songId);
        }
      }
      final onlyHere = songIds.where((id) => !elsewhere.contains(id)).length;
      if (onlyHere == 0) return null;
      return onlyHere == 1
          ? '1 of these songs is on no other edition, and every song stays '
                'on at least one. Move the songs instead.'
          : '$onlyHere of these songs are on no other edition, and every '
                'song stays on at least one. Move the songs instead.';
    } catch (error, stackTrace) {
      developer.log(
        'Other editions could not be read (${error.runtimeType})',
        name: 'sonus.library.release_studio',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return 'Sonus could not check the other editions, so these can only '
          'be moved.';
    }
  }

  Future<void> _commitDiscDeletion({
    required String editionId,
    required int disc,
    required List<EditionPlacement> placements,
    required Set<String> removing,
    required int? moveTo,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final later = _shownDiscs(editionId).any((d) => d > disc);
    final named = controller.discLabels.containsKey(disc);
    setState(() => _isSavingOrder = true);
    try {
      // An empty, unnamed disc with no disc after it exists only on this
      // screen: there is nothing to save.
      if (removing.isNotEmpty || moveTo != null || later || named) {
        await controller.deleteSelectedEditionDisc(
          disc: disc,
          placements: placements,
          removeSongIds: removing,
          userId: widget.userId,
        );
      }
      if (!mounted) return;
      setState(() {
        final added = _addedDiscs[editionId];
        if (added != null) {
          _addedDiscs[editionId] = {
            for (final d in added)
              if (d != disc) discAfterDeleting(d, disc),
          };
        }
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            removing.isNotEmpty
                ? 'Disc $disc deleted. ${_songs(removing.length)} removed '
                      'from this edition; they stay in your library.'
                : moveTo != null
                ? 'Disc $disc deleted. Its songs moved to Disc '
                      '${discAfterDeleting(moveTo, disc)}.'
                : 'Disc $disc deleted.',
          ),
        ),
      );
    } on DiscDeletionException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (error.refusal) {
            DiscDeletionRefusal.songsOnlyOnThisEdition =>
              '${_songs(error.songCount)} on no other edition, so the disc '
                  'was not deleted. Move the songs instead.',
            DiscDeletionRefusal.editionWouldBeEmpty =>
              'An edition keeps at least one song. Nothing was changed.',
            DiscDeletionRefusal.notOnDisc =>
              'The tracklist changed meanwhile. Nothing was changed.',
          }),
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'A disc could not be deleted (${error.runtimeType})',
        name: 'sonus.library.release_studio',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not delete the disc. Nothing was changed.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingOrder = false);
    }
  }

  static String _songs(int count) => count == 1 ? '1 song' : '$count songs';

  /// Saves the edition laid out as [placements]: order, discs and
  /// automatic numbering of the discs it changes (REF-13), without asking.
  /// Whether it was saved.
  Future<bool> _arrange(List<EditionPlacement> placements) async {
    final edition = controller.selectedEdition;
    if (edition == null || _isSavingOrder) return false;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSavingOrder = true);
    try {
      await controller.arrangeSelectedEdition(
        userId: widget.userId,
        placements: placements,
      );
      if (!mounted) return true;
      // A disc that now has songs no longer needs to be remembered here.
      final used = {for (final p in placements) p.discNumber};
      final added = _addedDiscs[edition.editionId];
      if (added != null) {
        setState(() => added.removeWhere(used.contains));
      }
      return true;
    } catch (error, stackTrace) {
      developer.log(
        'Tracks could not be arranged (${error.runtimeType})',
        name: 'sonus.library.release_studio',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not reorder tracks. Nothing was changed.'),
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _isSavingOrder = false);
    }
  }

  /// Names a disc, or clears its name when left empty (REF-13c).
  Future<void> _renameDisc(int disc) async {
    final text = await _askForText(
      title: 'Name Disc $disc',
      label: 'Name (leave empty for none)',
      initial: controller.discLabels[disc] ?? '',
      fieldKey: 'album-studio-disc-name-field',
      saveKey: 'album-studio-disc-name-save',
    );
    if (text == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.setSelectedEditionDiscLabel(
        disc: disc,
        label: text,
        userId: widget.userId,
      );
    } catch (error, stackTrace) {
      developer.log(
        'A disc name could not be saved (${error.runtimeType})',
        name: 'sonus.library.release_studio',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save the disc name.')),
      );
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
    required this.isSaving,
    required this.onSortByDiscAndTrack,
    required this.onAddDisc,
    this.onSelect,
  });

  final int count;
  final bool isSaving;
  final Future<void> Function()? onSortByDiscAndTrack;
  final VoidCallback? onAddDisc;

  /// Starts selecting songs to move together (PATCH-03).
  final VoidCallback? onSelect;

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
        const SizedBox(height: 4),
        // REF-13: no Auto-renumber switch; every arrangement numbers each
        // disc 1, 2, 3 by itself.
        Text(
          'Drag songs, or use Move, to change their order or disc. Tracks '
          'are numbered automatically on each disc.',
          key: const ValueKey<String>('album-studio-order-help'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey<String>('album-studio-add-disc'),
              onPressed: isSaving ? null : onAddDisc,
              icon: const Icon(Icons.album_outlined),
              label: const Text('Add disc'),
            ),
            OutlinedButton.icon(
              key: const ValueKey<String>('album-studio-sort-disc-track'),
              onPressed: isSaving || onSortByDiscAndTrack == null
                  ? null
                  : () {
                      unawaited(onSortByDiscAndTrack!());
                    },
              icon: const Icon(Icons.sort_rounded),
              label: const Text('Sort by disc & track'),
            ),
            OutlinedButton.icon(
              key: const ValueKey<String>('album-studio-select'),
              onPressed: isSaving ? null : onSelect,
              icon: const Icon(Icons.checklist_rounded),
              label: const Text('Select'),
            ),
          ],
        ),
        if (isSaving)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              key: ValueKey<String>('album-studio-reorder-progress'),
            ),
          ),
      ],
    );
  }
}

/// One row of the Release Studio tracklist: a disc's heading, or a song.
sealed class _StudioEntry {
  const _StudioEntry();
}

class _DiscEntry extends _StudioEntry {
  const _DiscEntry(this.disc, {required this.isEmpty});

  final int disc;
  final bool isEmpty;
}

class _SongEntry extends _StudioEntry {
  const _SongEntry(this.track);

  final LibraryTrack track;
}

/// The edition's songs in its order, with a heading for each disc when it
/// has (or is given) more than one (REF-13). Dragging a song below another
/// disc's heading moves it to that disc; one disc stays implicit.
List<_StudioEntry> _studioEntries(
  List<LibraryTrack> tracks, {
  Set<int> extraDiscs = const {},
}) {
  final discs = {
    for (final track in tracks) shownDisc(track.discNumber),
    ...extraDiscs,
  }.toList()..sort();
  if (discs.length <= 1) {
    return [for (final track in tracks) _SongEntry(track)];
  }
  final grouped = groupedByDisc(tracks, (track) => track.discNumber);
  return [
    for (final disc in discs) ...[
      _DiscEntry(
        disc,
        isEmpty: !grouped.any((t) => shownDisc(t.discNumber) == disc),
      ),
      for (final track in grouped)
        if (shownDisc(track.discNumber) == disc) _SongEntry(track),
    ],
  ];
}

/// Every song of [entries], in order, on the disc of the heading above it
/// (the first disc when it is above every heading). Without headings each
/// song keeps its own disc.
List<EditionPlacement> _placementsOf(List<_StudioEntry> entries) {
  // Songs above every heading go on the first disc.
  int? disc = entries.whereType<_DiscEntry>().firstOrNull?.disc;
  final placements = <EditionPlacement>[];
  for (final entry in entries) {
    switch (entry) {
      case _DiscEntry():
        disc = entry.disc;
      case _SongEntry(:final track):
        placements.add(
          EditionPlacement(
            songId: track.songId,
            discNumber: disc ?? shownDisc(track.discNumber),
          ),
        );
    }
  }
  return placements;
}

class _StudioTrackList extends StatelessWidget {
  const _StudioTrackList({
    required this.tracks,
    required this.extraDiscs,
    required this.discLabels,
    required this.isBusy,
    required this.onArrange,
    required this.onRenameDisc,
    required this.onEditPlacement,
    this.onDeleteDisc,
    this.onDeletePermanently,
    this.selection,
    this.onStartSelection,
    this.bonusSongIds = const {},
  });

  /// "Delete Disc" on each disc heading (PATCH-02). Headings, and so this,
  /// appear only when the edition has more than one disc.
  final Future<void> Function(int disc)? onDeleteDisc;

  /// The songs selected to move together (PATCH-03). While selecting, a
  /// tap selects a song and songs are not dragged.
  final TrackSelectionController? selection;

  /// Starts selecting with a song: a long press on it.
  final void Function(String songId)? onStartSelection;

  final List<LibraryTrack> tracks;
  final Set<int> extraDiscs;
  final Map<int, String> discLabels;
  final Future<void> Function(LibraryTrack track)? onDeletePermanently;

  /// Songs this edition adds to the primary edition.
  final Set<String> bonusSongIds;
  final bool isBusy;
  final Future<void> Function(List<EditionPlacement> placements) onArrange;
  final Future<void> Function(int disc) onRenameDisc;
  final Future<void> Function(LibraryTrack track) onEditPlacement;

  @override
  Widget build(BuildContext context) {
    final entries = _studioEntries(tracks, extraDiscs: extraDiscs);
    final multiDisc = entries.any((e) => e is _DiscEntry);
    final selecting = selection?.isActive ?? false;
    final discs = [
      for (final e in entries)
        if (e is _DiscEntry) e.disc,
    ];
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
      itemCount: entries.length,
      onReorderItem: isBusy || selecting
          ? (_, _) {}
          : (oldIndex, newIndex) {
              if (oldIndex == newIndex || entries[oldIndex] is _DiscEntry) {
                return;
              }
              final moved = [...entries];
              moved.insert(newIndex, moved.removeAt(oldIndex));
              unawaited(onArrange(_placementsOf(moved)));
            },
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is _DiscEntry) {
          return Padding(
            key: ValueKey<String>('album-studio-disc-${entry.disc}'),
            padding: EdgeInsets.fromLTRB(
              gutter,
              index == 0 ? 4 : 14,
              gutter,
              2,
            ),
            child: _StudioDiscHeading(
              disc: entry.disc,
              label: discLabels[entry.disc],
              isEmpty: entry.isEmpty,
              onRename: isBusy || selecting
                  ? null
                  : () => onRenameDisc(entry.disc),
              onDelete: isBusy || selecting || onDeleteDisc == null
                  ? null
                  : () => onDeleteDisc!(entry.disc),
            ),
          );
        }
        final track = (entry as _SongEntry).track;

        return Padding(
          key: ValueKey<String>('album-studio-track-${track.songId}'),
          padding: EdgeInsets.fromLTRB(gutter, 3, gutter, 3),
          child: _StudioTrackRow(
            track: track,
            index: index,
            multiDisc: multiDisc,
            isBusy: isBusy,
            isBonus: bonusSongIds.contains(track.songId),
            moves: selecting ? const [] : _movesFor(entries, index, discs),
            selected: selecting ? selection!.isSelected(track.songId) : null,
            onToggleSelected: selecting
                ? () => selection!.toggle(track.songId)
                : null,
            onStartSelection: selecting || onStartSelection == null
                ? null
                : () => onStartSelection!(track.songId),
            onEditPlacement: onEditPlacement,
            onDeletePermanently: onDeletePermanently,
          ),
        );
      },
    );
  }

  /// The keyboard and screen-reader alternatives to dragging the song at
  /// [index] (REF-13): up, down, to another disc, or to a new disc.
  List<(String, VoidCallback)> _movesFor(
    List<_StudioEntry> entries,
    int index,
    List<int> discs,
  ) {
    void moveTo(int target) {
      final moved = [...entries];
      moved.insert(target, moved.removeAt(index));
      unawaited(onArrange(_placementsOf(moved)));
    }

    final track = (entries[index] as _SongEntry).track;
    final disc = shownDisc(track.discNumber);
    final above = index - 1;
    final below = index + 1;
    final canGoUp = above >= 0 && !(above == 0 && entries[0] is _DiscEntry);
    final canGoDown = below < entries.length;

    // After the disc's last song; on an empty disc, where it begins.
    void toDisc(int target) => unawaited(
      onArrange(movedToDisc(_placementsOf(entries), {track.songId}, target)),
    );

    final allDiscs = {...discs, disc}.toList()..sort();
    final newDisc = (allDiscs.isEmpty ? 1 : allDiscs.last) + 1;
    return [
      if (canGoUp) ('Move up', () => moveTo(above)),
      if (canGoDown) ('Move down', () => moveTo(below)),
      for (final other in allDiscs)
        if (other != disc) ('Move to Disc $other', () => toDisc(other)),
      ('Move to a new disc ($newDisc)', () => toDisc(newDisc)),
    ];
  }
}

/// A disc's heading in Release Studio: its number and name, and a button
/// to name it (REF-13c). Not draggable.
class _StudioDiscHeading extends StatelessWidget {
  const _StudioDiscHeading({
    required this.disc,
    required this.label,
    required this.isEmpty,
    required this.onRename,
    this.onDelete,
  });

  final int disc;
  final String? label;
  final bool isEmpty;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final named = label?.trim().isNotEmpty ?? false;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  discTitle(disc, label: label),
                  key: ValueKey<String>('album-studio-disc-title-$disc'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isEmpty)
                Text(
                  'No songs yet. Drag songs here, or use Move.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          key: ValueKey<String>('album-studio-disc-name-$disc'),
          tooltip: named ? 'Rename Disc $disc' : 'Name Disc $disc',
          onPressed: onRename,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          key: ValueKey<String>('album-studio-delete-disc-$disc'),
          tooltip: 'Delete Disc $disc',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

class _StudioTrackRow extends StatelessWidget {
  const _StudioTrackRow({
    required this.track,
    required this.index,
    required this.multiDisc,
    required this.isBusy,
    required this.onEditPlacement,
    this.onDeletePermanently,
    this.moves = const [],
    this.isBonus = false,
    this.selected,
    this.onToggleSelected,
    this.onStartSelection,
  });

  /// While songs are being selected (PATCH-03): whether this one is. Null
  /// otherwise. A tap then selects it, and it is not dragged.
  final bool? selected;
  final VoidCallback? onToggleSelected;

  /// A long press starts selecting with this song. Not at large text,
  /// where a long press drags the row.
  final VoidCallback? onStartSelection;

  /// Where the song can be moved without dragging (REF-13): each a label
  /// and its action. Shown as a Move menu and as screen-reader actions.
  final List<(String, VoidCallback)> moves;

  final LibraryTrack track;
  final int index;
  final bool multiDisc;
  final bool isBusy;

  /// Not on the primary edition: a bonus track of this edition.
  final bool isBonus;
  final Future<void> Function(LibraryTrack track) onEditPlacement;

  /// "Delete song permanently…", offered only while the song's file is
  /// unavailable: Release Studio is the one place such a song is listed
  /// (App Update 1.2, Purpose repair). Null: not offered.
  final Future<void> Function(LibraryTrack track)? onDeletePermanently;

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

    final row = Material(
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
        selected: selected ?? false,
        leading: selected != null
            ? Checkbox(
                key: ValueKey<String>('album-studio-select-${track.songId}'),
                value: selected,
                onChanged: (_) => onToggleSelected?.call(),
              )
            : largeText
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
        onTap: selected != null
            ? onToggleSelected
            : isBusy
            ? null
            : () => onEditPlacement(track),
        onLongPress: largeText || isBusy ? null : onStartSelection,
        trailing: selected != null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Kept at large text too: there is no other way to reach it.
                  if (!track.hasAvailableFile && onDeletePermanently != null)
                    IconButton(
                      key: ValueKey<String>(
                        'album-studio-delete-${track.songId}',
                      ),
                      tooltip: 'Delete song permanently…',
                      onPressed: isBusy
                          ? null
                          : () => onDeletePermanently!(track),
                      icon: const Icon(Icons.delete_forever_outlined),
                    ),
                  if (moves.isNotEmpty)
                    PopupMenuButton<int>(
                      key: ValueKey<String>(
                        'album-studio-move-${track.songId}',
                      ),
                      tooltip: 'Move',
                      enabled: !isBusy,
                      icon: const Icon(Icons.swap_vert_rounded),
                      onSelected: (choice) => moves[choice].$2(),
                      itemBuilder: (context) => [
                        for (final (index, (label, _)) in moves.indexed)
                          PopupMenuItem<int>(
                            key: ValueKey<String>(
                              'album-studio-move-${track.songId}-$index',
                            ),
                            value: index,
                            child: Text(label),
                          ),
                      ],
                    ),
                  if (!largeText)
                    IconButton(
                      key: ValueKey<String>(
                        'album-studio-edit-placement-${track.songId}',
                      ),
                      tooltip: 'Edit track placement',
                      onPressed: isBusy ? null : () => onEditPlacement(track),
                      icon: const Icon(Icons.numbers_rounded),
                    ),
                  // At large text the Move menu takes the handle's place and the
                  // whole row drags on a long press, so the title keeps its room.
                  if (!largeText)
                    ReorderableDragStartListener(
                      index: index,
                      enabled: !isBusy,
                      child: Tooltip(
                        message: 'Drag to reorder',
                        child: Padding(
                          key: ValueKey<String>(
                            'album-studio-drag-${track.songId}',
                          ),
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
    return largeText
        ? ReorderableDelayedDragStartListener(
            index: index,
            enabled: !isBusy && selected == null,
            child: row,
          )
        : row;
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

/// Choosing a genre (REF-14): type to search the canonical categories and
/// the release's own genres, tap one to choose it, or save what is typed
/// as a genre of its own. Saving it empty removes the genre.
class _GenreDialog extends StatefulWidget {
  const _GenreDialog({required this.initial, required this.known});

  final String initial;
  final List<String> known;

  @override
  State<_GenreDialog> createState() => _GenreDialogState();
}

class _GenreDialogState extends State<_GenreDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = GenreCatalog.suggestionsFor(
      _text.text,
      known: widget.known,
    );
    final typed = _text.text.trim();

    return AlertDialog(
      key: const ValueKey<String>('release-studio-genre-dialog'),
      title: const Text('Genre'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey<String>('release-studio-genre-field'),
              controller: _text,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Genre',
                hintText: 'Search or type a genre',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                key: const ValueKey<String>('release-studio-genre-options'),
                shrinkWrap: true,
                children: [
                  for (final (index, genre) in suggestions.indexed)
                    ListTile(
                      key: ValueKey<String>(
                        'release-studio-genre-option-$index',
                      ),
                      minTileHeight: 48,
                      title: Text(genre),
                      trailing: genre == typed
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.of(context).pop(genre),
                    ),
                  if (suggestions.isEmpty && typed.isNotEmpty)
                    ListTile(
                      key: const ValueKey<String>(
                        'release-studio-genre-custom',
                      ),
                      minTileHeight: 48,
                      leading: const Icon(Icons.add_rounded),
                      title: Text('Use "$typed"'),
                      onTap: () => Navigator.of(context).pop(typed),
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
        FilledButton(
          key: const ValueKey<String>('release-studio-save-genre'),
          // Read when pressed: what is in the field now.
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
