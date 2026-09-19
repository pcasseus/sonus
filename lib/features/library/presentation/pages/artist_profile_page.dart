import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../account/application/controllers/account_controller.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/artist_profile_editing_service.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import '../controllers/artist_profile_controller.dart';
import '../widgets/artist_profile/artist_profile_albums_grid.dart';
import '../widgets/artist_profile/artist_profile_header.dart';
import '../widgets/artist_profile/artist_profile_tracks_list.dart';
import '../widgets/artist_profile/artist_profile_playback_controls.dart';
import '../widgets/artist_profile/artist_profile_section_heading.dart';
import '../widgets/track_profile_edit_dialog.dart';
import 'album_profile_page.dart';

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
      trackProfileEditingService: context.read<TrackProfileEditingService?>(),
      artworkAssignmentService: context.read<ArtworkAssignmentService?>(),
      artworkFilePicker: context.read<ArtworkFilePicker?>(),
      artistProfileEditingService: context.read<ArtistProfileEditingService?>(),
    );

    unawaited(_controller!.load());
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final accountController = context.watch<AccountController?>();
    final userId = accountController?.user?.id;

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
                      controller.canEditArtist(userId),
                  tooltip: 'Artist actions',
                  onSelected: (action) {
                    unawaited(_handleArtistAction(controller, action, userId));
                  },
                  itemBuilder: (context) => [
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
                        count: controller.albums.length,
                      ),
                      const SizedBox(height: 12),
                      ArtistProfileAlbumsGrid(
                        albums: controller.albums,
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
                        count: controller.tracks.length,
                      ),
                      const SizedBox(height: 8),
                      ArtistProfileTracksList(
                        tracks: controller.tracks,
                        isTrackPlayable: controller.isTrackPlayable,
                        canEditArtwork: controller.canEditTrackArtwork,
                        canEditTrack: controller.canEditTrack(userId),
                        onPlay: controller.playTrack,
                        onPlayNext: controller.playNext,
                        onAddToQueue: controller.addToQueue,
                        onEditTrack: (track) =>
                            _editTrack(controller, track, userId),
                        onChangeArtwork: (track) =>
                            _changeTrackArtwork(controller, track),
                        onClearArtwork: (track) =>
                            _clearTrackArtwork(controller, track),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _handleArtistAction(
    ArtistProfileController controller,
    _ArtistMenuAction action,
    String? userId,
  ) async {
    if (action == _ArtistMenuAction.editName) {
      if (userId == null || userId.trim().isEmpty) {
        return;
      }

      await _editArtistName(controller, userId);
      return;
    }

    await _handleArtworkAction(controller, action);
  }

  Future<void> _editArtistName(
    ArtistProfileController controller,
    String userId,
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
        _ArtistMenuAction.editName => false,
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
        _ArtistMenuAction.editName => '',
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

  Future<void> _editTrack(
    ArtistProfileController controller,
    LibraryTrack track,
    String? userId,
  ) async {
    if (userId == null || userId.trim().isEmpty) {
      return;
    }

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
  editName,
  changeHeader,
  clearHeader,
  changeTopArtists,
  clearTopArtists,
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
