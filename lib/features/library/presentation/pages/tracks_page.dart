import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_page_header.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../../core/design/widgets/sonus_track_tile.dart';
import '../../../../core/events/library_change_signal.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../application/models/library_artist.dart';
import '../../application/services/external_metadata_application_service.dart';
import '../../application/services/external_metadata_proposal_service.dart';
import '../../application/services/metadata_provider.dart';
import '../../application/models/library_track.dart';
import '../../application/models/library_track_order.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/artist_creation_service.dart';
import '../../application/services/song_block_service.dart';
import '../../application/services/song_artist_credit_service.dart';
import '../../application/services/track_profile_editing_service.dart';
import '../../domain/repositories/song_artist_credit_repository.dart';
import '../controllers/library_tracks_controller.dart';
import '../models/track_profile_edit_draft.dart';
import 'track_studio_page.dart';

class TracksPage extends StatefulWidget {
  const TracksPage({super.key, this.changes});

  /// Reloads after library edits, imports and recorded listening; the
  /// shared signal if null.
  final LibraryChangeSignal? changes;

  @override
  State<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends State<TracksPage> {
  LibraryChangeRefresher? _refresher;
  LibraryTracksController? _controller;
  LibraryQueryRepository? _repository;

  /// The song now playing, read from the player without changing it. Only
  /// changes of song rebuild the list, not every position update.
  Stream<String?>? _currentSongIds;
  PlaybackCoordinator? _coordinator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final repository = context.watch<LibraryQueryRepository?>();

    if (repository == null || identical(repository, _repository)) {
      return;
    }

    _refresher?.dispose();
    _controller?.dispose();

    _repository = repository;

    final coordinator = context.read<PlaybackCoordinator>();
    if (!identical(coordinator, _coordinator)) {
      _coordinator = coordinator;
      _currentSongIds = coordinator.states
          .map((state) => state.queue.currentTrack?.songId)
          .distinct();
    }

    _controller = LibraryTracksController(
      repository: repository,
      playbackCoordinator: coordinator,
      songArtistCreditRepository: context.read<SongArtistCreditRepository?>(),
      trackProfileEditingService: context.read<TrackProfileEditingService?>(),
      songBlockService: context.read<SongBlockService?>(),
      artworkAssignmentService: context.read<ArtworkAssignmentService?>(),
      artworkFilePicker: context.read<ArtworkFilePicker?>(),
    );

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

    if (controller == null) {
      return const SizedBox(
        key: ValueKey<String>('app-destination-tracks'),
        child: Center(child: Text('Loading tracks...')),
      );
    }

    return SizedBox(
      key: const ValueKey<String>('app-destination-tracks'),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final visibleTracks = controller.tracks
              .where(_hasAvailableMedia)
              .toList(growable: false);

          if (controller.isLoading && controller.tracks.isEmpty) {
            return const SonusStateView.loading();
          }

          if (controller.hasError && controller.tracks.isEmpty) {
            return _LibraryLoadError(
              message: 'Could not load your tracks.',
              onRetry: controller.load,
            );
          }

          if (!controller.isLoading && visibleTracks.isEmpty) {
            return RefreshIndicator(
              onRefresh: controller.refresh,
              child: const CustomScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyTracksState(),
                  ),
                ],
              ),
            );
          }

          final gutter = SonusTheme.of(context).metrics.pageGutter;

          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: StreamBuilder<String?>(
              stream: _currentSongIds,
              initialData:
                  _coordinator?.currentState.queue.currentTrack?.songId,
              builder: (context, current) => CustomScrollView(
                key: const PageStorageKey<String>('tracks-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _TracksHeader(trackCount: visibleTracks.length),
                  ),
                  SliverToBoxAdapter(
                    child: _TracksControls(controller: controller),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      gutter - 4,
                      4,
                      gutter - 4,
                      120 + MediaQuery.paddingOf(context).bottom,
                    ),
                    // Lazy: only rows on screen are built, for large libraries.
                    sliver: SliverList.builder(
                      itemCount: visibleTracks.length,
                      itemBuilder: (context, index) {
                        final track = visibleTracks[index];

                        return _TrackTile(
                          track: track,
                          isPlayable: controller.isTrackPlayable(track),
                          isCurrent: current.data == track.songId,
                          canEditArtwork: controller.canEditArtwork,
                          canEditTrack: controller.canEditTrack(userId),
                          canSetBlocked: controller.canSetTrackBlocked(userId),
                          onPlay: () => controller.playTrack(track),
                          onPlayNext: () => controller.playNext(track),
                          onAddToQueue: () => controller.addToQueue(track),
                          onAddToPlaylist: () =>
                              showAddToPlaylistFlow(context, track),
                          onEditTrack: () =>
                              _editTrack(controller, track, userId),
                          onChangeArtwork: () =>
                              _changeArtwork(controller, track),
                          onClearArtwork: () =>
                              _clearArtwork(controller, track),
                          onSetBlocked: (isBlocked) => _setTrackBlocked(
                            controller,
                            track,
                            userId,
                            isBlocked,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool _hasAvailableMedia(LibraryTrack track) {
    return track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }

  Future<void> _editTrack(
    LibraryTracksController controller,
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
      final artistCreationService = context.read<ArtistCreationService?>();
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
              onCreateArtist: artistCreationService == null
                  ? null
                  : (name) async {
                      final artist = await artistCreationService.createOrReuse(
                        userId: userId,
                        name: name,
                      );

                      return LibraryArtist(
                        artistId: artist.id,
                        name: artist.name,
                        albumCount: 0,
                        songCount: 0,
                        dateAdded: artist.createdAt,
                      );
                    },
              onChangeArtwork: controller.canEditArtwork
                  ? () => _changeArtwork(controller, track)
                  : null,
              onClearArtwork: controller.canEditArtwork
                  ? () => _clearArtwork(controller, track)
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

  Future<void> _setTrackBlocked(
    LibraryTracksController controller,
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

  Future<void> _changeArtwork(
    LibraryTracksController controller,
    LibraryTrack track,
  ) async {
    try {
      final changed = await controller.changeArtwork(track);

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

  Future<void> _clearArtwork(
    LibraryTracksController controller,
    LibraryTrack track,
  ) async {
    try {
      final changed = await controller.clearArtwork(track);

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
    _refresher?.dispose();
    _controller?.dispose();
    super.dispose();
  }
}

class _TracksHeader extends StatelessWidget {
  const _TracksHeader({required this.trackCount});

  final int trackCount;

  @override
  Widget build(BuildContext context) {
    return SonusPageHeader(
      title: 'Tracks',
      titleKey: const ValueKey<String>('tracks-page-title'),
      subtitle: trackCount == 1
          ? '1 song in your library'
          : '$trackCount songs in your library',
      subtitleKey: const ValueKey<String>('tracks-count-label'),
    );
  }
}

class _TracksControls extends StatelessWidget {
  const _TracksControls({required this.controller});

  final LibraryTracksController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final radius = BorderRadius.circular(tokens.metrics.controlRadius);
    final gutter = tokens.metrics.pageGutter;

    final playAll = FilledButton.icon(
      key: const ValueKey<String>('tracks-play-all-button'),
      onPressed: controller.playAll,
      icon: const Icon(Icons.play_arrow_rounded),
      label: const Text('Play all', maxLines: 1),
      style: FilledButton.styleFrom(
        backgroundColor: colors.accentPrimary,
        foregroundColor: colors.onAccentPrimary,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    );
    final shuffleStyle = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      foregroundColor: colors.textPrimary,
      side: BorderSide(color: colors.border),
      shape: RoundedRectangleBorder(borderRadius: radius),
    );
    final shuffle = controller.isShuffleEnabled
        ? FilledButton.tonalIcon(
            key: const ValueKey<String>('tracks-shuffle-button'),
            onPressed: () {
              unawaited(controller.toggleShuffle());
            },
            icon: const Icon(Icons.shuffle_on_rounded),
            label: const Text('Shuffle on', maxLines: 1),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: radius),
            ),
          )
        : OutlinedButton.icon(
            key: const ValueKey<String>('tracks-shuffle-button'),
            onPressed: () {
              unawaited(controller.toggleShuffle());
            },
            icon: const Icon(Icons.shuffle_rounded),
            label: const Text('Shuffle', maxLines: 1),
            style: shuffleStyle,
          );
    final sort = DropdownButtonFormField<LibraryTrackOrder>(
      key: const ValueKey<String>('tracks-order-dropdown'),
      initialValue: controller.order,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Sort by',
        prefixIcon: const Icon(Icons.sort_rounded),
        filled: true,
        fillColor: colors.raisedSurface,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colors.focus, width: 2),
        ),
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(
          value: LibraryTrackOrder.title,
          child: Text('Song name'),
        ),
        DropdownMenuItem(
          value: LibraryTrackOrder.artist,
          child: Text('Artist name'),
        ),
        DropdownMenuItem(
          value: LibraryTrackOrder.dateAdded,
          child: Text('Date added'),
        ),
      ],
      onChanged: (order) {
        if (order != null) {
          unawaited(controller.setOrder(order));
        }
      },
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // One row when there is room; otherwise sort sits under the
          // playback buttons.
          if (constraints.maxWidth >= 640) {
            return Row(
              children: [
                Expanded(child: playAll),
                const SizedBox(width: 10),
                Expanded(child: shuffle),
                const SizedBox(width: 10),
                Expanded(child: sort),
              ],
            );
          }

          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: playAll),
                  const SizedBox(width: 10),
                  Expanded(child: shuffle),
                ],
              ),
              const SizedBox(height: 10),
              sort,
            ],
          );
        },
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.isPlayable,
    required this.isCurrent,
    required this.canEditArtwork,
    required this.canEditTrack,
    required this.canSetBlocked,
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
  final bool isPlayable;
  final bool isCurrent;
  final bool canEditArtwork;
  final bool canEditTrack;
  final bool canSetBlocked;

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
    final tokens = SonusTheme.of(context);
    final theme = Theme.of(context);
    final credit = [
      track.artistName,
      if (track.featuredArtists.isNotEmpty)
        'feat. ${track.featuredArtists.join(', ')}',
    ].join(' ');
    final albumTitle = track.albumTitle.trim();

    return SonusTrackTile(
      inkKey: ValueKey<String>('track-${track.songId}'),
      title: track.title,
      subtitle: credit,
      detail: albumTitle,
      artworkPath: track.artworkPath,
      duration: sonusFormatDuration(track.durationSeconds),
      durationKey: ValueKey<String>('track-duration-${track.songId}'),
      enabled: isPlayable,
      isCurrent: isCurrent,
      tileColor: tokens.colors.surface,
      onTap: () {
        unawaited(onPlay());
      },
      status: isPlayable
          ? null
          : Text(
              track.isBlocked ? 'Blacklisted' : 'Unavailable',
              key: ValueKey<String>(
                track.isBlocked
                    ? 'track-blocked-${track.songId}'
                    : 'track-unavailable-${track.songId}',
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
      trailing: PopupMenuButton<_TrackMenuAction>(
        key: ValueKey<String>('track-menu-${track.songId}'),
        enabled: isPlayable || canEditArtwork || canEditTrack || canSetBlocked,
        tooltip: 'Song options',
        onSelected: (action) {
          switch (action) {
            case _TrackMenuAction.playNext:
              unawaited(onPlayNext());
            case _TrackMenuAction.addToQueue:
              unawaited(onAddToQueue());
            case _TrackMenuAction.addToPlaylist:
              unawaited(onAddToPlaylist());
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
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _TrackMenuAction.addToPlaylist,
            child: const ListTile(
              leading: Icon(Icons.playlist_add_rounded),
              title: Text('Add to playlist'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
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
          const PopupMenuDivider(),
        ],
      ),
    );
  }
}

enum _TrackMenuAction {
  playNext,
  addToQueue,
  addToPlaylist,
  trackStudio,
  toggleBlocked,
}

class _EmptyTracksState extends StatelessWidget {
  const _EmptyTracksState();

  @override
  Widget build(BuildContext context) {
    return const SonusStateView(
      icon: Icons.library_music_rounded,
      title: 'No tracks yet',
      message: 'Import music to start building your library.',
    );
  }
}

class _LibraryLoadError extends StatelessWidget {
  const _LibraryLoadError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return SonusStateView(
      icon: Icons.error_outline_rounded,
      isError: true,
      title: message,
      action: FilledButton.tonalIcon(
        onPressed: () {
          unawaited(onRetry());
        },
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try again'),
      ),
    );
  }
}
