import 'dart:ui' show ImageFilter;
import '../../../../core/design/context/sonus_context_theme.dart';
import '../../../../core/design/widgets/playback/sonus_playing_indicator.dart';
import '../../../player/presentation/models/now_playing_mark.dart';
import '../../../artwork/presentation/pages/artwork_crop_editor_page.dart';
import '../../../artwork/domain/entities/artwork_crop.dart';
import '../../../artwork/application/services/artwork_crop_service.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_artwork_palette.dart';
import '../../../../core/design/sonus_contrast.dart';
import '../../../../core/design/sonus_profile_colors.dart';
import '../../../../core/design/widgets/sonus_profile_surfaces.dart';
import '../../../../core/design/widgets/sonus_artwork_environment.dart';
import '../../../../core/design/widgets/sonus_frosted_glass.dart';
import '../../../../core/design/widgets/sonus_secondary_text_scope.dart';
import '../../../../core/design/widgets/sonus_profile_atmosphere_builder.dart';
import '../../../../core/design/sonus_atmosphere_colors.dart';
import '../../../../core/design/sonus_profile_effects.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/sonus_text_scale.dart';
import '../../../../core/design/sonus_tokens.dart';
import '../../../../core/design/widgets/sonus_artwork_frame.dart';
import '../../../../core/design/widgets/sonus_segmented_selector.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../domain/repositories/song_artist_credit_repository.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../artwork/application/services/cover_art_candidate_discovery_service.dart';
import '../../../artwork/application/services/cover_art_album_edition_import_service.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_album_edition.dart';
import '../../application/models/library_track.dart';
import '../../application/models/release_display_title.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/album_profile_editing_service.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/external_metadata_proposal_service.dart';
import '../../application/services/metadata_provider.dart';
import '../../application/services/album_edition_track_ordering_service.dart';
import '../../application/services/song_block_service.dart';
import '../../application/services/album_edition_management_service.dart';
import '../../application/services/artist_creation_service.dart';
import '../../application/services/library_organization_service.dart';
import '../../domain/services/album_edition_track_order.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import '../controllers/album_profile_controller.dart';
import '../controllers/track_selection_controller.dart';
import '../models/song_credit_summary.dart';
import '../models/track_profile_edit_draft.dart';
import '../widgets/track_selection_bar.dart';
import '../widgets/track_studio_launcher.dart';
import 'artist_profile_page.dart';
import 'release_studio_page.dart';
import 'track_studio_page.dart';
import '../../../song_stats/presentation/song_stats_navigation.dart';

class AlbumProfilePage extends StatefulWidget {
  const AlbumProfilePage({
    super.key,
    required this.albumId,
    this.initialAlbumTitle,
    this.initialEditionId,
    this.artworkPalette,
    this.changes,
  });

  final String albumId;
  final String? initialAlbumTitle;

  /// Opens on this edition when it belongs to the album, for example the
  /// edition a linked song is on.
  final String? initialEditionId;

  /// Where artwork colours come from; the app-wide cache by default.
  final SonusArtworkPalette? artworkPalette;

  /// Reloads after library edits, imports and recorded listening; the
  /// shared signal if null.
  final LibraryChangeSignal? changes;

  @override
  State<AlbumProfilePage> createState() => _AlbumProfilePageState();
}

class _AlbumProfilePageState extends State<AlbumProfilePage> {
  LibraryChangeRefresher? _refresher;
  AlbumProfileController? _controller;
  LibraryQueryRepository? _repository;
  final TrackSelectionController _selection = TrackSelectionController();

  /// Whether this release is a soundtrack or cast recording, so rows with
  /// many performers show a compact credit summary (UI redesign C2).
  bool _compactCredits = false;
  int _releaseKindRequest = 0;

  /// Whether the collapsing artwork has gone under the toolbar, so the
  /// toolbar names the release instead (UI redesign P2).
  final ValueNotifier<bool> _titleShown = ValueNotifier<bool>(false);

  /// How far the toolbar has filled in: 0 over the hero, 1 once the hero
  /// has scrolled away (phones).
  final ValueNotifier<double> _barProgress = ValueNotifier<double>(0);

  /// The artwork the page's atmosphere comes from. Updated as soon as the
  /// controller changes (it notifies without rebuilding this State), so
  /// [SonusProfileAtmosphereBuilder] requests its colours at once.
  final ValueNotifier<String?> _atmosphereArtwork = ValueNotifier<String?>(
    null,
  );

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    _atmosphereArtwork.value = _presentationArtworkPath(controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final repository = context.watch<LibraryQueryRepository?>();

    if (repository == null || identical(repository, _repository)) {
      return;
    }

    _controller?.removeListener(_onControllerChanged);
    _refresher?.dispose();
    _controller?.dispose();

    _repository = repository;
    _controller = AlbumProfileController(
      repository: repository,
      albumId: widget.albumId,
      initialEditionId: widget.initialEditionId,
      playbackCoordinator: context.read<PlaybackCoordinator?>(),
      albumProfileEditingService: context.read<AlbumProfileEditingService?>(),
      albumEditionTrackOrderingService: context
          .read<AlbumEditionTrackOrderingService?>(),
      songArtistCreditRepository: context.read<SongArtistCreditRepository?>(),
      trackProfileEditingService: context.read<TrackProfileEditingService?>(),
      songBlockService: context.read<SongBlockService?>(),
      artworkAssignmentService: context.read<ArtworkAssignmentService?>(),
      artworkFilePicker: context.read<ArtworkFilePicker?>(),
      artworkCropService: context.read<ArtworkCropService?>(),
    );

    // The artwork can change without this State rebuilding: when the album
    // loads or another edition is selected.
    _controller!.addListener(_onControllerChanged);
    final controller = _controller!;
    _refresher = LibraryChangeRefresher(
      signal: widget.changes ?? LibraryChangeSignal.shared,
      kinds: LibraryChangeKind.values.toSet(),
      onChange: () {
        unawaited(controller.refresh());
        unawaited(_loadReleaseKind());
      },
    );
    unawaited(controller.load());
    unawaited(_loadReleaseKind());
  }

  /// Reads the release's stated kind. Read only; a failure, or no
  /// organization service, leaves the full credit lines.
  Future<void> _loadReleaseKind() async {
    final service = context.read<LibraryOrganizationService?>();
    final request = ++_releaseKindRequest;
    if (service == null) return;

    var compact = false;
    try {
      final classifications = await service.organization.getClassifications();
      for (final classification in classifications) {
        if (classification.albumId == widget.albumId) {
          compact = compactCreditReleaseKinds.contains(classification.kind);
          break;
        }
      }
    } catch (error, stackTrace) {
      developer.log(
        'Release kind could not be read (${error.runtimeType})',
        name: 'sonus.library.album_profile',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (!mounted || request != _releaseKindRequest) return;
    if (compact != _compactCredits) {
      setState(() => _compactCredits = compact);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final accountController = context.watch<AccountController?>();
    final userId = accountController?.user?.id;
    // UI redesign P2: the artwork's own colours carry the page.
    return SonusProfileAtmosphereBuilder.listenable(
      artworkPath: _atmosphereArtwork,
      palette: widget.artworkPalette,
      // Theme architecture: the page's menus, dialogs, sheets, buttons and
      // rows take the artwork's colours, not the theme's blue and charcoal.
      builder: (context, resolved) {
        // Profile Lab: lighter secondary text over the lit page.
        final profile = resolved.forEnvironment(
          effects: SonusTheme.of(context).decoration.allowGradients,
        );
        return SonusContextTheme(
          colors: SonusContextColors.profile(
            profile,
            theme: SonusTheme.of(context).colors,
          ),
          child: Builder(
            builder: (context) => SonusSecondaryTextScope(
              secondary: profile.textSecondary,
              child: Builder(
                builder: (context) =>
                    _buildPage(context, controller, userId, profile),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPage(
    BuildContext context,
    AlbumProfileController? controller,
    String? userId,
    SonusProfileColors profile,
  ) {
    final atmosphere = profile.atmosphere;
    return Scaffold(
      key: const ValueKey<String>('album-profile-page'),
      backgroundColor: atmosphere.background,
      // V2: the selected edition's colour and light behind the whole page,
      // still while the content scrolls over it.
      body: SonusProfileBackdrop(
        profile: profile,
        baseKey: const ValueKey<String>('album-profile-background'),
        // Profile Lab: the selected edition's cover itself behind the page,
        // blurred and tone-mapped (also for neutral covers).
        environment: ValueListenableBuilder<String?>(
          valueListenable: _atmosphereArtwork,
          builder: (context, path, _) => SonusArtworkEnvironment(
            artworkPath: path,
            light: profile.light,
            deep: profile.backgroundDeep,
            // High contrast keeps a restrained backdrop behind its solid
            // panels; Low effects and Decoration Off draw none.
            enabled:
                sonusProfileBackdropMode(SonusTheme.of(context).decoration) !=
                SonusProfileBackdropMode.none,
            restrained:
                sonusProfileBackdropMode(SonusTheme.of(context).decoration) ==
                SonusProfileBackdropMode.restrained,
          ),
        ),
        child: controller == null
            ? CustomScrollView(
                slivers: [
                  _appBar(context, null, userId, atmosphere),
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('Loading album...')),
                  ),
                ],
              )
            : AnimatedBuilder(
                animation: Listenable.merge([controller, _selection]),
                builder: (context, _) =>
                    _content(context, controller, userId, profile),
              ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    AlbumProfileController controller,
    String? userId,
    SonusProfileColors profile,
  ) {
    final atmosphere = profile.atmosphere;
    Widget message(Widget child) => CustomScrollView(
      slivers: [
        _appBar(context, controller, userId, atmosphere),
        SliverFillRemaining(hasScrollBody: false, child: child),
      ],
    );

    if (controller.isLoading && controller.album == null) {
      return message(const Center(child: CircularProgressIndicator()));
    }
    if (controller.hasError && controller.album == null) {
      return message(_AlbumProfileLoadError(onRetry: controller.load));
    }
    if (controller.isNotFound) {
      return message(const _AlbumNotFound());
    }
    final album = controller.album;
    if (album == null) return message(const SizedBox.shrink());

    // The page's own size, not the screen's: the same in split screen.
    return LayoutBuilder(
      builder: (context, constraints) =>
          _loaded(context, controller, userId, profile, album, constraints),
    );
  }

  Widget _loaded(
    BuildContext context,
    AlbumProfileController controller,
    String? userId,
    SonusProfileColors profile,
    LibraryAlbum album,
    BoxConstraints constraints,
  ) {
    final atmosphere = profile.atmosphere;
    final tokens = SonusTheme.of(context);
    final gutter = tokens.metrics.pageGutter;
    final wide = constraints.maxWidth >= _AlbumHero.wideLayoutWidth;
    final artworkPath = _presentationArtworkPath(controller);
    // On phones the full cover leads the hero, and the whole hero scrolls
    // away naturally (no shrinking cover pinned under the toolbar); wide
    // screens keep it beside the details.
    final heroArt = wide
        ? null
        : _AlbumHero.phoneArtSize(
            context,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
          );

    return TrackSelectionScope(
      controller: _selection,
      visibleTracks: controller.tracks
          .where(_hasAvailableMedia)
          .toList(growable: false),
      child: RefreshIndicator(
        onRefresh: controller.refresh,
        // Below the collapsed toolbar, not under the status bar.
        edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 &&
                notification.metrics.axis == Axis.vertical) {
              final pixels = notification.metrics.pixels;
              _titleShown.value = wide || pixels > (heroArt ?? 0) * 0.75 + 12;
              _barProgress.value = heroArt == null
                  ? 1
                  : ((pixels - heroArt * 0.55) / (heroArt * 0.3)).clamp(
                      0.0,
                      1.0,
                    );
            }
            return false;
          },
          child: CustomScrollView(
            key: const PageStorageKey<String>('album-profile-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _appBar(
                context,
                controller,
                userId,
                atmosphere,
                scrollAway: !wide,
                alwaysShowTitle: wide,
              ),
              SliverToBoxAdapter(
                child: _AlbumHero(
                  album: album,
                  controller: controller,
                  artworkPath: artworkPath,
                  atmosphere: atmosphere,
                  profile: profile,
                  artSize: heroArt,
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (controller.editions.length > 1) ...[
                        _EditionSelector(
                          controller: controller,
                          atmosphere: atmosphere,
                        ),
                        const SizedBox(height: 18),
                      ],
                      _PlaybackControls(
                        controller: controller,
                        atmosphere: atmosphere,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                // The bottom inset keeps the last track clear of anything
                // anchored at the bottom of the app, such as a persistent
                // mini-player that reserves its space.
                // Close to the edges, so titles keep their width on small
                // screens and with large text.
                padding: EdgeInsets.fromLTRB(
                  8,
                  0,
                  8,
                  32 + MediaQuery.paddingOf(context).bottom,
                ),
                sliver: SliverToBoxAdapter(
                  child: _TracksSection(
                    profile: profile,
                    count: controller.tracks.where(_hasAvailableMedia).length,
                    child: _TracksList(
                      controller: controller,
                      selection: _selection,
                      profile: profile,
                      compactCredits: _compactCredits,
                      onGoToArtist: _openArtist,
                      canEditTrack: controller.canEditTrack(userId),
                      canSetBlocked: controller.canSetTrackBlocked(userId),
                      onEditTrack: (track) =>
                          _editTrack(controller, track, userId),
                      onChangeArtwork: (track) =>
                          _changeTrackArtwork(controller, track),
                      onClearArtwork: (track) =>
                          _clearTrackArtwork(controller, track),
                      onSetBlocked: (track, isBlocked) => _setTrackBlocked(
                        controller,
                        track,
                        userId,
                        isBlocked,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The pinned, compact toolbar. With [scrollAway] (phones) it is clear
  /// over the hero and fills in once the hero has scrolled away: glass over
  /// a blur of the list with effects on, solid otherwise. The release's
  /// title then fades in (at once with reduced motion). The cover is never
  /// pinned or shrunk under it.
  Widget _appBar(
    BuildContext context,
    AlbumProfileController? controller,
    String? userId,
    SonusAtmosphereColors atmosphere, {
    bool scrollAway = false,
    bool alwaysShowTitle = true,
  }) {
    final reduced = SonusTheme.of(context).motion.reduced;
    final title = controller == null
        ? Text(widget.initialAlbumTitle ?? 'Album')
        : Text(
            controller.album == null
                ? widget.initialAlbumTitle ?? 'Album'
                : _presentationAlbumTitle(
                    controller.album!,
                    controller.selectedEdition,
                  ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );

    return SliverAppBar(
      key: const ValueKey<String>('album-profile-app-bar'),
      pinned: true,
      backgroundColor: scrollAway ? Colors.transparent : atmosphere.background,
      scrolledUnderElevation: 0,
      title: !scrollAway || alwaysShowTitle
          ? title
          : ValueListenableBuilder<bool>(
              valueListenable: _titleShown,
              builder: (context, shown, _) => ExcludeSemantics(
                excluding: !shown,
                child: AnimatedOpacity(
                  key: const ValueKey<String>('album-profile-toolbar-title'),
                  opacity: shown ? 1 : 0,
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  child: title,
                ),
              ),
            ),
      flexibleSpace: !scrollAway
          ? null
          : ValueListenableBuilder<double>(
              valueListenable: _barProgress,
              builder: (context, t, _) {
                final effects = SonusTheme.of(
                  context,
                ).decoration.allowGradients;
                final fill = ColoredBox(
                  key: const ValueKey<String>('album-profile-toolbar-fill'),
                  color: atmosphere.background.withValues(
                    alpha: (effects ? 0.72 : 1.0) * Curves.easeIn.transform(t),
                  ),
                  child: const SizedBox.expand(),
                );
                if (!effects || t == 0) return fill;
                return ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
                    child: fill,
                  ),
                );
              },
            ),
      actions: [
        if (controller != null)
          PopupMenuButton<_AlbumMenuAction>(
            key: const ValueKey<String>('album-profile-artwork-menu'),
            enabled:
                controller.canEditArtwork ||
                controller.canEditAlbumProfile(userId) ||
                controller.canEditAlbumStudio(userId),
            tooltip: 'Release actions',
            onSelected: (action) {
              unawaited(_handleAlbumAction(controller, action, userId));
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _AlbumMenuAction.studio,
                enabled:
                    controller.canEditAlbumStudio(userId) ||
                    controller.canEditAlbumProfile(userId) ||
                    controller.canEditArtwork,
                child: const ListTile(
                  leading: Icon(Icons.tune_rounded),
                  title: Text('Edit Release'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
      ],
    );
  }

  void _openArtist(LibraryTrack track) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistProfilePage(
          artistId: track.artistId,
          initialArtistName: track.artistName,
        ),
      ),
    );
  }

  Future<void> _handleAlbumAction(
    AlbumProfileController controller,
    _AlbumMenuAction action,
    String? userId,
  ) async {
    if (action == _AlbumMenuAction.studio) {
      await _openAlbumStudio(controller, userId);
      return;
    }

    await _handleArtworkAction(controller, action);
  }

  Future<void> _openAlbumStudio(
    AlbumProfileController controller,
    String? userId,
  ) async {
    if (!controller.canEditAlbumStudio(userId) &&
        !controller.canEditAlbumProfile(userId) &&
        !controller.canEditArtwork) {
      return;
    }

    final coverArtCandidateDiscoveryService = context
        .read<CoverArtCandidateDiscoveryService?>();
    final coverArtAlbumEditionImportService = context
        .read<CoverArtAlbumEditionImportService?>();
    final metadataProvider = context.read<MetadataProvider?>();
    final externalMetadataApplicationService = context
        .read<ExternalMetadataApplicationService?>();
    final externalMetadataProposalService = context
        .read<ExternalMetadataProposalService?>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) {
          return ReleaseStudioPage(
            controller: controller,
            userId: userId,
            metadataProvider: metadataProvider,
            coverArtAlbumEditionImportService:
                coverArtAlbumEditionImportService,
            coverArtCandidateDiscoveryService:
                coverArtCandidateDiscoveryService,
            externalMetadataApplicationService:
                externalMetadataApplicationService,
            externalMetadataProposalService: externalMetadataProposalService,
            editionManagement: context.read<AlbumEditionManagementService?>(),
            organization: context.read<LibraryOrganizationService?>(),
            library: context.read<LibraryQueryRepository?>(),
            artistCreation: context.read<ArtistCreationService?>(),
            onChangeArtwork: controller.canEditArtwork
                ? () => _handleArtworkAction(
                    controller,
                    _AlbumMenuAction.changeArtwork,
                  )
                : null,
            onClearArtwork: controller.canEditArtwork
                ? () => _handleArtworkAction(
                    controller,
                    _AlbumMenuAction.clearArtwork,
                  )
                : null,
            onRepositionArtwork: controller.canCropArtwork
                ? () => _repositionArtwork(controller)
                : null,
          );
        },
      ),
    );
  }

  Future<void> _handleArtworkAction(
    AlbumProfileController controller,
    _AlbumMenuAction action,
  ) async {
    try {
      final changed = switch (action) {
        _AlbumMenuAction.studio => false,
        _AlbumMenuAction.changeArtwork =>
          controller.canCropArtwork
              ? await _pickAndCropArtwork(controller)
              : await controller.changeArtwork(),
        _AlbumMenuAction.clearArtwork => await controller.clearArtwork(),
      };

      if (!mounted || !changed) {
        return;
      }

      // Each edition has its own cover, so name it when there are several.
      final edition = controller.editions.length > 1
          ? controller.selectedEdition?.title
          : null;
      final message = switch (action) {
        _AlbumMenuAction.studio => '',
        _AlbumMenuAction.changeArtwork =>
          edition == null
              ? 'Album artwork updated.'
              : 'Cover updated for $edition.',
        _AlbumMenuAction.clearArtwork =>
          edition == null
              ? 'Album artwork cleared.'
              : 'Cover cleared for $edition.',
      };

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update album artwork.')),
      );
    }
  }

  /// Change artwork (SN-45): choose an image, then crop it to the cover.
  Future<bool> _pickAndCropArtwork(AlbumProfileController controller) async {
    final path = await controller.pickArtworkFile();

    if (path == null || !mounted) {
      return false;
    }

    final decision = await showArtworkCropEditor(
      context,
      imagePath: path,
      target: ArtworkCropTarget.albumEdition,
    );

    if (decision is! ArtworkCropSave) {
      return false;
    }

    return controller.applyArtworkCrop(sourcePath: path, rect: decision.rect);
  }

  /// Reposition cover: reopens the original at its saved crop.
  Future<void> _repositionArtwork(AlbumProfileController controller) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final source = await controller.artworkRepositionSource();

      if (!mounted) {
        return;
      }

      if (source == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('This edition has no cover of its own to move.'),
          ),
        );
        return;
      }

      final decision = await showArtworkCropEditor(
        context,
        imagePath: source.filePath,
        target: ArtworkCropTarget.albumEdition,
        initialRect: source.rect,
        canReset: source.isRecropping,
      );

      final String? message = switch (decision) {
        ArtworkCropSave(:final rect) =>
          await controller.applyArtworkCrop(
                sourcePath: source.filePath,
                rect: rect,
              )
              ? 'Cover repositioned.'
              : null,
        ArtworkCropReset() =>
          await controller.resetArtworkCrop()
              ? 'The full original cover is back.'
              : null,
        null => null,
      };

      if (message != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not reposition the cover.')),
        );
      }
    }
  }

  Future<void> _editTrack(
    AlbumProfileController controller,
    LibraryTrack track,
    String? userId,
  ) async {
    try {
      final repository = _repository;

      if (repository == null) {
        return;
      }

      final artists = await trackStudioArtists(context, repository);
      final albums = await repository.getAlbums();
      final structuredCredits = await controller.getTrackAdditionalCredits(
        track.songId,
      );

      if (!mounted) {
        return;
      }

      final initialAdditionalCredits = trackStudioInitialCredits(
        credits: structuredCredits,
        legacyFeaturedArtists: track.featuredArtists,
        primaryArtistId: track.artistId,
        primaryArtistName: track.artistName,
      );
      final metadataProvider = context.read<MetadataProvider?>();
      final externalMetadataApplicationService = context
          .read<ExternalMetadataApplicationService?>();
      final externalMetadataProposalService = context
          .read<ExternalMetadataProposalService?>();

      final draft = await Navigator.of(context).push<TrackProfileEditDraft>(
        MaterialPageRoute<TrackProfileEditDraft>(
          builder: (routeContext) {
            return TrackStudioPage(
              track: track,
              userId: userId,
              metadataProvider: metadataProvider,
              externalMetadataApplicationService:
                  externalMetadataApplicationService,
              externalMetadataProposalService: externalMetadataProposalService,
              onMetadataApplied: controller.refresh,
              artists: artists,
              albums: albums,
              initialAdditionalCredits: initialAdditionalCredits,
              canEditDetails: controller.canEditTrack(userId),
              onSaveCredits: controller.canEditTrack(userId)
                  ? trackStudioCreditSaver(
                      track: track,
                      save: (credits) => controller.saveTrackCredits(
                        userId: userId,
                        track: track,
                        additionalCredits: credits,
                      ),
                    )
                  : null,
              onChangeArtwork: controller.canEditTrackArtwork
                  ? () => _changeTrackArtwork(controller, track)
                  : null,
              onClearArtwork: controller.canEditTrackArtwork
                  ? () => _clearTrackArtwork(controller, track)
                  : null,
            );
          },
        ),
      );

      if (!mounted || draft == null) {
        return;
      }

      final changed = await controller.updateTrackWithCredits(
        userId: userId,
        track: track,
        title: draft.title,
        trackNumber: draft.trackNumber,
        discNumber: draft.discNumber,
        additionalCredits: draft.additionalCredits.map(
          (credit) => credit.toInput(),
        ),
        isSingle: draft.isSingle,
        versionLabel: draft.versionLabel,
        versionCharacteristics: draft.versionCharacteristics,
        releaseStatus: draft.releaseStatus,
        isLeak: draft.isLeak,
        artistId: draft.artistId,
        albumId: draft.albumId,
        albumEditionId: draft.moveToEditionId,
        placementEditionId: draft.placementEditionId,
      );

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Song details updated.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update song details.')),
      );
    }
  }

  Future<void> _setTrackBlocked(
    AlbumProfileController controller,
    LibraryTrack track,
    String? userId,
    bool isBlocked,
  ) async {
    if (!controller.canSetTrackBlocked(userId)) {
      return;
    }

    try {
      final changed = await controller.setTrackBlocked(
        userId: userId,
        track: track,
        isBlocked: isBlocked,
      );

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBlocked ? 'Song blacklisted.' : 'Removed from blacklist.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update blacklist.')),
      );
    }
  }

  Future<void> _changeTrackArtwork(
    AlbumProfileController controller,
    LibraryTrack track,
  ) async {
    try {
      final changed = await controller.changeTrackArtwork(track);

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Song artwork updated.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update song artwork.')),
      );
    }
  }

  Future<void> _clearTrackArtwork(
    AlbumProfileController controller,
    LibraryTrack track,
  ) async {
    try {
      final changed = await controller.clearTrackArtwork(track);

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Song artwork cleared.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update song artwork.')),
      );
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _selection.dispose();
    _refresher?.dispose();
    _controller?.dispose();
    _atmosphereArtwork.dispose();
    _titleShown.dispose();
    _barProgress.dispose();
    super.dispose();
  }
}

bool _hasAvailableMedia(LibraryTrack track) {
  return track.isAvailable &&
      track.filePath != null &&
      track.filePath!.trim().isNotEmpty;
}

/// Artwork, title, artist, edition and release details, on a background
/// that flows from the artwork's tint into the page.
class _AlbumHero extends StatelessWidget {
  const _AlbumHero({
    required this.album,
    required this.controller,
    required this.artworkPath,
    required this.atmosphere,
    this.profile,
    this.artSize,
  });

  final LibraryAlbum album;
  final AlbumProfileController controller;
  final String? artworkPath;
  final SonusAtmosphereColors atmosphere;

  /// The page's colours, for the cover's rim, glow and depth.
  final SonusProfileColors? profile;

  /// The phone cover's size ([phoneArtSize]); null on wide screens.
  final double? artSize;

  /// Page width from which the artwork sits beside the details
  /// (landscape and tablets), keeping the track list in view.
  static const double wideLayoutWidth = 560;

  /// The phone hero's cover: large, about four fifths of the width, but
  /// never more than about 40% of the screen's height, so the title and
  /// controls still start on the first screen.
  static double phoneArtSize(
    BuildContext context, {
    required double width,
    required double height,
  }) {
    final byHeight = !height.isFinite || height <= 0 ? 320.0 : height * 0.40;
    final available = width - 2 * SonusTheme.of(context).metrics.pageGutter;
    final byWidth = available * 0.82;
    return [
      byWidth,
      byHeight,
      320.0,
    ].reduce((a, b) => a < b ? a : b).clamp(140.0, 320.0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    // The page behind it carries the artwork's colours (P2).
    return Padding(
      key: const ValueKey<String>('album-profile-hero'),
      padding: EdgeInsets.fromLTRB(
        tokens.metrics.pageGutter,
        12,
        tokens.metrics.pageGutter,
        20,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Profile Lab: a luminous rim and glow in the page's light and a
          // soft depth, wherever glow is allowed (also neutral covers).
          final profile = this.profile;
          final glow = !tokens.decoration.allowGlow
              ? null
              : profile == null
              ? (atmosphere.isTinted ? atmosphere.accent : null)
              : (profile.isTinted ? profile.light : profile.accent);
          final depth = tokens.decoration.allowGlow
              ? profile?.backgroundDeep
              : null;

          if (constraints.maxWidth >= wideLayoutWidth) {
            final size = (constraints.maxWidth * 0.3).clamp(140.0, 220.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _AlbumArtwork(
                  album: album,
                  artworkPath: artworkPath,
                  size: size,
                  glow: glow,
                ),
                const SizedBox(width: 24),
                Expanded(child: _details(context, centered: false)),
              ],
            );
          }

          final size =
              artSize ?? (constraints.maxWidth * 0.66).clamp(140.0, 264.0);
          return Column(
            children: [
              _AlbumArtwork(
                album: album,
                artworkPath: artworkPath,
                size: size,
                glow: glow,
                depth: depth,
              ),
              const SizedBox(height: 20),
              _details(context, centered: true),
            ],
          );
        },
      ),
    );
  }

  Widget _details(BuildContext context, {required bool centered}) {
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    final metadata = _metadata(album);
    final edition = controller.selectedEdition;
    const tabular = [FontFeature.tabularFigures()];
    final align = centered ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          _presentationAlbumTitle(album, edition),
          key: ValueKey<String>('album-profile-title-${album.albumId}'),
          textAlign: align,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: -0.6,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          album.artistName,
          key: ValueKey<String>('album-profile-artist-${album.artistId}'),
          textAlign: align,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        if (edition != null) ...[
          const SizedBox(height: 8),
          _EditionBadge(
            label: _editionDisplayLabel(edition, album.title),
            atmosphere: atmosphere,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          _summary(),
          key: const ValueKey<String>('album-profile-summary'),
          textAlign: align,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textPrimary,
            fontFeatures: tabular,
          ),
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            metadata,
            key: const ValueKey<String>('album-profile-metadata'),
            textAlign: align,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontFeatures: tabular,
            ),
          ),
        ],
      ],
    );
  }

  String _summary() {
    final visibleTracks = controller.tracks
        .where(_hasAvailableMedia)
        .toList(growable: false);

    final trackCount = visibleTracks.length;
    final trackLabel = trackCount == 1 ? 'track' : 'tracks';

    final totalDuration = Duration(
      seconds: visibleTracks.fold<int>(
        0,
        (total, track) => total + track.durationSeconds,
      ),
    );

    final runtime = _formatRuntime(totalDuration);

    if (runtime.isEmpty) {
      return '$trackCount $trackLabel';
    }

    return '$trackCount $trackLabel • $runtime';
  }

  String _metadata(LibraryAlbum album) {
    final parts = <String>[];
    final selectedEdition = controller.selectedEdition;

    final releaseDate =
        selectedEdition?.releaseDateValue ?? album.releaseDateValue;

    if (releaseDate != null) {
      parts.add(releaseDate.label);
    }

    // Genre is shared by the release: the primary edition's (SN-50 A1).
    final genre = album.genre?.trim();

    if (genre != null && genre.isNotEmpty) {
      parts.add(genre);
    }

    if (selectedEdition == null) {
      if (controller.hasMultipleEditions) {
        parts.add('${controller.editionCount} editions');
      } else {
        final editionTitle = album.primaryEditionTitle?.trim();

        if (editionTitle != null &&
            editionTitle.isNotEmpty &&
            editionTitle.toLowerCase() != 'standard') {
          parts.add(editionTitle);
        }
      }
    }

    return parts.join(' • ');
  }

  String _formatRuntime(Duration duration) {
    final totalMinutes = duration.inMinutes;

    if (totalMinutes <= 0) {
      return '';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours == 0) {
      return '$minutes min';
    }

    if (minutes == 0) {
      return '$hours hr';
    }

    return '$hours hr $minutes min';
  }
}

/// The selected edition's name, outlined in the album's accent.
class _EditionBadge extends StatelessWidget {
  const _EditionBadge({required this.label, required this.atmosphere});

  final String label;
  final SonusAtmosphereColors atmosphere;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: atmosphere.accent),
        borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          label,
          key: const ValueKey<String>('album-profile-selected-edition-label'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: tokens.colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AlbumArtwork extends StatelessWidget {
  const _AlbumArtwork({
    required this.album,
    required this.artworkPath,
    required this.size,
    this.glow,
    this.depth,
  });

  final LibraryAlbum album;
  final String? artworkPath;
  final double size;

  /// A soft glow in the artwork's accent, only with decoration effects on.
  final Color? glow;

  /// A soft drop shadow under the cover (the page's deep tone), with glow.
  final Color? depth;

  @override
  Widget build(BuildContext context) {
    final path = artworkPath;
    final glow = this.glow;
    // Decoded at its display size, never at the cover's full resolution.
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          SonusTheme.of(context).metrics.artworkRadius,
        ),
        border: glow == null
            ? null
            : Border.all(color: glow.withValues(alpha: 0.55), width: 1.5),
        boxShadow: glow == null
            ? null
            : [
                BoxShadow(
                  color: glow.withValues(alpha: 0.36),
                  blurRadius: 34,
                  spreadRadius: 2,
                ),
                if (depth case final depth?)
                  BoxShadow(
                    color: depth.withValues(alpha: 0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
              ],
      ),
      child: SonusArtworkFrame(
        key: ValueKey<String>('album-profile-artwork-${album.albumId}'),
        size: size,
        child: path == null
            ? const _ArtworkFallback()
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: cacheSize,
                // Keeps the previous edition's cover until the next one is
                // ready, so switching editions never flashes empty.
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return const _ArtworkFallback();
                },
              ),
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
      key: const ValueKey<String>('album-profile-artwork-fallback'),
      color: colors.artworkPlaceholder,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.5,
          heightFactor: 0.5,
          child: FittedBox(
            child: Icon(
              Icons.album_rounded,
              color: colors.onArtworkPlaceholder,
            ),
          ),
        ),
      ),
    );
  }
}

/// Switches between the album's real editions. Only shown when two or more
/// exist; the options come from the album's data and nothing else.
///
/// A segmented control when every edition fits on one line, otherwise
/// wrapping choices, so long edition titles are never clipped or hidden off
/// screen.
class _EditionSelector extends StatelessWidget {
  const _EditionSelector({required this.controller, required this.atmosphere});

  final AlbumProfileController controller;
  final SonusAtmosphereColors atmosphere;

  @override
  Widget build(BuildContext context) {
    final selectedEdition = controller.selectedEdition;
    final editions = controller.editions;

    if (selectedEdition == null || editions.length < 2) {
      return const SizedBox.shrink();
    }
    final quiet = SonusTheme.of(context).decoration.allowGradients;

    final baseTitle = controller.album?.title ?? '';
    final labels = [
      for (final edition in editions) _editionDisplayLabel(edition, baseTitle),
    ];

    return Semantics(
      container: true,
      label: 'Album edition',
      child: LayoutBuilder(
        key: const ValueKey<String>('album-profile-edition-selector'),
        builder: (context, constraints) {
          if (_fitsOnOneLine(context, labels, constraints.maxWidth)) {
            return Center(
              // Its own scroll storage: without it, this horizontal
              // scroller shares the page list's slot and reopens at the
              // page's vertical offset.
              child: KeyedSubtree(
                key: const PageStorageKey<String>(
                  'album-profile-edition-selector-scroll',
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SonusSegmentedSelector<String>(
                    key: const ValueKey<String>(
                      'album-profile-edition-segmented-button',
                    ),
                    segments: [
                      for (final (index, edition) in editions.indexed)
                        SonusSegment<String>(
                          value: edition.editionId,
                          label: labels[index],
                        ),
                    ],
                    selected: selectedEdition.editionId,
                    // Profile Lab: with effects, a quiet selected segment
                    // (faint accent over the surface, primary text, check)
                    // so it stays subordinate to Play.
                    selectedBackgroundColor: quiet
                        ? Color.alphaBlend(
                            atmosphere.accent.withValues(alpha: 0.22),
                            atmosphere.surface,
                          )
                        : atmosphere.accent,
                    selectedForegroundColor: quiet
                        ? SonusTheme.of(context).colors.textPrimary
                        : atmosphere.onAccent,
                    onChanged: _select,
                  ),
                ),
              ),
            );
          }

          return _EditionChoices(
            editions: editions,
            labels: labels,
            selectedId: selectedEdition.editionId,
            maxWidth: constraints.maxWidth,
            atmosphere: atmosphere,
            onSelected: _select,
          );
        },
      ),
    );
  }

  void _select(String editionId) {
    if (editionId == controller.selectedEdition?.editionId) return;
    unawaited(controller.selectEdition(editionId));
  }

  /// Whether a segmented control holding [labels] fits in [maxWidth]. Its
  /// segments share the widest label's width, plus padding and the
  /// selected checkmark.
  static bool _fitsOnOneLine(
    BuildContext context,
    List<String> labels,
    double maxWidth,
  ) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textScaler: scaler,
        textDirection: Directionality.of(context),
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    const segmentChrome = 24 + 26 + 2; // padding, checkmark, border
    return (widest + segmentChrome) * labels.length <= maxWidth;
  }
}

class _EditionChoices extends StatelessWidget {
  const _EditionChoices({
    required this.editions,
    required this.labels,
    required this.selectedId,
    required this.maxWidth,
    required this.atmosphere,
    required this.onSelected,
  });

  final List<LibraryAlbumEdition> editions;
  final List<String> labels;
  final String selectedId;
  final double maxWidth;
  final SonusAtmosphereColors atmosphere;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    // Profile Lab: with effects, a quiet selected state (faint accent fill,
    // accent edge, check and weight) instead of a filled accent chip.
    final quiet = tokens.decoration.allowGradients;

    return Wrap(
      key: const ValueKey<String>('album-profile-edition-choices'),
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (index, edition) in editions.indexed)
          () {
            final selected = edition.editionId == selectedId;
            return ChoiceChip(
              key: ValueKey<String>(
                'album-profile-edition-choice-${edition.editionId}',
              ),
              label: ConstrainedBox(
                // Long titles wrap inside the chip instead of clipping.
                constraints: BoxConstraints(maxWidth: maxWidth - 64),
                // Chips force their label onto one line; a fresh text
                // style without a line limit lets long titles wrap fully.
                child: Builder(
                  builder: (context) => DefaultTextStyle(
                    style: DefaultTextStyle.of(context).style,
                    child: Text(labels[index]),
                  ),
                ),
              ),
              selected: selected,
              showCheckmark: true,
              checkmarkColor: selected && !quiet
                  ? atmosphere.onAccent
                  : colors.textPrimary,
              selectedColor: quiet
                  ? Color.alphaBlend(
                      atmosphere.accent.withValues(alpha: 0.18),
                      atmosphere.surface,
                    )
                  : atmosphere.accent,
              backgroundColor: Colors.transparent,
              labelStyle: TextStyle(
                color: selected && !quiet
                    ? atmosphere.onAccent
                    : selected
                    ? colors.textPrimary
                    : (quiet ? colors.textSecondary : colors.textPrimary),
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
              side: BorderSide(
                color: selected
                    ? (quiet
                          ? atmosphere.accent.withValues(alpha: 0.55)
                          : atmosphere.accent)
                    : colors.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  tokens.metrics.controlRadius,
                ),
              ),
              onSelected: (_) => onSelected(edition.editionId),
            );
          }(),
      ],
    );
  }
}

String? _presentationArtworkPath(AlbumProfileController controller) {
  final editionPath = controller.selectedEdition?.artworkPath?.trim();

  if (editionPath != null && editionPath.isNotEmpty) {
    return editionPath;
  }

  return controller.artworkPath;
}

String _presentationAlbumTitle(
  LibraryAlbum album,
  LibraryAlbumEdition? edition,
) {
  if (edition == null) {
    return album.displayTitle;
  }

  return releaseDisplayTitle(
    baseTitle: album.displayTitle,
    editionTitle: edition.title,
  );
}

String _editionDisplayLabel(LibraryAlbumEdition edition, String baseTitle) {
  return editionLabel(
    title: edition.title,
    type: edition.type,
    baseTitle: baseTitle,
  );
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.controller, required this.atmosphere});

  final AlbumProfileController controller;
  final SonusAtmosphereColors atmosphere;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.metrics.controlRadius),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.outlined(
          key: const ValueKey<String>('album-profile-shuffle-button'),
          tooltip: controller.isShuffleEnabled ? 'Shuffle on' : 'Shuffle off',
          isSelected: controller.isShuffleEnabled,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(48),
            foregroundColor: colors.textPrimary,
            // V2: artwork-tinted glass with an accent rim when tinted.
            backgroundColor:
                atmosphere.isTinted && tokens.decoration.allowGradients
                ? atmosphere.surface.withValues(alpha: 0.55)
                : null,
            side: BorderSide(
              color: controller.isShuffleEnabled
                  ? atmosphere.accent
                  : atmosphere.isTinted && tokens.decoration.allowGradients
                  ? atmosphere.accent.withValues(alpha: 0.45)
                  : colors.border,
            ),
            shape: shape,
          ),
          onPressed: controller.hasPlayableTracks
              ? () {
                  unawaited(controller.toggleShuffle());
                }
              : null,
          icon: Icon(
            controller.isShuffleEnabled
                ? Icons.shuffle_on_rounded
                : Icons.shuffle_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: FilledButton.icon(
            key: const ValueKey<String>('album-profile-play-all-button'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(132, 48),
              backgroundColor: atmosphere.accent,
              foregroundColor: atmosphere.onAccent,
              shape: shape,
            ),
            onPressed: controller.hasPlayableTracks
                ? () {
                    unawaited(controller.playAll());
                  }
                : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play'),
          ),
        ),
      ],
    );
  }
}

/// The track list on glass (P2): a translucent, artwork-tinted panel with
/// a rim, opaque where effects are off.
class _TracksSection extends StatelessWidget {
  const _TracksSection({
    required this.profile,
    required this.count,
    required this.child,
  });

  final SonusProfileColors profile;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);

    // Profile Lab: frosted glass over the artwork environment; solid where
    // effects are off.
    return SonusFrostedGlass(
      key: const ValueKey<String>('album-profile-tracks-section'),
      frosted: tokens.decoration.allowGradients,
      tint: profile.surface,
      light: profile.light,
      shadow: profile.backgroundDeep,
      solid: profile.surface,
      edge: profile.edge,
      borderRadius: tokens.metrics.cardRadius + 8,
      padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
      // A transparent Material, so row ripples show on the glass.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 4,
                      height: 22,
                      decoration: BoxDecoration(
                        color: profile.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Tracks',
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
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

class _TracksList extends StatelessWidget {
  const _TracksList({
    required this.controller,
    required this.selection,
    required this.profile,
    this.compactCredits = false,
    required this.onGoToArtist,
    required this.canEditTrack,
    required this.canSetBlocked,
    required this.onEditTrack,
    required this.onChangeArtwork,
    required this.onClearArtwork,
    required this.onSetBlocked,
  });

  final AlbumProfileController controller;
  final TrackSelectionController selection;
  final SonusProfileColors profile;

  /// See [_TrackTile.compactCredits].
  final bool compactCredits;
  final void Function(LibraryTrack track) onGoToArtist;
  final bool canEditTrack;
  final bool canSetBlocked;
  final Future<void> Function(LibraryTrack track) onEditTrack;
  final Future<void> Function(LibraryTrack track) onChangeArtwork;
  final Future<void> Function(LibraryTrack track) onClearArtwork;
  final Future<void> Function(LibraryTrack track, bool isBlocked) onSetBlocked;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.tracks
        .where(
          (track) =>
              track.isAvailable &&
              track.filePath != null &&
              track.filePath!.trim().isNotEmpty,
        )
        .toList(growable: false);

    if (tracks.isEmpty) {
      return const _EmptySection(message: 'No tracks yet');
    }

    // Disc headings only when the edition really spans several discs. They
    // follow the list's existing order; nothing is re-sorted here.
    final multiDisc = spansMultipleDiscs(
      tracks.map((track) => track.discNumber),
    );
    final coordinator = context.read<PlaybackCoordinator?>();

    return StreamBuilder<NowPlayingMark>(
      stream: coordinator == null ? null : NowPlayingMark.changes(coordinator),
      initialData: coordinator == null
          ? const NowPlayingMark()
          : NowPlayingMark.of(coordinator.currentState),
      builder: (context, snapshot) {
        final mark = snapshot.data ?? const NowPlayingMark();
        return _rows(context, tracks, multiDisc, mark);
      },
    );
  }

  Widget _rows(
    BuildContext context,
    List<LibraryTrack> tracks,
    bool multiDisc,
    NowPlayingMark mark,
  ) {
    return Column(
      key: const ValueKey<String>('album-profile-tracks-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, track) in tracks.indexed) ...[
          if (multiDisc &&
              (index == 0 || tracks[index - 1].discNumber != track.discNumber))
            _DiscHeading(disc: track.discNumber, index: index)
          else if (index > 0)
            // A hairline between rows, in the glass's rim colour.
            Divider(
              height: 1,
              thickness: 0.5,
              indent: 52,
              endIndent: 12,
              color: profile.edge.withValues(alpha: 0.28),
            ),
          _TrackTile(
            track: track,
            profile: profile,
            compactCredits: compactCredits,
            isCurrent: mark.marks(track.songId),
            isNowPlaying: mark.isPlaying,
            selectedEditionTitle: controller.selectedEdition?.title,
            isPlayable: controller.isTrackPlayable(track),
            canEditArtwork: controller.canEditTrackArtwork,
            canEditTrack: canEditTrack,
            canSetBlocked: canSetBlocked,
            selected: selection.isActive
                ? selection.isSelected(track.songId)
                : null,
            onSelect: () => selection.start(track.songId),
            onToggleSelected: () => selection.toggle(track.songId),
            onGoToArtist: () => onGoToArtist(track),
            onPlay: () => controller.playTrack(track),
            onPlayNext: () => controller.playNext(track),
            onAddToQueue: () => controller.addToQueue(track),
            onAddToPlaylist: () => showAddToPlaylistFlow(context, track),
            onEditTrack: () => onEditTrack(track),
            onChangeArtwork: () => onChangeArtwork(track),
            onClearArtwork: () => onClearArtwork(track),
            onSetBlocked: (isBlocked) => onSetBlocked(track, isBlocked),
          ),
        ],
      ],
    );
  }
}

class _DiscHeading extends StatelessWidget {
  const _DiscHeading({required this.disc, required this.index});

  final int disc;

  /// Position in the list, so a disc that appears twice keeps unique keys.
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = SonusTheme.of(context).colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      child: Semantics(
        header: true,
        child: Text(
          'Disc $disc',
          key: ValueKey<String>('album-profile-disc-heading-$index'),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.profile,
    this.compactCredits = false,
    this.isCurrent = false,
    this.isNowPlaying = false,
    this.selectedEditionTitle,
    required this.isPlayable,
    required this.canEditArtwork,
    required this.canEditTrack,
    required this.canSetBlocked,
    required this.selected,
    required this.onSelect,
    required this.onToggleSelected,
    required this.onGoToArtist,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onEditTrack,
    required this.onChangeArtwork,
    required this.onClearArtwork,
    required this.onSetBlocked,
  });

  final LibraryTrack track;
  final SonusProfileColors profile;

  /// On soundtracks and cast recordings, a credit line naming many
  /// performers collapses to a summary the listener can expand.
  final bool compactCredits;
  final bool isCurrent;
  final bool isNowPlaying;

  /// The edition on screen; a row names its edition only when it differs.
  final String? selectedEditionTitle;
  final bool isPlayable;
  final bool canEditArtwork;
  final bool canEditTrack;
  final bool canSetBlocked;

  /// Null outside selection mode.
  final bool? selected;
  final VoidCallback onSelect;
  final VoidCallback onToggleSelected;
  final VoidCallback onGoToArtist;

  final Future<void> Function() onPlay;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onAddToQueue;
  final Future<void> Function() onAddToPlaylist;
  final Future<void> Function() onEditTrack;
  final Future<void> Function() onChangeArtwork;
  final Future<void> Function() onClearArtwork;
  final Future<void> Function(bool isBlocked) onSetBlocked;

  @override
  Widget build(BuildContext context) {
    final selected = this.selected;

    if (selected == null) return _buildRow(context, null);

    return Semantics(
      checked: selected,
      selected: selected,
      child: _buildRow(context, selected),
    );
  }

  Widget _buildRow(BuildContext context, bool? selected) {
    final selecting = selected != null;
    final colors = SonusTheme.of(context).colors;
    final theme = Theme.of(context);
    const tabular = [FontFeature.tabularFigures()];
    // Above 1.3x text the duration moves onto the credit line, so the title
    // keeps enough width to wrap between words, not inside them.
    final largeText =
        MediaQuery.textScalerOf(context).scale(1) > sonusLargeTextScale;
    final duration = _formatDuration(track.durationSeconds);
    // The playing song in the artwork's accent, where it reads as text on
    // the glass; otherwise in the text colour, marked by its highlight.
    final currentColour =
        SonusContrast.ratio(profile.accent, profile.surface) >= 4.5
        ? profile.accent
        : colors.textPrimary;

    return ListTile(
      key: ValueKey<String>('album-track-${track.songId}'),
      contentPadding: const EdgeInsets.only(left: 8),
      minTileHeight: 56,
      // The playing row glows in the artwork's accent (P2, V2).
      tileColor: isCurrent ? profile.accent.withValues(alpha: 0.22) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isCurrent && profile.isTinted
            ? BorderSide(color: profile.accent.withValues(alpha: 0.35))
            : BorderSide.none,
      ),
      enabled: isPlayable || selecting,
      selected: selected ?? false,
      textColor: colors.textPrimary,
      iconColor: colors.textSecondary,
      // At least 28px, growing with the text, so "10" never wraps.
      leading: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.textScalerOf(context).scale(28),
        ),
        child: selecting
            ? ExcludeFocus(
                child: ExcludeSemantics(
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelected(),
                  ),
                ),
              )
            : isCurrent
            ? SizedBox(
                key: ValueKey<String>('album-track-playing-${track.songId}'),
                width: MediaQuery.textScalerOf(context).scale(28),
                child: Center(
                  child: SonusPlayingIndicator(
                    isPlaying: isNowPlaying,
                    color: profile.accent,
                  ),
                ),
              )
            : Text(
                '${track.trackNumber}',
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabular,
                ),
              ),
      ),
      title: Text(
        track.displayTitle,
        maxLines: largeText ? 3 : 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
          color: isCurrent ? currentColour : null,
        ),
      ),
      subtitle: _subtitle(track, colors, duration: largeText ? duration : null),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!largeText)
            Text(
              duration,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
                fontFeatures: tabular,
              ),
            ),
          if (!selecting)
            PopupMenuButton<_TrackMenuAction>(
              key: ValueKey<String>('album-track-menu-${track.songId}'),
              onSelected: (action) {
                switch (action) {
                  case _TrackMenuAction.playNext:
                    unawaited(onPlayNext());
                  case _TrackMenuAction.addToQueue:
                    unawaited(onAddToQueue());
                  case _TrackMenuAction.addToPlaylist:
                    unawaited(onAddToPlaylist());
                  case _TrackMenuAction.viewStats:
                    unawaited(
                      openSongStats(
                        context,
                        songId: track.songId,
                        initialTitle: track.displayTitle,
                      ),
                    );
                  case _TrackMenuAction.goToArtist:
                    onGoToArtist();
                  case _TrackMenuAction.select:
                    onSelect();
                  case _TrackMenuAction.trackStudio:
                    unawaited(onEditTrack());
                  case _TrackMenuAction.toggleBlocked:
                    unawaited(onSetBlocked(!track.isSongBlocked));
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _TrackMenuAction.playNext,
                  enabled: isPlayable,
                  child: const ListTile(
                    leading: Icon(Icons.skip_next_rounded),
                    title: Text('Play next'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _TrackMenuAction.addToQueue,
                  enabled: isPlayable,
                  child: const ListTile(
                    leading: Icon(Icons.queue_music_rounded),
                    title: Text('Add to queue'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _TrackMenuAction.addToPlaylist,
                  child: const ListTile(
                    leading: Icon(Icons.playlist_add_rounded),
                    title: Text('Add to playlist'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                songStatsMenuItem(
                  _TrackMenuAction.viewStats,
                  key: ValueKey<String>('album-track-stats-${track.songId}'),
                ),
                const PopupMenuItem(
                  value: _TrackMenuAction.goToArtist,
                  child: ListTile(
                    leading: Icon(Icons.person_outline_rounded),
                    title: Text('Go to artist'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _TrackMenuAction.select,
                  child: ListTile(
                    leading: Icon(Icons.check_box_outlined),
                    title: Text('Select'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _TrackMenuAction.trackStudio,
                  enabled: canEditTrack || canEditArtwork,
                  child: const ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Track Studio'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _TrackMenuAction.toggleBlocked,
                  enabled: canSetBlocked,
                  child: ListTile(
                    leading: Icon(
                      track.isSongBlocked
                          ? Icons.lock_open_rounded
                          : Icons.block_rounded,
                    ),
                    title: Text(
                      track.isSongBlocked
                          ? 'Remove from blacklist'
                          : 'Blacklist song',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      onLongPress: selecting ? onToggleSelected : onSelect,
      onTap: selecting
          ? onToggleSelected
          : isPlayable
          ? () {
              unawaited(onPlay());
            }
          : null,
    );
  }

  Widget? _subtitle(
    LibraryTrack track,
    SonusColors colors, {
    String? duration,
  }) {
    final parts = <String>[?duration];

    if (track.isBlocked) {
      parts.add('Blacklisted');
    } else if (!track.isAvailable ||
        track.filePath == null ||
        track.filePath!.trim().isEmpty) {
      parts.add('Unavailable');
    }

    final credit = songCreditSummary(
      primaryArtistName: track.artistName,
      coPrimaryArtists: track.coPrimaryArtists,
      featuredArtists: track.featuredArtists,
      guestArtists: track.guestArtists,
      omitPrimary: true,
    );
    final collapsible = compactCredits && credit.isCollapsible;
    final creditIndex = parts.length;

    if (credit.full.isNotEmpty) {
      parts.add(credit.full);
    }

    final editionTitle = track.albumEditionTitle.trim();
    final onScreen = selectedEditionTitle?.trim().toLowerCase();

    if (editionTitle.isNotEmpty &&
        editionTitle.toLowerCase() != 'standard' &&
        editionTitle.toLowerCase() != onScreen) {
      parts.add(editionTitle);
    }

    if (parts.isEmpty) {
      return null;
    }

    if (collapsible) {
      return _CollapsibleCredits(
        key: ValueKey<String>('album-track-credits-${track.songId}'),
        songId: track.songId,
        fullLine: parts.join(' \u2022 '),
        compactLine: [
          ...parts.take(creditIndex),
          credit.compact!,
          ...parts.skip(creditIndex + 1),
        ].join(' \u2022 '),
        color: colors.textSecondary,
      );
    }

    return Text(
      parts.join(' \u2022 '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.textSecondary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    final remainder = safeSeconds % 60;

    return '$minutes:'
        '${remainder.toString().padLeft(2, '0')}';
  }
}

/// A track row's credit line that starts as a summary ("Ft. Ada, Ben + 3
/// others") and expands to the full line (UI redesign C2). The whole line
/// is a 48dp-high control; screen readers always hear the full credits.
class _CollapsibleCredits extends StatefulWidget {
  const _CollapsibleCredits({
    super.key,
    required this.songId,
    required this.fullLine,
    required this.compactLine,
    required this.color,
  });

  final String songId;
  final String fullLine;
  final String compactLine;
  final Color color;

  @override
  State<_CollapsibleCredits> createState() => _CollapsibleCreditsState();
}

class _CollapsibleCreditsState extends State<_CollapsibleCredits> {
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    // Covers both the device setting and the in-app Reduce motion.
    final reduceMotion = SonusTheme.of(context).motion.reduced;
    final style = TextStyle(
      color: widget.color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final text = Text(
      _expanded ? widget.fullLine : widget.compactLine,
      key: ValueKey<String>(
        _expanded
            ? 'album-track-credits-full-${widget.songId}'
            : 'album-track-credits-summary-${widget.songId}',
      ),
      maxLines: _expanded ? null : 2,
      overflow: _expanded ? null : TextOverflow.ellipsis,
      style: style,
    );

    return Semantics(
      container: true,
      button: true,
      expanded: _expanded,
      label: 'Credits: ${widget.fullLine}',
      onTap: _toggle,
      onTapHint: _expanded ? 'Show fewer credits' : 'Show all credits',
      // The visible line may be the summary; the label is always whole.
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey<String>('album-track-credits-toggle-${widget.songId}'),
        borderRadius: BorderRadius.circular(8),
        onTap: _toggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                // With reduced motion the line changes at once.
                child: reduceMotion
                    ? text
                    : AnimatedSize(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topLeft,
                        child: text,
                      ),
              ),
              Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 20,
                color: widget.color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AlbumMenuAction { studio, changeArtwork, clearArtwork }

enum _TrackMenuAction {
  playNext,
  addToQueue,
  addToPlaylist,
  viewStats,
  goToArtist,
  select,
  trackStudio,
  toggleBlocked,
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: SonusTheme.of(context).colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _AlbumProfileLoadError extends StatelessWidget {
  const _AlbumProfileLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: SonusTheme.of(context).colors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load this album.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () {
                unawaited(onRetry());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumNotFound extends StatelessWidget {
  const _AlbumNotFound();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.album_outlined,
              size: 48,
              color: SonusTheme.of(context).colors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text('Album not found', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
