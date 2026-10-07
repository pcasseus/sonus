import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/repositories/song_artist_credit_repository.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/artist_profile_editing_service.dart';
import '../../application/services/artist_merge_service.dart';
import '../../application/services/song_block_service.dart';
import '../../application/services/song_artist_credit_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import '../controllers/artist_profile_controller.dart';
import '../models/track_profile_edit_draft.dart';
import '../widgets/artist_profile/artist_profile_albums_grid.dart';
import '../widgets/artist_profile/artist_profile_header.dart';
import '../widgets/artist_profile/artist_profile_tracks_list.dart';
import '../widgets/artist_profile/artist_profile_playback_controls.dart';
import '../widgets/artist_profile/artist_profile_section_heading.dart';
import 'album_profile_page.dart';
import 'artist_studio_page.dart';
import 'track_studio_page.dart';

class ArtistProfilePage extends StatefulWidget {
  const ArtistProfilePage({
    super.key,
    required this.artistId,
    this.initialArtistName,
  });

  final String artistId;
  final String? initialArtistName;

  @override
  State<ArtistProfilePage> createState() => _ArtistProfilePageState();
}

class _ArtistProfilePageState extends State<ArtistProfilePage> {
  ArtistProfileController? _controller;
  LibraryQueryRepository? _repository;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final repository = context.watch<LibraryQueryRepository?>();

    if (repository == null || identical(repository, _repository)) {
      return;
    }

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
    );

    unawaited(_controller!.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final accountController = context.watch<AccountController?>();
    final userId = accountController?.user?.id;
    final artistMergeService = context.watch<ArtistMergeService?>();

    return Scaffold(
      key: const ValueKey<String>('artist-profile-page'),
      appBar: AppBar(
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
                      artistMergeService != null,
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
                        title: Text('Change header artwork'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _ArtistMenuAction.clearHeader,
                      enabled: controller.canEditArtwork,
                      child: const ListTile(
                        leading: Icon(Icons.hide_image_outlined),
                        title: Text('Clear header artwork'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: _ArtistMenuAction.changeTopArtists,
                      enabled: controller.canEditArtwork,
                      child: const ListTile(
                        leading: Icon(Icons.account_circle_outlined),
                        title: Text('Change Top Artists artwork'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _ArtistMenuAction.clearTopArtists,
                      enabled: controller.canEditArtwork,
                      child: const ListTile(
                        leading: Icon(Icons.person_off_outlined),
                        title: Text('Clear Top Artists artwork'),
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

                final visibleTracks = controller.tracks
                    .where(_hasAvailableMedia)
                    .toList(growable: false);
                final visibleFeaturedTracks = controller.featuredTracks
                    .where(_hasAvailableMedia)
                    .toList(growable: false);
                final visibleAlbumIds = controller.allTracks
                    .where(_hasAvailableMedia)
                    .map((track) => track.albumId)
                    .toSet();

                final visibleAlbums = controller.albums
                    .where((album) => visibleAlbumIds.contains(album.albumId))
                    .toList(growable: false);

                return RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ListView(
                    key: const PageStorageKey<String>('artist-profile-scroll'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    children: [
                      ArtistProfileHeader(
                        artist: artist,
                        artworkPath: controller.headerArtworkPath,
                      ),
                      const SizedBox(height: 20),
                      ArtistProfilePlaybackControls(controller: controller),
                      const SizedBox(height: 28),
                      ArtistProfileSectionHeading(
                        title: 'Albums',
                        count: visibleAlbums.length,
                      ),
                      const SizedBox(height: 12),
                      ArtistProfileAlbumsGrid(
                        albums: visibleAlbums,
                        onAlbumTap: (album) {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AlbumProfilePage(
                                albumId: album.albumId,
                                initialAlbumTitle: album.title,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                      ArtistProfileSectionHeading(
                        title: 'Songs',
                        count: visibleTracks.length,
                      ),
                      const SizedBox(height: 8),
                      ArtistProfileTracksList(
                        tracks: visibleTracks,
                        isTrackPlayable: controller.isTrackPlayable,
                        canEditArtwork: controller.canEditTrackArtwork,
                        canEditTrack: controller.canEditTrack(userId),
                        canSetBlocked: controller.canSetTrackBlocked(userId),
                        onPlay: controller.playTrack,
                        onPlayNext: controller.playNext,
                        onAddToQueue: controller.addToQueue,
                        onAddToPlaylist: (track) =>
                            showAddToPlaylistFlow(context, track),
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
                      if (visibleFeaturedTracks.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        ArtistProfileSectionHeading(
                          title: 'Featured On',
                          count: visibleFeaturedTracks.length,
                        ),
                        const SizedBox(height: 8),
                        ArtistProfileTracksList(
                          tracks: visibleFeaturedTracks,
                          isTrackPlayable: controller.isTrackPlayable,
                          canEditArtwork: controller.canEditTrackArtwork,
                          canEditTrack: controller.canEditTrack(userId),
                          canSetBlocked: controller.canSetTrackBlocked(userId),
                          onPlay: controller.playTrack,
                          onPlayNext: controller.playNext,
                          onAddToQueue: controller.addToQueue,
                          onAddToPlaylist: (track) =>
                              showAddToPlaylistFlow(context, track),
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
                      ],
                    ],
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
    if (action == _ArtistMenuAction.editName) {
      await _editArtistName(controller, userId);
      return;
    }

    if (action == _ArtistMenuAction.removeArtist) {
      await _removeArtist(controller, userId);
      return;
    }

    await _handleArtworkAction(controller, action);
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

    final result = await Navigator.of(context).push<ArtistStudioMergeResult>(
      MaterialPageRoute<ArtistStudioMergeResult>(
        builder: (_) => ArtistStudioPage(
          controller: controller,
          repository: repository,
          userId: userId,
          mergeService: artistMergeService,
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
  ) async {
    try {
      final changed = switch (action) {
        _ArtistMenuAction.studio => false,
        _ArtistMenuAction.editName => false,
        _ArtistMenuAction.removeArtist => false,
        _ArtistMenuAction.changeHeader =>
          await controller.changeHeaderArtwork(),
        _ArtistMenuAction.clearHeader => await controller.clearHeaderArtwork(),
        _ArtistMenuAction.changeTopArtists =>
          await controller.changeTopArtistsArtwork(),
        _ArtistMenuAction.clearTopArtists =>
          await controller.clearTopArtistsArtwork(),
      };

      if (!mounted || !changed) {
        return;
      }

      final message = switch (action) {
        _ArtistMenuAction.studio => '',
        _ArtistMenuAction.editName => '',
        _ArtistMenuAction.removeArtist => '',
        _ArtistMenuAction.changeHeader => 'Header artwork updated.',
        _ArtistMenuAction.clearHeader => 'Header artwork cleared.',
        _ArtistMenuAction.changeTopArtists => 'Top Artists artwork updated.',
        _ArtistMenuAction.clearTopArtists => 'Top Artists artwork cleared.',
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
      final draft = await Navigator.of(context).push<TrackProfileEditDraft>(
        MaterialPageRoute<TrackProfileEditDraft>(
          builder: (routeContext) {
            return TrackStudioPage(
              track: track,
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
        albumEditionId: draft.albumEditionId,
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
  editName,
  changeHeader,
  clearHeader,
  changeTopArtists,
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
