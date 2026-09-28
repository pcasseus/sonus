import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_artist.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/presentation/pages/album_profile_page.dart';
import '../../../library/presentation/pages/artist_profile_page.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../application/repositories/library_search_repository.dart';
import '../controllers/library_search_controller.dart';
import '../../../account/application/controllers/account_controller.dart';
import '../../../library/application/services/song_block_service.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  LibrarySearchRepository? _repository;
  LibrarySearchController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final repository = context.watch<LibrarySearchRepository?>();

    if (identical(repository, _repository)) {
      return;
    }

    _repository = repository;

    final previousController = _controller;

    if (repository == null) {
      _controller = null;
    } else {
      _controller = LibrarySearchController(repository: repository);
    }

    previousController?.dispose();
  }

  void _clearSearch() {
    _textController.clear();
    _controller?.clear();
    _searchFocusNode.requestFocus();
  }

  void _openArtist(LibraryArtist artist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistProfilePage(
          artistId: artist.artistId,
          initialArtistName: artist.name,
        ),
      ),
    );
  }

  void _openAlbum(LibraryAlbum album) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumProfilePage(
          albumId: album.albumId,
          initialAlbumTitle: album.title,
        ),
      ),
    );
  }

  void _openTrackArtist(LibraryTrack track) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistProfilePage(
          artistId: track.artistId,
          initialArtistName: track.artistName,
        ),
      ),
    );
  }

  void _openTrackAlbum(LibraryTrack track) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumProfilePage(
          albumId: track.albumId,
          initialAlbumTitle: track.albumTitle,
        ),
      ),
    );
  }

  bool _isPlayable(LibraryTrack track) {
    return !track.isBlocked &&
        track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
  }

  Future<void> _setTrackBlocked(LibraryTrack track, bool isBlocked) async {
    final accountController = context.read<AccountController?>();
    final userId = accountController?.user?.id;
    final service = context.read<SongBlockService?>();
    final playbackCoordinator = context.read<PlaybackCoordinator?>();

    if (service == null) {
      return;
    }

    try {
      await service.setBlocked(
        userId: userId,
        songId: track.songId,
        isBlocked: isBlocked,
      );

      if (isBlocked && playbackCoordinator != null) {
        await playbackCoordinator.removeBlockedSongFromQueue(track.songId);
      }

      if (!mounted) {
        return;
      }

      final controller = _controller;

      if (controller != null) {
        await controller.retry();
      }

      if (!mounted) {
        return;
      }

      _showMessage(isBlocked ? 'Song blacklisted.' : 'Removed from blacklist.');
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage('Could not update blacklist.');
    }
  }

  Future<void> _playTrack(LibraryTrack track) async {
    if (!_isPlayable(track)) {
      _showMessage(
        track.isBlocked
            ? 'This song is blacklisted.'
            : 'This track is unavailable on this device.',
      );
      return;
    }

    try {
      await context.read<PlaybackCoordinator>().playTrack(track);
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Could not play this track.');
    }
  }

  Future<void> _playNext(LibraryTrack track) async {
    if (!_isPlayable(track)) {
      _showMessage(
        track.isBlocked
            ? 'This song is blacklisted.'
            : 'This track is unavailable on this device.',
      );
      return;
    }

    try {
      await context.read<PlaybackCoordinator>().playNext(track);

      if (!mounted) {
        return;
      }

      _showMessage('Added "${track.title}" to play next.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Could not add this track to play next.');
    }
  }

  Future<void> _addToQueue(LibraryTrack track) async {
    if (!_isPlayable(track)) {
      _showMessage(
        track.isBlocked
            ? 'This song is blacklisted.'
            : 'This track is unavailable on this device.',
      );
      return;
    }

    try {
      await context.read<PlaybackCoordinator>().addToQueue(track);

      if (!mounted) {
        return;
      }

      _showMessage('Added "${track.title}" to the queue.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Could not add this track to the queue.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      key: const ValueKey<String>('search-page'),
      appBar: AppBar(title: const Text('Search')),
      body: controller == null
          ? const Center(
              child: CircularProgressIndicator(
                key: ValueKey<String>('search-initializing'),
              ),
            )
          : AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TextField(
                        key: const ValueKey<String>('search-field'),
                        controller: _textController,
                        focusNode: _searchFocusNode,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: controller.updateQuery,
                        decoration: InputDecoration(
                          hintText: 'Artists, albums, tracks',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: controller.hasQuery
                              ? IconButton(
                                  key: const ValueKey<String>(
                                    'search-clear-button',
                                  ),
                                  tooltip: 'Clear search',
                                  onPressed: _clearSearch,
                                  icon: const Icon(Icons.close_rounded),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                    if (controller.isSearching)
                      const LinearProgressIndicator(
                        key: ValueKey<String>('search-progress'),
                      ),
                    Expanded(child: _buildBody(controller)),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildBody(LibrarySearchController controller) {
    if (!controller.hasQuery) {
      return const _SearchPrompt();
    }

    if (controller.hasError) {
      return _SearchError(onRetry: controller.retry);
    }

    if (controller.isSearching && !controller.hasResults) {
      return const SizedBox.shrink();
    }

    if (controller.showEmptyState) {
      return _NoSearchResults(query: controller.query.trim());
    }

    final results = controller.results;

    return ListView(
      key: const ValueKey<String>('search-results'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (results.artists.isNotEmpty) ...[
          _SectionHeader(title: 'Artists', count: results.artists.length),
          for (final artist in results.artists)
            _ArtistResultTile(artist: artist, onTap: () => _openArtist(artist)),
          const SizedBox(height: 18),
        ],
        if (results.albums.isNotEmpty) ...[
          _SectionHeader(title: 'Albums', count: results.albums.length),
          for (final album in results.albums)
            _AlbumResultTile(album: album, onTap: () => _openAlbum(album)),
          const SizedBox(height: 18),
        ],
        if (results.tracks.isNotEmpty) ...[
          _SectionHeader(title: 'Tracks', count: results.tracks.length),
          for (final track in results.tracks)
            _TrackResultTile(
              track: track,
              isPlayable: _isPlayable(track),
              canSetBlocked: context.read<SongBlockService?>() != null,
              onTap: () => _playTrack(track),
              onAction: (action) {
                switch (action) {
                  case _TrackSearchAction.playNext:
                    _playNext(track);
                  case _TrackSearchAction.addToQueue:
                    _addToQueue(track);
                  case _TrackSearchAction.goToArtist:
                    _openTrackArtist(track);
                  case _TrackSearchAction.goToAlbum:
                    _openTrackAlbum(track);
                  case _TrackSearchAction.toggleBlocked:
                    _setTrackBlocked(track, !track.isSongBlocked);
                }
              },
            ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textController.dispose();
    _searchFocusNode.dispose();

    super.dispose();
  }
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: ValueKey<String>('search-prompt'),
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music_rounded, size: 52),
            SizedBox(height: 16),
            Text(
              'Search your library',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Find artists, albums, and tracks in Sonus.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey<String>('search-error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Search failed',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Something went wrong while searching your library.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey<String>('search-retry-button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey<String>('search-empty'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 48),
            const SizedBox(height: 16),
            Text(
              'No results for "$query"',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Try another artist, album, or track name.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 6, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text('$count', style: textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _ArtistResultTile extends StatelessWidget {
  const _ArtistResultTile({required this.artist, required this.onTap});

  final LibraryArtist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final artworkPath =
        artist.topArtistsArtworkPath ?? artist.headerArtworkPath;

    return ListTile(
      key: ValueKey<String>('search-artist-${artist.artistId}'),
      onTap: onTap,
      leading: _SearchArtwork(
        path: artworkPath,
        icon: Icons.person_rounded,
        circular: true,
      ),
      title: Text(artist.name),
      subtitle: Text(
        '${artist.albumCount} ${artist.albumCount == 1 ? 'album' : 'albums'}'
        ' • '
        '${artist.songCount} ${artist.songCount == 1 ? 'track' : 'tracks'}',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _AlbumResultTile extends StatelessWidget {
  const _AlbumResultTile({required this.album, required this.onTap});

  final LibraryAlbum album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey<String>('search-album-${album.albumId}'),
      onTap: onTap,
      leading: _SearchArtwork(
        path: album.artworkPath,
        icon: Icons.album_rounded,
      ),
      title: Text(album.title),
      subtitle: Text(
        '${album.artistName} • '
        '${album.trackCount} ${album.trackCount == 1 ? 'track' : 'tracks'}',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}

class _TrackResultTile extends StatelessWidget {
  const _TrackResultTile({
    required this.track,
    required this.isPlayable,
    required this.canSetBlocked,
    required this.onTap,
    required this.onAction,
  });

  final LibraryTrack track;
  final bool isPlayable;
  final bool canSetBlocked;
  final VoidCallback onTap;
  final ValueChanged<_TrackSearchAction> onAction;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey<String>('search-track-${track.songId}'),
      onTap: isPlayable ? onTap : null,
      leading: _SearchArtwork(
        path: track.artworkPath,
        icon: Icons.music_note_rounded,
      ),
      title: Text(track.title),
      subtitle: Text(
        track.isBlocked
            ? '${track.artistName} • Blacklisted'
            : !track.isAvailable ||
                  track.filePath == null ||
                  track.filePath!.trim().isEmpty
            ? '${track.artistName} • Unavailable'
            : '${track.artistName} • ${track.albumTitle}',
      ),
      trailing: PopupMenuButton<_TrackSearchAction>(
        key: ValueKey<String>('search-track-menu-${track.songId}'),
        onSelected: onAction,
        itemBuilder: (context) {
          return [
            PopupMenuItem<_TrackSearchAction>(
              value: _TrackSearchAction.playNext,
              enabled: isPlayable,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.playlist_play_rounded),
                title: Text('Play next'),
              ),
            ),
            PopupMenuItem<_TrackSearchAction>(
              value: _TrackSearchAction.addToQueue,
              enabled: isPlayable,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.queue_music_rounded),
                title: Text('Add to queue'),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<_TrackSearchAction>(
              value: _TrackSearchAction.toggleBlocked,
              enabled: canSetBlocked,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
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
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<_TrackSearchAction>(
              value: _TrackSearchAction.goToArtist,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.person_rounded),
                title: Text('Go to artist'),
              ),
            ),
            const PopupMenuItem<_TrackSearchAction>(
              value: _TrackSearchAction.goToAlbum,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.album_rounded),
                title: Text('Go to album'),
              ),
            ),
          ];
        },
      ),
    );
  }
}

class _SearchArtwork extends StatelessWidget {
  const _SearchArtwork({
    required this.path,
    required this.icon,
    this.circular = false,
  });

  final String? path;
  final IconData icon;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    const size = 52.0;

    final resolvedPath = path?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(circular ? size / 2 : 10),
      child: SizedBox(
        width: size,
        height: size,
        child: resolvedPath == null || resolvedPath.isEmpty
            ? _ArtworkFallback(icon: icon)
            : _ArtworkImage(path: resolvedPath, fallbackIcon: icon),
      ),
    );
  }
}

class _ArtworkImage extends StatelessWidget {
  const _ArtworkImage({required this.path, required this.fallbackIcon});

  final String path;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final file = File(path);

    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 160,
        cacheHeight: 160,
        errorBuilder: (context, error, stackTrace) {
          return _ArtworkFallback(icon: fallbackIcon);
        },
      );
    }

    return Image.asset(
      path,
      fit: BoxFit.cover,
      cacheWidth: 160,
      cacheHeight: 160,
      errorBuilder: (context, error, stackTrace) {
        return _ArtworkFallback(icon: fallbackIcon);
      },
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(icon)),
    );
  }
}

enum _TrackSearchAction {
  playNext,
  addToQueue,
  goToArtist,
  goToAlbum,
  toggleBlocked,
}
