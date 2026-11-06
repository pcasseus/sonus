import '../../../artwork/presentation/pages/artwork_crop_editor_page.dart';
import '../../../artwork/domain/entities/artwork_crop.dart';
import '../../../artwork/application/services/artwork_crop_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/context/sonus_context_theme.dart';
import '../../../../core/design/sonus_artwork_palette.dart';
import '../../../../core/design/sonus_profile_colors.dart';
import '../../../../core/design/widgets/sonus_profile_surfaces.dart';
import '../../../../core/design/widgets/sonus_artwork_environment.dart';
import '../../../../core/design/widgets/sonus_frosted_glass.dart';
import '../../../../core/design/widgets/sonus_secondary_text_scope.dart';
import '../../../../core/design/widgets/sonus_profile_atmosphere_builder.dart';
import '../../../../core/design/sonus_atmosphere_colors.dart';
import '../../../../core/design/sonus_theme.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../domain/repositories/song_artist_credit_repository.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../analytics/domain/repositories/qualified_play_repository.dart';
import '../../../analytics/domain/repositories/playback_listening_segment_repository.dart';
import '../../../analytics/domain/repositories/playback_session_repository.dart';
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
import '../../application/services/library_organization_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import '../controllers/artist_profile_controller.dart';
import '../controllers/track_selection_controller.dart';
import '../models/artist_profile_sections.dart';
import '../models/artist_removal_message.dart';
import '../models/track_profile_edit_draft.dart';
import '../widgets/artist_profile/artist_profile_albums_grid.dart';
import '../widgets/artist_profile/artist_profile_collaborators.dart';
import '../widgets/artist_profile/artist_profile_header.dart';
import '../widgets/artist_profile/artist_profile_tracks_list.dart';
import '../widgets/artist_profile/artist_profile_playback_controls.dart';
import '../widgets/artist_profile/artist_profile_section_heading.dart';
import '../widgets/artist_profile/artist_library_placement_sheet.dart';
import '../widgets/track_selection_bar.dart';
import '../widgets/track_studio_launcher.dart';
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
  /// Whether the hero's name has scrolled under the toolbar. Until then
  /// the hero alone names the artist; afterwards the toolbar does.
  final ValueNotifier<bool> _titleShown = ValueNotifier<bool>(false);

  LibraryChangeRefresher? _refresher;
  ArtistProfileController? _controller;
  LibraryQueryRepository? _repository;
  final TrackSelectionController _selection = TrackSelectionController();

  /// The artwork the page's atmosphere comes from. Updated as soon as the
  /// controller changes (it notifies without rebuilding this State), so
  /// [SonusProfileAtmosphereBuilder] requests its colours at once.
  final ValueNotifier<String?> _atmosphereArtwork = ValueNotifier<String?>(
    null,
  );

  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    _atmosphereArtwork.value = _atmosphereArtworkPath(controller);
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
  static QualifiedPlayRepository? _qualifiedPlays(BuildContext context) =>
      _optional<QualifiedPlayRepository>(context);

  static T? _optional<T extends Object>(BuildContext context) {
    try {
      return context.read<T?>();
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
      playbackSessions: _optional<PlaybackSessionRepository>(context),
      listeningSegments: _optional<PlaybackListeningSegmentRepository>(context),
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
    // UI redesign P1: the artwork's own colours carry the page.
    return SonusProfileAtmosphereBuilder.listenable(
      artworkPath: _atmosphereArtwork,
      palette: widget.artworkPalette,
      // Theme architecture: the page's menus, dialogs, sheets, buttons and
      // rows take the artwork's colours, not the theme's blue and charcoal.
      builder: (context, resolved) {
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
                builder: (context) => _buildPage(
                  context,
                  controller,
                  userId,
                  artistMergeService,
                  profile,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPage(
    BuildContext context,
    ArtistProfileController? controller,
    String? userId,
    ArtistMergeService? artistMergeService,
    SonusProfileColors profile,
  ) {
    final atmosphere = profile.atmosphere;
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
        scrolledUnderElevation: 0,
        title: ValueListenableBuilder<bool>(
          valueListenable: _titleShown,
          builder: (context, shown, _) => ExcludeSemantics(
            excluding: !shown,
            child: AnimatedOpacity(
              key: const ValueKey<String>('artist-profile-toolbar-title'),
              opacity: shown ? 1 : 0,
              duration: SonusTheme.of(context).motion.reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              child: controller == null
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
            ),
          ),
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
      // V1: the artwork's colour and light behind the whole page, still
      // while the content scrolls over it.
      body: SonusProfileBackdrop(
        profile: profile,
        baseKey: const ValueKey<String>('artist-profile-background'),
        // The artwork itself behind the page (Profile Lab method): blurred,
        // tone-mapped, still while the content scrolls over it.
        environment: ValueListenableBuilder<String?>(
          valueListenable: _atmosphereArtwork,
          // Neutral artwork, which gives no tint, still lights the page.
          builder: (context, path, _) => SonusArtworkEnvironment(
            artworkPath: path,
            light: profile.light,
            deep: profile.backgroundDeep,
            enabled: SonusTheme.of(context).decoration.allowGradients,
          ),
        ),
        child: controller == null
            ? const Center(child: Text('Loading artist...'))
            : AnimatedBuilder(
                animation: Listenable.merge([controller, _selection]),
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

                  // Unavailable songs and releases stay listed, marked
                  // (B-Q24, B-Q28).
                  final collaborations = controller.collaborationTracks;
                  final albumIds = {
                    for (final track in controller.allTracks) track.albumId,
                  };
                  final playableAlbumIds = {
                    for (final track in controller.allTracks)
                      if (_hasAvailableMedia(track)) track.albumId,
                  };
                  final shelves = ArtistProfileSections.releaseShelves(
                    albums: controller.albums.where(
                      (album) => albumIds.contains(album.albumId),
                    ),
                    formatOf: controller.formatOf,
                    hasStatedFormat: controller.hasStatedFormat,
                    isLive: controller.isLive,
                    isLeaked: controller.isLeaked,
                    kindOf: controller.kindOf,
                    isUnavailable: (album) =>
                        !playableAlbumIds.contains(album.albumId),
                  );
                  final collaborators = [
                    for (final collaborator in controller.collaborators)
                      if (collaborator.displaySongCount > 0) collaborator,
                  ];
                  final topTracks = controller.topTracks;

                  if (controller.isContributor) {
                    return TrackSelectionScope(
                      controller: _selection,
                      visibleTracks: [
                        for (final appearance in controller.appearances)
                          ...appearance.tracks.where(_hasAvailableMedia),
                      ],
                      child: _contributorBody(
                        context,
                        controller,
                        userId,
                        profile,
                        artist,
                      ),
                    );
                  }

                  final gutter = SonusTheme.of(context).metrics.pageGutter;
                  Widget section(Key key, List<Widget> children) => Padding(
                    key: key,
                    padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  );

                  return TrackSelectionScope(
                    controller: _selection,
                    visibleTracks: [
                      for (final entry in topTracks) entry.track,
                      ...collaborations,
                    ],
                    child: _watchScroll(
                      controller,
                      RefreshIndicator(
                        onRefresh: controller.refresh,
                        child: ListView(
                          key: const PageStorageKey<String>(
                            'artist-profile-scroll',
                          ),
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
                              profile: profile,
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                gutter,
                                16,
                                gutter,
                                0,
                              ),
                              child: ArtistProfilePlaybackControls(
                                controller: controller,
                                atmosphere: atmosphere,
                              ),
                            ),
                            if (topTracks.isNotEmpty)
                              section(
                                const ValueKey<String>(
                                  'artist-profile-top-tracks',
                                ),
                                [
                                  ArtistProfileSectionHeading(
                                    title: 'Top Tracks',
                                    accent: atmosphere.accent,
                                    subtitle: _topTracksSubtitle(
                                      controller.topTracksCountedElsewhere,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _glass(
                                    context,
                                    profile,
                                    key: const ValueKey<String>(
                                      'artist-profile-top-tracks-glass',
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _tracksList(
                                          context,
                                          controller,
                                          userId,
                                          atmosphere,
                                          tracks: [
                                            for (final entry in topTracks)
                                              entry.track,
                                          ],
                                          keyPrefix: 'artist-top-track',
                                          selection: _selection,
                                          profileArtistId: artist.artistId,
                                          onPlay: controller.playTopTrack,
                                          streamCounts: {
                                            for (final entry in topTracks)
                                              entry.track.songId:
                                                  entry.streamCount,
                                          },
                                          onGlass: true,
                                        ),
                                        // V1: the way to every streamed
                                        // song closes the section, inside
                                        // its glass.
                                        if (controller.rankedTracks.length >
                                            topTracks.length)
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              4,
                                              6,
                                              4,
                                              2,
                                            ),
                                            child: TextButton.icon(
                                              key: const ValueKey<String>(
                                                'artist-profile-top-tracks-see-all',
                                              ),
                                              style: TextButton.styleFrom(
                                                minimumSize:
                                                    const Size.fromHeight(48),
                                                foregroundColor:
                                                    profile.textPrimary,
                                                backgroundColor: profile.accent
                                                    .withValues(alpha: 0.10),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              onPressed: () =>
                                                  _openRankedTracks(
                                                    controller,
                                                    userId,
                                                  ),
                                              iconAlignment: IconAlignment.end,
                                              icon: const Icon(
                                                Icons.arrow_forward_rounded,
                                                size: 18,
                                              ),
                                              label: const Text('See All'),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            for (final MapEntry(key: shelf, value: cards)
                                in shelves.entries)
                              section(
                                ValueKey<String>('artist-profile-${shelf.key}'),
                                [
                                  ArtistProfileSectionHeading(
                                    title: shelf.title,
                                    accent: atmosphere.accent,
                                    subtitle:
                                        shelf == ArtistReleaseShelf.needsReview
                                        ? 'Choose Single, EP or Album in '
                                              'Edit Release'
                                        : null,
                                    count: cards.length,
                                  ),
                                  const SizedBox(height: 12),
                                  ArtistProfileAlbumsGrid(
                                    cards: cards,
                                    onAlbumTap: (album) {
                                      unawaited(
                                        _pushAndRefresh(
                                          AlbumProfilePage(
                                            albumId: album.albumId,
                                            initialAlbumTitle:
                                                album.displayTitle,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            if (collaborations.isNotEmpty)
                              section(
                                const ValueKey<String>(
                                  'artist-profile-collaborations',
                                ),
                                [
                                  ArtistProfileSectionHeading(
                                    title: 'Collaborations',
                                    accent: atmosphere.accent,
                                    count: collaborations.length,
                                  ),
                                  const SizedBox(height: 8),
                                  _glass(
                                    context,
                                    profile,
                                    key: const ValueKey<String>(
                                      'artist-profile-collaborations-glass',
                                    ),
                                    _tracksList(
                                      context,
                                      controller,
                                      userId,
                                      atmosphere,
                                      tracks: collaborations,
                                      keyPrefix: 'artist-track',
                                      selection: _selection,
                                      profileArtistId: artist.artistId,
                                      onPlay: controller.playCollaboration,
                                      onGlass: true,
                                      groupByAlbum: true,
                                    ),
                                  ),
                                ],
                              ),
                            if (collaborators.isNotEmpty)
                              section(
                                const ValueKey<String>(
                                  'artist-profile-collaborators',
                                ),
                                [
                                  ArtistProfileSectionHeading(
                                    title: 'Collaborators',
                                    accent: atmosphere.accent,
                                    count: collaborators.length,
                                    subtitle:
                                        'Artists who appear on these releases',
                                  ),
                                  const SizedBox(height: 8),
                                  _glass(
                                    context,
                                    profile,
                                    key: const ValueKey<String>(
                                      'artist-profile-collaborators-glass',
                                    ),
                                    ArtistProfileCollaborators(
                                      collaborators: collaborators,
                                      tileColor: Colors.transparent,
                                      isPlayable: (collaborator) => collaborator
                                          .tracks
                                          .any(controller.isTrackPlayable),
                                      onPlay: controller.playCollaborator,
                                      onOpen: _openCollaborator,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  /// A glass section: frosted glass over the artwork environment (Profile
  /// Lab method), a soft lit rim and an outer shadow; flat and opaque where
  /// effects are off.
  static Widget _glass(
    BuildContext context,
    SonusProfileColors profile,
    Widget child, {
    Key? key,
  }) {
    return SonusFrostedGlass(
      key: key,
      frosted: SonusTheme.of(context).decoration.allowGradients,
      tint: profile.surface,
      light: profile.light,
      shadow: profile.backgroundDeep,
      solid: profile.surface,
      edge: profile.edge,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      // Ink from the rows shows on the glass, not under it.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }

  /// Shows the toolbar title once the hero's name has scrolled under it.
  Widget _watchScroll(ArtistProfileController controller, Widget child) {
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis != Axis.vertical ||
            notification.depth != 0) {
          return false;
        }
        _titleShown.value =
            notification.metrics.pixels >
            ArtistProfileHeader.collapseOffset(
              context,
              width: MediaQuery.sizeOf(context).width,
              hasBanner: controller.bannerPath != null,
            );
        return false;
      },
      child: child,
    );
  }

  /// Says why the header's artist total can be lower than these songs'
  /// streams: songs by artists with their own releases count for them.
  static String _topTracksSubtitle(List<String> countedElsewhere) {
    const base = 'Your most streamed songs';
    if (countedElsewhere.isEmpty) return base;
    final names = countedElsewhere.length <= 2
        ? countedElsewhere.join(' and ')
        : '${countedElsewhere.take(2).join(', ')} and others';
    final owner = countedElsewhere.length == 1
        ? "$names's own artist total"
        : 'their own artist totals';
    return '$base. Streams of songs by $names count toward $owner, '
        'not the one above.';
  }

  /// See All: every streamed song, ranked, playing within the ranking.
  void _openRankedTracks(ArtistProfileController controller, String? userId) {
    final tokens = SonusTheme.of(context);
    // The ranking page has no artwork atmosphere: plain theme colours.
    final atmosphere = SonusAtmosphereColors.of(
      SonusArtworkAtmosphere.resolve(
        colors: tokens.colors,
        decoration: tokens.decoration,
      ),
    );
    unawaited(
      _pushAndRefresh(
        _ArtistRankedTracksPage(
          controller: controller,
          rowOf: (entry, rank) => _tracksList(
            context,
            controller,
            userId,
            atmosphere,
            tracks: [entry.track],
            keyPrefix: 'artist-ranked-track',
            profileArtistId: controller.artistId,
            onPlay: controller.playRankedTrack,
            streamCounts: {entry.track.songId: entry.streamCount},
            firstRank: rank,
          ),
        ),
      ),
    );
  }

  /// Opens a verified collaborator's page; a credit that is only a name
  /// has none (B-Q33).
  void _openCollaborator(ArtistProfileCollaborator collaborator) {
    final artistId = collaborator.artistId;
    if (artistId == null) return;
    unawaited(
      _pushAndRefresh(
        ArtistProfilePage(
          artistId: artistId,
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
    SonusProfileColors profile,
    LibraryArtist artist,
  ) {
    final gutter = SonusTheme.of(context).metrics.pageGutter;
    final appearances = controller.appearances;
    final atmosphere = profile.atmosphere;
    final summary = _projectContext([
      for (final appearance in appearances) appearance.ownerName,
    ]);

    return _watchScroll(
      controller,
      RefreshIndicator(
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
              profile: profile,
              summary: summary,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
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
                padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ArtistProfileSectionHeading(
                      title: 'On ${appearance.ownerName}',
                      accent: atmosphere.accent,
                      count: appearance.tracks.length,
                      subtitle: appearance.albums
                          .map((album) => album.displayTitle)
                          .join(' · '),
                    ),
                    const SizedBox(height: 8),
                    _glass(
                      context,
                      profile,
                      _tracksList(
                        context,
                        controller,
                        userId,
                        atmosphere,
                        tracks: appearance.tracks
                            .where(_hasAvailableMedia)
                            .toList(growable: false),
                        keyPrefix: 'artist-appearance-track',
                        selection: _selection,
                        profileArtistId: artist.artistId,
                        onGlass: true,
                      ),
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
      ),
    );
  }

  /// "On Descendants" or "On Descendants, Zombies and others": where a
  /// contributor appears, without counts (B-Q2).
  static String _projectContext(List<String> owners) {
    if (owners.isEmpty) return 'No songs in your library';
    final names = owners.length <= 2
        ? owners.join(' and ')
        : '${owners.take(2).join(', ')} and others';
    return 'On $names';
  }

  Widget _tracksList(
    BuildContext context,
    ArtistProfileController controller,
    String? userId,
    SonusAtmosphereColors atmosphere, {
    required List<LibraryTrack> tracks,
    required String keyPrefix,
    Map<String, int>? streamCounts,
    int firstRank = 1,
    String? profileArtistId,
    Future<void> Function(LibraryTrack track)? onPlay,
    TrackSelectionController? selection,
    bool onGlass = false,
    bool groupByAlbum = false,
  }) {
    return ArtistProfileTracksList(
      tracks: tracks,
      groupByAlbum: groupByAlbum,
      selection: selection,
      profileArtistId: profileArtistId,
      keyPrefix: keyPrefix,
      streamCounts: streamCounts,
      firstRank: firstRank,
      tileColor: onGlass ? Colors.transparent : atmosphere.surface,
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
      onGoToAlbum: (track) => unawaited(
        _pushAndRefresh(
          AlbumProfilePage(
            albumId: track.albumId,
            initialAlbumTitle: track.albumTitle,
            initialEditionId: track.albumEditionId,
          ),
        ),
      ),
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
    } on ArtistStillReferencedException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey<String>('artist-remove-referenced-message'),
          content: Text(artistRemovalBlockedMessage(error.references)),
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
    _titleShown.dispose();
    _selection.dispose();
    _controller?.removeListener(_onControllerChanged);
    _refresher?.dispose();
    _controller?.dispose();
    _atmosphereArtwork.dispose();
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

/// Every streamed song of the artist, most streamed first (B-Q29/B-Q35).
class _ArtistRankedTracksPage extends StatelessWidget {
  const _ArtistRankedTracksPage({
    required this.controller,
    required this.rowOf,
  });

  final ArtistProfileController controller;
  final Widget Function(ArtistTopTrack entry, int rank) rowOf;

  @override
  Widget build(BuildContext context) {
    final gutter = SonusTheme.of(context).metrics.pageGutter;

    return Scaffold(
      key: const ValueKey<String>('artist-ranked-tracks-page'),
      appBar: AppBar(title: const Text('Top Tracks')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final ranked = controller.rankedTracks;
          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
              gutter,
              8,
              gutter,
              32 + MediaQuery.paddingOf(context).bottom,
            ),
            itemCount: ranked.length,
            itemBuilder: (context, index) => rowOf(ranked[index], index + 1),
          );
        },
      ),
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
