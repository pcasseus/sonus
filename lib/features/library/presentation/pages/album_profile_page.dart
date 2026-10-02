import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../account/application/controllers/account_controller.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_album_edition.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/album_profile_editing_service.dart';
import '../../application/services/album_edition_track_ordering_service.dart';
import '../../application/services/song_block_service.dart';
import '../../domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import '../controllers/album_profile_controller.dart';
import '../widgets/album_profile_edit_dialog.dart';
import '../widgets/track_profile_edit_dialog.dart';

class AlbumProfilePage extends StatefulWidget {
  const AlbumProfilePage({
    super.key,
    required this.albumId,
    this.initialAlbumTitle,
  });

  final String albumId;
  final String? initialAlbumTitle;

  @override
  State<AlbumProfilePage> createState() => _AlbumProfilePageState();
}

class _AlbumProfilePageState extends State<AlbumProfilePage> {
  AlbumProfileController? _controller;
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
    _controller = AlbumProfileController(
      repository: repository,
      albumId: widget.albumId,
      playbackCoordinator: context.read<PlaybackCoordinator?>(),
      albumProfileEditingService: context.read<AlbumProfileEditingService?>(),
      albumEditionTrackOrderingService: context
          .read<AlbumEditionTrackOrderingService?>(),
      trackProfileEditingService: context.read<TrackProfileEditingService?>(),
      songBlockService: context.read<SongBlockService?>(),
      artworkAssignmentService: context.read<ArtworkAssignmentService?>(),
      artworkFilePicker: context.read<ArtworkFilePicker?>(),
    );

    unawaited(_controller!.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final accountController = context.watch<AccountController?>();
    final userId = accountController?.user?.id;

    return Scaffold(
      key: const ValueKey<String>('album-profile-page'),
      appBar: AppBar(
        title: controller == null
            ? Text(widget.initialAlbumTitle ?? 'Album')
            : AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final album = controller.album;

                  return Text(
                    album == null
                        ? widget.initialAlbumTitle ?? 'Album'
                        : _presentationAlbumTitle(
                            album,
                            controller.selectedEdition,
                          ),
                  );
                },
              ),
        actions: [
          if (controller != null)
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                return PopupMenuButton<_AlbumMenuAction>(
                  key: const ValueKey<String>('album-profile-artwork-menu'),
                  enabled:
                      controller.canEditArtwork ||
                      controller.canEditAlbumProfile(userId),
                  tooltip: 'Album actions',
                  onSelected: (action) {
                    unawaited(_handleAlbumAction(controller, action, userId));
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _AlbumMenuAction.editProfile,
                      enabled: controller.canEditAlbumProfile(userId),
                      child: const ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit album details'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: _AlbumMenuAction.changeArtwork,
                      enabled: controller.canEditArtwork,
                      child: const ListTile(
                        leading: Icon(Icons.image_rounded),
                        title: Text('Change artwork'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _AlbumMenuAction.clearArtwork,
                      enabled: controller.canEditArtwork,
                      child: const ListTile(
                        leading: Icon(Icons.hide_image_rounded),
                        title: Text('Clear artwork'),
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
          ? const Center(child: Text('Loading album...'))
          : AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.isLoading && controller.album == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (controller.hasError && controller.album == null) {
                  return _AlbumProfileLoadError(onRetry: controller.load);
                }

                if (controller.isNotFound) {
                  return const _AlbumNotFound();
                }

                final album = controller.album;

                if (album == null) {
                  return const SizedBox.shrink();
                }

                return RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ListView(
                    key: const PageStorageKey<String>('album-profile-scroll'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    children: [
                      _AlbumHeader(
                        album: album,
                        controller: controller,
                        artworkPath: _presentationArtworkPath(controller),
                      ),
                      const SizedBox(height: 20),
                      if (controller.editions.length > 1) ...[
                        _EditionSelector(controller: controller),
                        const SizedBox(height: 20),
                      ],
                      _PlaybackControls(controller: controller),
                      const SizedBox(height: 28),
                      _SectionHeading(
                        title: 'Tracks',
                        count: controller.tracks
                            .where(_hasAvailableMedia)
                            .length,
                      ),
                      const SizedBox(height: 8),
                      _TracksList(
                        controller: controller,
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
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _handleAlbumAction(
    AlbumProfileController controller,
    _AlbumMenuAction action,
    String? userId,
  ) async {
    if (action == _AlbumMenuAction.editProfile) {
      await _editAlbumProfile(controller, userId);
      return;
    }

    await _handleArtworkAction(controller, action);
  }

  Future<void> _editAlbumProfile(
    AlbumProfileController controller,
    String? userId,
  ) async {
    final album = controller.album;
    final repository = _repository;

    if (album == null ||
        repository == null ||
        !controller.canEditAlbumProfile(userId)) {
      return;
    }

    try {
      final artists = await repository.getArtists();

      if (!mounted) {
        return;
      }

      final draft = await showDialog<AlbumProfileEditDraft>(
        context: context,
        builder: (dialogContext) {
          return AlbumProfileEditDialog(album: album, artists: artists);
        },
      );

      if (!mounted || draft == null) {
        return;
      }

      final changed = await controller.updateProfile(
        userId: userId,
        title: draft.title,
        editionTitle: draft.editionTitle,
        editionType: draft.editionType,
        releaseDate: draft.releaseDate,
        genre: draft.genre,
        artistId: draft.artistId,
      );

      if (!mounted || !changed) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Album details updated.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update album details.')),
      );
    }
  }

  Future<void> _handleArtworkAction(
    AlbumProfileController controller,
    _AlbumMenuAction action,
  ) async {
    try {
      final changed = switch (action) {
        _AlbumMenuAction.editProfile => false,
        _AlbumMenuAction.changeArtwork => await controller.changeArtwork(),
        _AlbumMenuAction.clearArtwork => await controller.clearArtwork(),
      };

      if (!mounted || !changed) {
        return;
      }

      final message = switch (action) {
        _AlbumMenuAction.editProfile => '',
        _AlbumMenuAction.changeArtwork => 'Album artwork updated.',
        _AlbumMenuAction.clearArtwork => 'Album artwork cleared.',
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

      final artists = await repository.getArtists();
      final albums = await repository.getAlbums();

      if (!mounted) {
        return;
      }

      final draft = await showDialog<TrackProfileEditDraft>(
        context: context,
        builder: (dialogContext) {
          return TrackProfileEditDialog(
            track: track,
            artists: artists,
            albums: albums,
          );
        },
      );

      if (!mounted || draft == null) {
        return;
      }

      final changed = await controller.updateTrack(
        userId: userId,
        track: track,
        title: draft.title,
        trackNumber: draft.trackNumber,
        discNumber: draft.discNumber,
        featuredArtists: draft.featuredArtists,
        isSingle: draft.isSingle,
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
    _controller?.dispose();
    super.dispose();
  }
}

bool _hasAvailableMedia(LibraryTrack track) {
  return track.isAvailable &&
      track.filePath != null &&
      track.filePath!.trim().isNotEmpty;
}

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.album,
    required this.controller,
    required this.artworkPath,
  });

  final LibraryAlbum album;
  final AlbumProfileController controller;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadata = _metadata(album);

    return Column(
      children: [
        _AlbumArtwork(album: album, artworkPath: artworkPath),
        const SizedBox(height: 18),
        Text(
          _presentationAlbumTitle(album, controller.selectedEdition),
          key: ValueKey<String>('album-profile-title-${album.albumId}'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          album.artistName,
          key: ValueKey<String>('album-profile-artist-${album.artistId}'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        if (controller.selectedEdition != null) ...[
          const SizedBox(height: 6),
          Text(
            _editionDisplayLabel(controller.selectedEdition!),
            key: const ValueKey<String>('album-profile-selected-edition-label'),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],

        const SizedBox(height: 10),
        Text(
          _summary(),
          key: const ValueKey<String>('album-profile-summary'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            metadata,
            key: const ValueKey<String>('album-profile-metadata'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
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

    return '$trackCount $trackLabel \u2022 $runtime';
  }

  String _metadata(LibraryAlbum album) {
    final parts = <String>[];
    final selectedEdition = controller.selectedEdition;

    final releaseDate = selectedEdition?.releaseDate ?? album.releaseDate;

    if (releaseDate != null) {
      parts.add(_formatDate(releaseDate));
    }

    final genre = (selectedEdition?.genre ?? album.genre)?.trim();

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

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year}';
  }
}

class _AlbumArtwork extends StatelessWidget {
  const _AlbumArtwork({required this.album, required this.artworkPath});

  final LibraryAlbum album;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = artworkPath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        key: ValueKey<String>('album-profile-artwork-${album.albumId}'),
        width: 156,
        height: 156,
        child: path == null
            ? _fallback(theme)
            : Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _fallback(theme);
                },
              ),
      ),
    );
  }

  Widget _fallback(ThemeData theme) {
    return ColoredBox(
      key: const ValueKey<String>('album-profile-artwork-fallback'),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.album_rounded,
          size: 82,
          color: theme.colorScheme.primary,
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

    return SingleChildScrollView(
      key: const ValueKey<String>('album-profile-edition-selector'),
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<String>(
        key: const ValueKey<String>('album-profile-edition-segmented-button'),
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
    return album.title;
  }

  final editionTitle = edition.title.trim();

  if (editionTitle.isEmpty || _isGenericEditionTitle(editionTitle)) {
    return album.title;
  }

  return editionTitle;
}

String _editionDisplayLabel(LibraryAlbumEdition edition) {
  final title = edition.title.trim();

  if (title.isNotEmpty && _isGenericEditionTitle(title)) {
    return title;
  }

  return switch (edition.type) {
    AlbumEditionType.standard => 'Standard',
    AlbumEditionType.deluxe => 'Deluxe',
    AlbumEditionType.expanded => 'Expanded',
    AlbumEditionType.anniversary => 'Anniversary',
    AlbumEditionType.remaster => 'Remaster',
    AlbumEditionType.other => title.isEmpty ? 'Other' : title,
  };
}

bool _isGenericEditionTitle(String title) {
  return switch (title.trim().toLowerCase()) {
    'standard' ||
    'deluxe' ||
    'expanded' ||
    'anniversary' ||
    'remaster' ||
    'other' => true,
    _ => false,
  };
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.controller});

  final AlbumProfileController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          key: const ValueKey<String>('album-profile-shuffle-button'),
          tooltip: controller.isShuffleEnabled ? 'Shuffle on' : 'Shuffle off',
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
        FilledButton.icon(
          key: const ValueKey<String>('album-profile-play-all-button'),
          onPressed: controller.hasPlayableTracks
              ? () {
                  unawaited(controller.playAll());
                }
              : null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Play'),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Text('$count', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _TracksList extends StatelessWidget {
  const _TracksList({
    required this.controller,
    required this.canEditTrack,
    required this.canSetBlocked,
    required this.onEditTrack,
    required this.onChangeArtwork,
    required this.onClearArtwork,
    required this.onSetBlocked,
  });

  final AlbumProfileController controller;
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

    return Column(
      key: const ValueKey<String>('album-profile-tracks-list'),
      children: [
        for (final track in tracks)
          _TrackTile(
            track: track,
            isPlayable: controller.isTrackPlayable(track),
            canEditArtwork: controller.canEditTrackArtwork,
            canEditTrack: canEditTrack,
            canSetBlocked: canSetBlocked,
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
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.isPlayable,
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
    return ListTile(
      key: ValueKey<String>('album-track-${track.songId}'),
      contentPadding: EdgeInsets.zero,
      enabled: isPlayable,
      leading: SizedBox(
        width: 32,
        child: Center(child: Text('${track.trackNumber}')),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: _subtitle(track),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatDuration(track.durationSeconds),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          PopupMenuButton<_TrackMenuAction>(
            key: ValueKey<String>('album-track-menu-${track.songId}'),
            enabled:
                isPlayable || canEditArtwork || canEditTrack || canSetBlocked,
            onSelected: (action) {
              switch (action) {
                case _TrackMenuAction.playNext:
                  unawaited(onPlayNext());
                case _TrackMenuAction.addToQueue:
                  unawaited(onAddToQueue());
                case _TrackMenuAction.addToPlaylist:
                  unawaited(onAddToPlaylist());
                case _TrackMenuAction.editDetails:
                  unawaited(onEditTrack());
                case _TrackMenuAction.changeArtwork:
                  unawaited(onChangeArtwork());
                case _TrackMenuAction.clearArtwork:
                  unawaited(onClearArtwork());
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
              PopupMenuItem(
                value: _TrackMenuAction.editDetails,
                enabled: canEditTrack,
                child: const ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit song details'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _TrackMenuAction.changeArtwork,
                enabled: canEditArtwork,
                child: const ListTile(
                  leading: Icon(Icons.image_rounded),
                  title: Text('Change artwork'),
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
              PopupMenuItem(
                value: _TrackMenuAction.clearArtwork,
                enabled: canEditArtwork,
                child: const ListTile(
                  leading: Icon(Icons.hide_image_rounded),
                  title: Text('Clear artwork'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: isPlayable
          ? () {
              unawaited(onPlay());
            }
          : null,
    );
  }

  Widget? _subtitle(LibraryTrack track) {
    final parts = <String>[];

    if (track.isBlocked) {
      parts.add('Blacklisted');
    } else if (!track.isAvailable ||
        track.filePath == null ||
        track.filePath!.trim().isEmpty) {
      parts.add('Unavailable');
    }

    if (track.featuredArtists.isNotEmpty) {
      parts.add('feat. ${track.featuredArtists.join(', ')}');
    }

    final editionTitle = track.albumEditionTitle.trim();

    if (editionTitle.isNotEmpty && editionTitle.toLowerCase() != 'standard') {
      parts.add(editionTitle);
    }

    if (parts.isEmpty) {
      return null;
    }

    return Text(
      parts.join(' \u2022 '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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

enum _AlbumMenuAction { editProfile, changeArtwork, clearArtwork }

enum _TrackMenuAction {
  playNext,
  addToQueue,
  addToPlaylist,
  editDetails,
  changeArtwork,
  clearArtwork,
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
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
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
            const Icon(Icons.error_outline_rounded, size: 48),
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.album_outlined, size: 48),
            SizedBox(height: 16),
            Text('Album not found', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
