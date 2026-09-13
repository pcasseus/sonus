import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../account/application/controllers/account_controller.dart';
import '../../../artwork/application/services/artwork_assignment_service.dart';
import '../../../artwork/application/services/artwork_file_picker.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/models/library_album.dart';
import '../../application/models/library_artist.dart';
import '../../application/models/library_track.dart';
import '../../application/repositories/library_query_repository.dart';
import '../../application/services/artist_profile_editing_service.dart';
import '../controllers/artist_profile_controller.dart';
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
                      _ArtistHeader(
                        artist: artist,
                        artworkPath: controller.headerArtworkPath,
                      ),
                      const SizedBox(height: 20),
                      _PlaybackControls(controller: controller),
                      const SizedBox(height: 28),
                      _SectionHeading(
                        title: 'Albums',
                        count: controller.albums.length,
                      ),
                      const SizedBox(height: 12),
                      _AlbumsGrid(albums: controller.albums),
                      const SizedBox(height: 28),
                      _SectionHeading(
                        title: 'Songs',
                        count: controller.tracks.length,
                      ),
                      const SizedBox(height: 8),
                      _TracksList(
                        controller: controller,
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

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({required this.artist, required this.artworkPath});

  final LibraryArtist artist;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ArtistArtwork(artist: artist, artworkPath: artworkPath),
        const SizedBox(height: 16),
        Text(
          artist.name,
          key: ValueKey<String>('artist-profile-name-${artist.artistId}'),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          _summary(artist),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  String _summary(LibraryArtist artist) {
    final albumLabel = artist.albumCount == 1 ? 'album' : 'albums';
    final songLabel = artist.songCount == 1 ? 'song' : 'songs';

    return '${artist.albumCount} $albumLabel • '
        '${artist.songCount} $songLabel';
  }
}

class _ArtistArtwork extends StatelessWidget {
  const _ArtistArtwork({required this.artist, required this.artworkPath});

  final LibraryArtist artist;
  final String? artworkPath;

  @override
  Widget build(BuildContext context) {
    final path = artworkPath;

    if (path == null) {
      return _ArtistArtworkFallback(artistName: artist.name);
    }

    return ClipOval(
      child: SizedBox(
        key: ValueKey<String>('artist-profile-artwork-${artist.artistId}'),
        width: 104,
        height: 104,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _ArtistArtworkFallback(artistName: artist.name);
          },
        ),
      ),
    );
  }
}

class _ArtistArtworkFallback extends StatelessWidget {
  const _ArtistArtworkFallback({required this.artistName});

  final String artistName;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      key: const ValueKey<String>('artist-profile-artwork-fallback'),
      radius: 52,
      child: Text(
        _initials(artistName),
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return '?';
    }

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}'
            '${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({required this.controller});

  final ArtistProfileController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          key: const ValueKey<String>('artist-profile-shuffle-button'),
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
          key: const ValueKey<String>('artist-profile-play-all-button'),
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

class _AlbumsGrid extends StatelessWidget {
  const _AlbumsGrid({required this.albums});

  final List<LibraryAlbum> albums;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return const _EmptySection(message: 'No albums yet');
    }

    return GridView.builder(
      key: const ValueKey<String>('artist-profile-albums-grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];

        return Card(
          key: ValueKey<String>('artist-album-${album.albumId}'),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AlbumProfilePage(
                    albumId: album.albumId,
                    initialAlbumTitle: album.title,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(child: _AlbumArtworkThumbnail(album: album)),
                  ),
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _albumSummary(album),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _albumSummary(LibraryAlbum album) {
    final trackLabel = album.trackCount == 1 ? 'track' : 'tracks';

    return '${album.trackCount} $trackLabel';
  }
}

class _AlbumArtworkThumbnail extends StatelessWidget {
  const _AlbumArtworkThumbnail({required this.album});

  final LibraryAlbum album;

  @override
  Widget build(BuildContext context) {
    final path = album.artworkPath?.trim();

    if (path == null || path.isEmpty) {
      return _fallback(context);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        key: ValueKey<String>('artist-album-artwork-${album.albumId}'),
        width: 84,
        height: 84,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _fallback(context);
          },
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    return Icon(
      Icons.album_rounded,
      size: 52,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}

class _TracksList extends StatelessWidget {
  const _TracksList({
    required this.controller,
    required this.onChangeArtwork,
    required this.onClearArtwork,
  });

  final ArtistProfileController controller;
  final Future<void> Function(LibraryTrack track) onChangeArtwork;
  final Future<void> Function(LibraryTrack track) onClearArtwork;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.tracks;

    if (tracks.isEmpty) {
      return const _EmptySection(message: 'No songs yet');
    }

    return Column(
      key: const ValueKey<String>('artist-profile-tracks-list'),
      children: [
        for (final track in tracks)
          _TrackTile(
            track: track,
            isPlayable: controller.isTrackPlayable(track),
            canEditArtwork: controller.canEditTrackArtwork,
            onPlay: () => controller.playTrack(track),
            onPlayNext: () => controller.playNext(track),
            onAddToQueue: () => controller.addToQueue(track),
            onChangeArtwork: () => onChangeArtwork(track),
            onClearArtwork: () => onClearArtwork(track),
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
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onChangeArtwork,
    required this.onClearArtwork,
  });

  final LibraryTrack track;
  final bool isPlayable;
  final bool canEditArtwork;

  final Future<void> Function() onPlay;
  final Future<void> Function() onPlayNext;
  final Future<void> Function() onAddToQueue;
  final Future<void> Function() onChangeArtwork;
  final Future<void> Function() onClearArtwork;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey<String>('artist-track-${track.songId}'),
      contentPadding: EdgeInsets.zero,
      enabled: isPlayable,
      leading: SizedBox(
        width: 32,
        child: Center(child: Text('${track.trackNumber}')),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: track.albumTitle.trim().isEmpty
          ? null
          : Text(
              track.albumTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatDuration(track.durationSeconds),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          PopupMenuButton<_TrackMenuAction>(
            key: ValueKey<String>('artist-track-menu-${track.songId}'),
            enabled: isPlayable || canEditArtwork,
            onSelected: (action) {
              switch (action) {
                case _TrackMenuAction.playNext:
                  unawaited(onPlayNext());
                case _TrackMenuAction.addToQueue:
                  unawaited(onAddToQueue());
                case _TrackMenuAction.changeArtwork:
                  unawaited(onChangeArtwork());
                case _TrackMenuAction.clearArtwork:
                  unawaited(onClearArtwork());
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
                value: _TrackMenuAction.changeArtwork,
                enabled: canEditArtwork,
                child: const ListTile(
                  leading: Icon(Icons.image_rounded),
                  title: Text('Change artwork'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
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

  String _formatDuration(int seconds) {
    final safeSeconds = seconds < 0 ? 0 : seconds;
    final minutes = safeSeconds ~/ 60;
    final remainder = safeSeconds % 60;

    return '$minutes:'
        '${remainder.toString().padLeft(2, '0')}';
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

enum _TrackMenuAction { playNext, addToQueue, changeArtwork, clearArtwork }

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
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
