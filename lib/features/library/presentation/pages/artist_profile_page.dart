import '../../../artwork/presentation/pages/artwork_crop_editor_page.dart';
import '../../../artwork/domain/entities/artwork_crop.dart';
import '../../../artwork/application/services/artwork_crop_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_artwork_palette.dart';
import '../../../../core/design/sonus_atmosphere_colors.dart';
import '../../../../core/design/sonus_count_label.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../domain/repositories/song_artist_credit_repository.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/artist_profile_editing_service.dart';
import '../../application/services/artist_merge_service.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/external_metadata_proposal_service.dart';
import '../../application/services/metadata_provider.dart';
import '../../application/services/song_block_service.dart';
import '../../application/services/song_artist_credit_service.dart';
import '../../application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import '../controllers/artist_profile_controller.dart';
import '../models/artist_profile_sections.dart';
import '../models/track_profile_edit_draft.dart';
import '../widgets/artist_profile/artist_profile_albums_grid.dart';
import '../widgets/artist_profile/artist_profile_collaborators.dart';
import '../widgets/artist_profile/artist_profile_header.dart';
import '../widgets/artist_profile/artist_profile_tracks_list.dart';
import '../widgets/artist_profile/artist_profile_playback_controls.dart';
import '../widgets/artist_profile/artist_profile_section_heading.dart';
import '../widgets/artist_profile/artist_library_placement_sheet.dart';
import 'album_profile_page.dart';
import 'artist_studio_page.dart';
import 'track_studio_page.dart';

class ArtistProfilePage extends StatefulWidget {
  const ArtistProfilePage({
    super.key,
    required this.artistId,
    this.initialArtistName,
    this.artworkPalette,
    this.changes,
    this.projectArtistId,
  });

  final String artistId;
  final String? initialArtistName;

  /// The project (release owner) this page was opened from. A contributor's
  /// page then shows only its songs on that project.
  final String? projectArtistId;

  /// Where artwork colours come from; the app-wide cache by default.
  final SonusArtworkPalette? artworkPalette;

  /// Reloads after library edits, imports and recorded listening; the
  /// shared signal if null.
  final LibraryChangeSignal? changes;

  @override
  State<ArtistProfilePage> createState() => _ArtistProfilePageState();
}

class _ArtistProfilePageState extends State<ArtistProfilePage> {
  LibraryChangeRefresher? _refresher;
  ArtistProfileController? _controller;
  LibraryQueryRepository? _repository;

  // Artwork atmosphere, as on the Album Profile: theme colours show at
  // once; the artwork's colours arrive asynchronously and replace them.
  SonusArtworkPalette get _palette =>
      widget.artworkPalette ?? SonusArtworkPalette.shared;
  String? _atmospherePath;
  Brightness? _atmosphereBrightness;
  SonusArtworkColors? _artworkColors;

  /// Asks for the colours of the artwork now on screen. Never sets state
  /// synchronously, so it is safe to call while building.
  void _requestAtmosphere(String? artworkPath, Brightness brightness) {
    if (artworkPath == _atmospherePath && brightness == _atmosphereBrightness) {
      return;
    }
    _atmospherePath = artworkPath;
    _atmosphereBrightness = brightness;

    unawaited(
      _palette.colorsFor(artworkPath, brightness: brightness).then((colors) {
        // Newer artwork may have been requested since.
        if (!mounted ||
            artworkPath != _atmospherePath ||
            brightness != _atmosphereBrightness ||
            colors == _artworkColors) {
          return;
        }
        setState(() {
          _artworkColors = colors;
        });
      }),
    );
  }

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    _requestAtmosphere(
      _atmosphereArtworkPath(controller),
      Theme.of(context).brightness,
    );
  }

  /// The artist's header image, or else the cover of their first album.
  String? _atmosphereArtworkPath(ArtistProfileController controller) {
    final header = controller.headerArtworkPath;
    if (header != null) return header;

    for (final album in controller.albums) {
      final path = album.artworkPath?.trim();
      if (path != null && path.isNotEmpty) return path;
    }
    return null;
  }

  /// Qualified plays come from the app's analytics scope. Pages built
  /// without one (previews, focused tests) simply show no Top Tracks.
  static QualifiedPlayRepository? _qualifiedPlays(BuildContext context) {
    try {
      return context.read<QualifiedPlayRepository?>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Opens [page], then re-reads the ranking: songs may have been played
  /// meanwhile.
  Future<void> _pushAndRefresh(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (!mounted) return;
    await _controller?.refreshTopTracks();
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
    _controller = ArtistProfileController(
      repository: repository,
      artistId: widget.artistId,
      playbackCoordinator: context.read<PlaybackCoordinator?>(),
      songArtistCreditRepository: context.read<SongArtistCreditRepository?>(),
      trackProfileEditingService: context.read<TrackProfileEditingService?>(),
      artworkAssignmentService: context.read<ArtworkAssignmentService?>(),
      artworkFilePicker: context.read<ArtworkFilePicker?>(),
      artistProfileEditingService: context.read<ArtistProfileEditingService?>(),
      songBlockService: context.read<SongBlockService?>(),
      qualifiedPlays: _qualifiedPlays(context),
      artworkCropService: context.read<ArtworkCropService?>(),
      organization: context.read<LibraryOrganizationService?>(),
      projectArtistId: widget.projectArtistId,
    );

    // The artwork can change without this State rebuilding: when the
    // artist loads or its header artwork changes.
    _controller!.addListener(_onControllerChanged);
    final controller = _controller!;
    _refresher = LibraryChangeRefresher(
      signal: widget.changes ?? LibraryChangeSignal.shared,
      kinds: LibraryChangeKind.values.toSet(),
      onChange: () => unawaited(controller.refresh()),
    );
    unawaited(controller.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final accountController = context.watch<AccountController?>();
    final userId = accountController?.user?.id;
    final artistMergeService = context.watch<ArtistMergeService?>();
    final tokens = SonusTheme.of(context);

    if (controller != null) {
      _requestAtmosphere(
        _atmosphereArtworkPath(controller),
        Theme.of(context).brightness,
      );
    }

    final target = SonusArtworkAtmosphere.resolve(
      colors: tokens.colors,
      decoration: tokens.decoration,
      artwork: _artworkColors,
    );
    final reduceMotion =
        tokens.motion.reduced || MediaQuery.disableAnimationsOf(context);

    // Eases between theme and artwork colours instead of flashing; jumps
    // straight there with reduced motion.
    return TweenAnimationBuilder<SonusAtmosphereColors>(
      tween: SonusAtmosphereColorsTween(end: SonusAtmosphereColors.of(target)),
      duration: reduceMotion ? Duration.zero : tokens.motion.baseMedium,
      curve: tokens.motion.curve,
      builder: (context, atmosphere, _) => _buildPage(
        context,
        controller,
        userId,
        artistMergeService,
        atmosphere,
      ),
    );
  }

  Widget _buildPage(
    BuildContext context,
    ArtistProfileController? controller,
    String? userId,
    ArtistMergeService? artistMergeService,
    SonusAtmosphereColors atmosphere,
  ) {
    return Scaffold(
      key: const ValueKey<String>('artist-profile-page'),
      backgroundColor: atmosphere.background,
      // The hero photo runs to the top of the screen, under the bars.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.scrolledUnder)
              ? atmosphere.background
              : Colors.transparent,
        ),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: controller == null
            ? Text(widget.initialArtistName ?? 'Artist')
            : AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  return Text(
                    controller.artist?.name ??
                        widget.initialArtistName ??
                        'Artist',
                  );
                },
              ),
        actions: [
          if (controller != null)
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                return PopupMenuButton<_ArtistMenuAction>(
                  key: const ValueKey<String>('artist-profile-artwork-menu'),
                  enabled:
                      controller.canEditArtwork ||
                      controller.canEditArtist(userId) ||
                      controller.canRemoveArtist(userId) ||
                      artistMergeService != null ||
                      context.read<LibraryOrganizationService?>() != null,
                  tooltip: 'Artist actions',
                  onSelected: (action) {
                    unawaited(
                      _handleArtistAction(
                        controller,
                        action,
                        userId,
                        artistMergeService,
                      ),
                    );
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      key: const ValueKey<String>(
                        'artist-profile-open-studio-menu-item',
                      ),
                      value: _ArtistMenuAction.studio,
                      child: const ListTile(
                        leading: Icon(Icons.tune_rounded),
                        title: Text('Artist Studio'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      key: const ValueKey<String>(
                        'artist-profile-library-placement-menu-item',
                      ),
                      value: _ArtistMenuAction.libraryPlacement,
                      enabled:
                          context.read<LibraryOrganizationService?>() != null,
                      child: const ListTile(
                        leading: Icon(Icons.account_tree_outlined),
                        title: Text('Library placement'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: _ArtistMenuAction.editName,
                      enabled: controller.canEditArtist(userId),
                      child: const ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit artist name'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: _ArtistMenuAction.changeHeader,
                      enabled: controller.canEditArtwork,
                      child: const ListTile(
                        leading: Icon(Icons.image_outlined),
                        title: Text('Change banner photo'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (controller.canCropArtwork &&
                        controller.bannerPath != null)
                      PopupMenuItem(
                        key: const ValueKey<String>(
                          'artist-profile-reposition-banner',
                        ),
                        value: _ArtistMenuAction.repositionBanner,
                        child: const ListTile(
                          leading: Icon(Icons.crop_rounded),
                          title: Text('Reposition banner'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    PopupMenuItem(
                      value: _ArtistMenuAction.clearHeader,
                      enabled: controller.canEditArtwork,
                      child: const ListTile(
                        leading: Icon(Icons.hide_image_outlined),
                        title: Text('Clear banner photo'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: _ArtistMenuAction.changeTopArtists,
                      enabled: controller.canEditArtwork,
                      child: const ListTile(
                        leading: Icon(Icons.account_circle_outlined),
                        title: Text('Change portrait'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (controller.canCropArtwork &&
                        controller.portraitPath != null)
                      PopupMenuItem(
                        key: const ValueKey<String>(
                          'artist-profile-reposition-portrait',
                        ),
                        value: _ArtistMenuAction.repositionPortrait,
                        child: const ListTile(
                          leading: Icon(Icons.crop_rounded),
                          title: Text('Reposition portrait'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    PopupMenuItem(
                      value: _ArtistMenuAction.clearTopArtists,
                      enabled: controller.canEditArtwork,
                      child: const ListTile(
                        leading: Icon(Icons.person_off_outlined),
                        title: Text('Clear portrait'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      key: const ValueKey<String>(
                        'artist-profile-remove-artist-menu-item',
                      ),
                      value: _ArtistMenuAction.removeArtist,
                      enabled: controller.canRemoveArtist(userId),
                      child: const ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Remove artist from library'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
      body: controller == null
          ? const Center(child: Text('Loading artist...'))
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.isLoading && controller.artist == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (controller.hasError && controller.artist == null) {
                  return _ArtistProfileLoadError(onRetry: controller.load);
                }

                if (controller.isNotFound) {
                  return const _ArtistNotFound();
                }

                final artist = controller.artist;

                if (artist == null) {
                  return const SizedBox.shrink();
                }

                final visibleCollaborations = controller.collaborationTracks
                    .where(_hasAvailableMedia)
                    .toList(growable: false);
                final visibleAlbumIds = controller.allTracks
                    .where(_hasAvailableMedia)
                    .map((track) => track.albumId)
                    .toSet();

                final visibleAlbums = controller.albums
                    .where((album) => visibleAlbumIds.contains(album.albumId))
                    .toList(growable: false);
                final visibleCollaborators = controller.collaborators
                    .where(
                      (collaborator) =>
                          collaborator.tracks.any(_hasAvailableMedia),
                    )
                    .toList(growable: false);
                final topTracks = controller.topTracks;

                if (controller.isContributor) {
                  return _contributorBody(
                    context,
                    controller,
                    userId,
                    atmosphere,
                    artist,
                  );
                }

                final gutter = SonusTheme.of(context).metrics.pageGutter;
                Widget section(Key key, List<Widget> children) => Padding(
                  key: key,
                  padding: EdgeInsets.fromLTRB(gutter, 28, gutter, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                );

                return RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ListView(
                    key: const PageStorageKey<String>('artist-profile-scroll'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    // Clears the system inset and any bottom player.
                    padding: EdgeInsets.only(
                      bottom: 32 + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      ArtistProfileHeader(
                        artist: artist,
                        bannerPath: controller.bannerPath,
                        portraitPath: controller.portraitPath,
                        standing: controller.standing,
                        atmosphere: atmosphere,
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: gutter),
                        child: ArtistProfilePlaybackControls(
                          controller: controller,
                          atmosphere: atmosphere,
                        ),
                      ),
                      if (topTracks.isNotEmpty)
                        section(
                          const ValueKey<String>('artist-profile-top-tracks'),
                          [
                            const ArtistProfileSectionHeading(
                              title: 'Top Tracks',
                              subtitle: 'Your most streamed, all time',
                            ),
                            const SizedBox(height: 8),
                            _tracksList(
                              context,
                              controller,
                              userId,
                              atmosphere,
                              tracks: [
                                for (final entry in topTracks) entry.track,
                              ],
                              keyPrefix: 'artist-top-track',
                              onPlay: controller.playTopTrack,
                              streamCounts: {
                                for (final entry in topTracks)
                                  entry.track.songId: entry.streamCount,
                              },
                            ),
                          ],
                        ),
                      if (visibleAlbums.isNotEmpty)
                        section(
                          const ValueKey<String>('artist-profile-albums'),
                          [
                            ArtistProfileSectionHeading(
                              title: 'Albums',
                              count: visibleAlbums.length,
                            ),
                            const SizedBox(height: 12),
                            ArtistProfileAlbumsGrid(
                              albums: visibleAlbums,
                              onAlbumTap: (album) {
                                unawaited(
                                  _pushAndRefresh(
                                    AlbumProfilePage(
                                      albumId: album.albumId,
                                      initialAlbumTitle: album.title,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      if (visibleCollaborations.isNotEmpty)
                        section(
                          const ValueKey<String>(
                            'artist-profile-collaborations',
                          ),
                          [
                            ArtistProfileSectionHeading(
                              title: 'Collaborations',
                              count: visibleCollaborations.length,
                            ),
                            const SizedBox(height: 8),
                            _tracksList(
                              context,
                              controller,
                              userId,
                              atmosphere,
                              tracks: visibleCollaborations,
                              keyPrefix: 'artist-track',
                              profileArtistId: artist.artistId,
                            ),
                          ],
                        ),
                      if (visibleCollaborators.isNotEmpty)
                        section(
                          const ValueKey<String>(
                            'artist-profile-collaborators',
                          ),
                          [
                            ArtistProfileSectionHeading(
                              title: 'Collaborators',
                              count: visibleCollaborators.length,
                              subtitle: 'Lead artists on these albums',
                            ),
                            const SizedBox(height: 8),
                            ArtistProfileCollaborators(
                              collaborators: visibleCollaborators,
                              tileColor: atmosphere.surface,
                              isPlayable: (collaborator) => collaborator.tracks
                                  .any(controller.isTrackPlayable),
                              onPlay: controller.playCollaborator,
                              onOpen: _openCollaborator,
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _openCollaborator(ArtistProfileCollaborator collaborator) {
    unawaited(
      _pushAndRefresh(
        ArtistProfilePage(
          artistId: collaborator.artistId,
          initialArtistName: collaborator.name,
          artworkPalette: widget.artworkPalette,
          // A contributor's page then shows its songs on this project.
          projectArtistId: widget.artistId,
        ),
      ),
    );
  }

  /// A contributor's page: who it is and where it appears. It never
  /// presents the projects as the contributor's own releases.
  Widget _contributorBody(
    BuildContext context,
    ArtistProfileController controller,
    String? userId,
    SonusAtmosphereColors atmosphere,
    LibraryArtist artist,
  ) {
    final gutter = SonusTheme.of(context).metrics.pageGutter;
    final appearances = controller.appearances;
    final songCount = appearances.fold(
      0,
      (sum, appearance) => sum + appearance.tracks.length,
    );
    final summary = appearances.length == 1
        ? 'On ${appearances.single.ownerName} · '
              '${sonusCount(songCount, 'song')}'
        : appearances.isEmpty
        ? 'No songs in your library'
        : 'On ${appearances.length} projects · '
              '${sonusCount(songCount, 'song')}';

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        key: const PageStorageKey<String>('artist-profile-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: 32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          ArtistProfileHeader(
            artist: artist,
            bannerPath: controller.bannerPath,
            portraitPath: controller.portraitPath,
            atmosphere: atmosphere,
            summary: summary,
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: ArtistProfilePlaybackControls(
              controller: controller,
              atmosphere: atmosphere,
            ),
          ),
          for (final appearance in appearances)
            Padding(
              key: ValueKey<String>(
                'artist-profile-appearance-${appearance.ownerArtistId}',
              ),
              padding: EdgeInsets.fromLTRB(gutter, 28, gutter, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ArtistProfileSectionHeading(
                    title: 'On ${appearance.ownerName}',
                    count: appearance.tracks.length,
                    subtitle: appearance.albums
                        .map((album) => album.title)
                        .join(' · '),
                  ),
                  const SizedBox(height: 8),
                  _tracksList(
                    context,
                    controller,
                    userId,
                    atmosphere,
                    tracks: appearance.tracks
                        .where(_hasAvailableMedia)
                        .toList(growable: false),
                    keyPrefix: 'artist-appearance-track',
                    profileArtistId: artist.artistId,
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: ValueKey<String>(
                        'artist-profile-open-project-'
                        '${appearance.ownerArtistId}',
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => unawaited(
                        _pushAndRefresh(
                          ArtistProfilePage(
                            artistId: appearance.ownerArtistId,
                            initialArtistName: appearance.ownerName,
                            artworkPalette: widget.artworkPalette,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text('Open ${appearance.ownerName}'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tracksList(
    BuildContext context,
    ArtistProfileController controller,
    String? userId,
    SonusAtmosphereColors atmosphere, {
    required List<LibraryTrack> tracks,
    required String keyPrefix,
    Map<String, int>? streamCounts,
    String? profileArtistId,
    Future<void> Function(LibraryTrack track)? onPlay,
  }) {
    return ArtistProfileTracksList(
      tracks: tracks,
      profileArtistId: profileArtistId,
      keyPrefix: keyPrefix,
      streamCounts: streamCounts,
      tileColor: atmosphere.surface,
      isTrackPlayable: controller.isTrackPlayable,
      canEditArtwork: controller.canEditTrackArtwork,
      canEditTrack: controller.canEditTrack(userId),
      canSetBlocked: controller.canSetTrackBlocked(userId),
      onPlay: onPlay ?? controller.playTrack,
      onPlayNext: controller.playNext,
      onAddToQueue: controller.addToQueue,
      onAddToPlaylist: (track) => showAddToPlaylistFlow(context, track),
      onEditTrack: (track) => _editTrack(controller, track, userId),
      onChangeArtwork: (track) => _changeTrackArtwork(controller, track),
      onClearArtwork: (track) => _clearTrackArtwork(controller, track),
      onSetBlocked: (track, isBlocked) =>
          _setTrackBlocked(controller, track, userId, isBlocked),
    );
  }

  bool _hasAvailableMedia(LibraryTrack track) {
    return track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }

  Future<void> _handleArtistAction(
    ArtistProfileController controller,
    _ArtistMenuAction action,
    String? userId,
    ArtistMergeService? artistMergeService,
  ) async {
    if (action == _ArtistMenuAction.studio) {
      await _openArtistStudio(controller, userId, artistMergeService);
      return;
    }
    if (action == _ArtistMenuAction.libraryPlacement) {
      await _openLibraryPlacement(controller);
      return;
    }
    if (action == _ArtistMenuAction.editName) {
      await _editArtistName(controller, userId);
      return;
    }

    if (action == _ArtistMenuAction.removeArtist) {
      await _removeArtist(controller, userId);
      return;
    }

    if (action == _ArtistMenuAction.repositionBanner ||
        action == _ArtistMenuAction.repositionPortrait) {
      await _repositionArtwork(
        controller,
        action == _ArtistMenuAction.repositionBanner
            ? ArtworkCropTarget.artistBanner
            : ArtworkCropTarget.artistPortrait,
        userId,
      );
      return;
    }

    await _handleArtworkAction(controller, action, userId);
  }

  /// "Assign to Project", "Show as its own artist" and "Undo my choice".
  Future<void> _openLibraryPlacement(ArtistProfileController controller) async {
    final service = context.read<LibraryOrganizationService?>();
    final repository = _repository;
    final artist = controller.artist;

    if (service == null || repository == null || artist == null) return;

    await showArtistLibraryPlacement(
      context,
      artistId: artist.artistId,
      artistName: artist.name,
      service: service,
      library: repository,
    );
  }

  Future<void> _openArtistStudio(
    ArtistProfileController controller,
    String? userId,
    ArtistMergeService? artistMergeService,
  ) async {
    final repository = _repository;

    if (repository == null || controller.artist == null) {
      return;
    }

    final metadataProvider = context.read<MetadataProvider?>();
    final externalMetadataApplicationService = context
        .read<ExternalMetadataApplicationService?>();
    final externalMetadataProposalService = context
        .read<ExternalMetadataProposalService?>();

    final result = await Navigator.of(context).push<ArtistStudioMergeResult>(
      MaterialPageRoute<ArtistStudioMergeResult>(
        builder: (_) => ArtistStudioPage(
          controller: controller,
          repository: repository,
          userId: userId,
          mergeService: artistMergeService,
          metadataProvider: metadataProvider,
          externalMetadataApplicationService:
              externalMetadataApplicationService,
          externalMetadataProposalService: externalMetadataProposalService,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ArtistProfilePage(
          artistId: result.targetArtistId,
          initialArtistName: result.targetArtistName,
        ),
      ),
    );
  }

  Future<void> _removeArtist(
    ArtistProfileController controller,
    String? userId,
  ) async {
    final artist = controller.artist;

    if (artist == null || !controller.canRemoveArtist(userId)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: const ValueKey<String>('artist-remove-confirmation-dialog'),
          title: Text('Remove ${artist.name}?'),
          content: const Text(
            'This removes the artist entry from Sonus. '
            'Your music and audio files will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey<String>('artist-remove-confirm-button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    try {
      final removed = await controller.removeArtist(userId: userId);

      if (!mounted || !removed) {
        return;
      }

      Navigator.of(context).pop();
    } on ArtistStillReferencedException {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: ValueKey<String>('artist-remove-referenced-message'),
          content: Text(
            'This artist still has songs or albums in your library. '
            'Reassign them before removing the artist.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: ValueKey<String>('artist-remove-error-message'),
          content: Text('Could not remove artist.'),
        ),
      );
    }
  }

  Future<void> _editArtistName(
    ArtistProfileController controller,
    String? userId,
  ) async {
    final artist = controller.artist;

    if (artist == null || !controller.canEditArtist(userId)) {
      return;
    }

    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return _ArtistNameEditDialog(initialName: artist.name);
        },
      );

      if (!mounted || name == null) {
        return;
      }

      final changed = await controller.renameArtist(userId: userId, name: name);

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Artist name updated.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update artist name.')),
      );
    }
  }

  Future<void> _handleArtworkAction(
    ArtistProfileController controller,
    _ArtistMenuAction action,
    String? userId,
  ) async {
    try {
      final changed = switch (action) {
        _ArtistMenuAction.studio => false,
        _ArtistMenuAction.libraryPlacement => false,
        _ArtistMenuAction.editName => false,
        _ArtistMenuAction.removeArtist => false,
        _ArtistMenuAction.repositionBanner ||
        _ArtistMenuAction.repositionPortrait => false,
        _ArtistMenuAction.changeHeader =>
          controller.canCropArtwork
              ? await _pickAndCrop(
                  controller,
                  ArtworkCropTarget.artistBanner,
                  userId,
                )
              : await controller.changeHeaderArtwork(userId: userId),
        _ArtistMenuAction.clearHeader => await controller.clearHeaderArtwork(
          userId: userId,
        ),
        _ArtistMenuAction.changeTopArtists =>
          controller.canCropArtwork
              ? await _pickAndCrop(
                  controller,
                  ArtworkCropTarget.artistPortrait,
                  userId,
                )
              : await controller.changeTopArtistsArtwork(userId: userId),
        _ArtistMenuAction.clearTopArtists =>
          await controller.clearTopArtistsArtwork(userId: userId),
      };

      if (!mounted || !changed) {
        return;
      }

      final message = switch (action) {
        _ArtistMenuAction.studio => '',
        _ArtistMenuAction.libraryPlacement => '',
        _ArtistMenuAction.editName => '',
        _ArtistMenuAction.removeArtist => '',
        _ArtistMenuAction.repositionBanner ||
        _ArtistMenuAction.repositionPortrait => '',
        _ArtistMenuAction.changeHeader => 'Banner photo updated.',
        _ArtistMenuAction.clearHeader => 'Banner photo cleared.',
        _ArtistMenuAction.changeTopArtists => 'Portrait updated.',
        _ArtistMenuAction.clearTopArtists => 'Portrait cleared.',
      };

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update artist artwork.')),
      );
    }
  }

  Future<bool> _pickAndCrop(
    ArtistProfileController controller,
    ArtworkCropTarget target,
    String? userId,
  ) async {
    final path = await controller.pickArtworkFile();

    if (path == null || !mounted) {
      return false;
    }

    final decision = await showArtworkCropEditor(
      context,
      imagePath: path,
      target: target,
      previewName: controller.artist?.name,
    );

    if (decision is! ArtworkCropSave) {
      return false;
    }

    return controller.applyArtworkCrop(
      target: target,
      sourcePath: path,
      rect: decision.rect,
      userId: userId,
    );
  }

  Future<void> _repositionArtwork(
    ArtistProfileController controller,
    ArtworkCropTarget target,
    String? userId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = target == ArtworkCropTarget.artistBanner
        ? 'banner'
        : 'portrait';

    try {
      final source = await controller.artworkRepositionSource(target);

      if (source == null || !mounted) {
        return;
      }

      final decision = await showArtworkCropEditor(
        context,
        imagePath: source.filePath,
        target: target,
        initialRect: source.rect,
        canReset: source.isRecropping,
        previewName: controller.artist?.name,
      );

      final String? message = switch (decision) {
        ArtworkCropSave(:final rect) =>
          await controller.applyArtworkCrop(
                target: target,
                sourcePath: source.filePath,
                rect: rect,
                userId: userId,
              )
              ? 'The $name was repositioned.'
              : null,
        ArtworkCropReset() =>
          await controller.resetArtworkCrop(target, userId: userId)
              ? 'The full original $name is back.'
              : null,
        null => null,
      };

      if (message != null && mounted) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not reposition the $name.')),
        );
      }
    }
  }

  Future<void> _setTrackBlocked(
    ArtistProfileController controller,
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

  Future<void> _editTrack(
    ArtistProfileController controller,
    LibraryTrack track,
    String? userId,
  ) async {
    try {
      final repository = _repository;

      if (repository == null) {
        return;
      }

      final artists = await repository.getArtists();
      final albums = await repository.getAlbums();
      final structuredCredits = await controller.getTrackAdditionalCredits(
        track.songId,
      );

      if (!mounted) {
        return;
      }

      final initialAdditionalCredits = structuredCredits
          .map(
            (credit) => TrackProfileCreditDraft(
              creditedName: credit.creditedName,
              role: credit.role,
              artistId: credit.artistId,
            ),
          )
          .toList(growable: false);
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

      if (!mounted) {
        return;
      }

      if (draft == null) {
        await controller.refreshTopTracks();
        return;
      }

      final changed = await controller.updateTrackWithCredits(
        userId: userId,
        track: track,
        title: draft.title,
        trackNumber: draft.trackNumber,
        discNumber: draft.discNumber,
        additionalCredits: draft.additionalCredits.map(
          (credit) => SongArtistCreditInput(
            creditedName: credit.creditedName,
            role: credit.role,
            artistId: credit.artistId,
          ),
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

  Future<void> _changeTrackArtwork(
    ArtistProfileController controller,
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
    ArtistProfileController controller,
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
    _refresher?.dispose();
    _controller?.dispose();
    super.dispose();
  }
}

class _ArtistNameEditDialog extends StatefulWidget {
  const _ArtistNameEditDialog({required this.initialName});

  final String initialName;

  @override
  State<_ArtistNameEditDialog> createState() => _ArtistNameEditDialogState();
}

class _ArtistNameEditDialogState extends State<_ArtistNameEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    Navigator.of(context).pop(_textController.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit artist name'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const ValueKey<String>('artist-name-field'),
          controller: _textController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Artist name'),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Artist name cannot be blank.';
            }

            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

enum _ArtistMenuAction {
  studio,
  libraryPlacement,
  editName,
  changeHeader,
  clearHeader,
  repositionBanner,
  changeTopArtists,
  repositionPortrait,
  clearTopArtists,
  removeArtist,
}

class _ArtistProfileLoadError extends StatelessWidget {
  const _ArtistProfileLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Could not load this artist.',
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

class _ArtistNotFound extends StatelessWidget {
  const _ArtistNotFound();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 48),
            SizedBox(height: 16),
            Text('Artist not found', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
