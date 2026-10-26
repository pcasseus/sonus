import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/design/sonus_theme.dart';
import '../../../../core/design/widgets/sonus_artwork_image.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../../core/design/widgets/sonus_track_tile.dart';

import '../../../library/application/models/library_album.dart';
import '../../../library/application/models/library_artist.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/application/repositories/library_query_repository.dart';
import '../../../library/application/services/library_organization_service.dart';
import '../../../library/presentation/pages/album_profile_page.dart';
import '../../../library/presentation/pages/artist_profile_page.dart';
import '../../../player/application/controllers/playback_coordinator.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
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

  LibraryQueryRepository? _libraryQueryRepository;
  List<LibraryAlbum> _availabilityAlbums = const [];
  List<LibraryTrack> _availabilityTracks = const [];
  bool _hasAvailabilityCatalog = false;

  /// The Library's artist identity; null shows every artist (fails open).
  ArtistLibraryOrganization? _organization;
  int _availabilityGeneration = 0;
  _SearchFilter _filter = _SearchFilter.all;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final repository = context.watch<LibrarySearchRepository?>();
    final libraryQueryRepository = context.watch<LibraryQueryRepository?>();

    if (!identical(libraryQueryRepository, _libraryQueryRepository)) {
      _libraryQueryRepository = libraryQueryRepository;
      _availabilityGeneration++;

      _availabilityAlbums = const [];
      _availabilityTracks = const [];
      _hasAvailabilityCatalog = false;

      if (libraryQueryRepository != null) {
        unawaited(
          _loadAvailabilityCatalog(
            libraryQueryRepository,
            _availabilityGeneration,
          ),
        );
      }
    }

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

  Future<void> _loadAvailabilityCatalog(
    LibraryQueryRepository repository,
    int generation,
  ) async {
    try {
      final results = await Future.wait<Object>([
        repository.getAlbums(),
        repository.getTracks(),
      ]);
      final organization = await _loadOrganization();

      if (!mounted || generation != _availabilityGeneration) {
        return;
      }

      setState(() {
        _availabilityAlbums = results[0] as List<LibraryAlbum>;
        _availabilityTracks = results[1] as List<LibraryTrack>;
        _organization = organization;
        _hasAvailabilityCatalog = true;
      });
    } catch (_) {
      if (!mounted || generation != _availabilityGeneration) {
        return;
      }

      setState(() {
        _availabilityAlbums = const [];
        _availabilityTracks = const [];
        _hasAvailabilityCatalog = false;
      });
    }
  }

  Future<ArtistLibraryOrganization?> _loadOrganization() async {
    LibraryOrganizationService? service;
    try {
      service = context.read<LibraryOrganizationService?>();
    } on ProviderNotFoundException {
      return null;
    }
    try {
      return await service?.load();
    } catch (_) {
      return null;
    }
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
          initialEditionId: track.albumEditionId,
        ),
      ),
    );
  }

  bool _hasAvailableMedia(LibraryTrack track) {
    return track.isAvailable &&
        track.filePath != null &&
        track.filePath!.trim().isNotEmpty;
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

  /// Plays [track] with the visible track results as the queue.
  Future<void> _playTrack(
    LibraryTrack track,
    List<LibraryTrack> results,
  ) async {
    if (!_isPlayable(track)) {
      _showMessage(
        track.isBlocked
            ? 'This song is blacklisted.'
            : 'This track is unavailable on this device.',
      );
      return;
    }

    try {
      await context.read<PlaybackCoordinator>().playInContext(track, results);
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
    final tokens = SonusTheme.of(context);

    return Scaffold(
      key: const ValueKey<String>('search-page'),
      backgroundColor: tokens.colors.background,
      appBar: AppBar(
        title: const Text('Search'),
        backgroundColor: tokens.colors.background,
        surfaceTintColor: Colors.transparent,
      ),
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
                    _SearchField(
                      textController: _textController,
                      focusNode: _searchFocusNode,
                      hasQuery: controller.hasQuery,
                      onChanged: controller.updateQuery,
                      onClear: _clearSearch,
                    ),
                    SizedBox(
                      height: 3,
                      child: controller.isSearching
                          ? const LinearProgressIndicator(
                              key: ValueKey<String>('search-progress'),
                            )
                          : null,
                    ),
                    Expanded(child: _buildBody(controller)),
                  ],
                );
              },
            ),
    );
  }

  List<LibraryAlbum> _visibleAlbums(List<LibraryAlbum> albums) {
    final availableAlbumIds = _availabilityTracks
        .where(_hasAvailableMedia)
        .map((track) => track.albumId)
        .toSet();

    return albums
        .where((album) => availableAlbumIds.contains(album.albumId))
        .toList(growable: false);
  }

  List<LibraryArtist> _visibleArtists(List<LibraryArtist> artists) {
    final availableTracks = _availabilityTracks
        .where(_hasAvailableMedia)
        .toList(growable: false);

    final visibleArtistIds = availableTracks
        .map((track) => track.artistId)
        .toSet();

    final availableAlbumIds = availableTracks
        .map((track) => track.albumId)
        .toSet();

    for (final album in _availabilityAlbums) {
      if (availableAlbumIds.contains(album.albumId)) {
        visibleArtistIds.add(album.artistId);
      }
    }

    // Contributors without a release of their own are found through their
    // songs and projects, not as artists.
    final organization = _organization;
    return artists
        .where(
          (artist) =>
              visibleArtistIds.contains(artist.artistId) &&
              (organization?.isShownInLibrary(artist.artistId) ?? true),
        )
        .toList(growable: false);
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

    final results = controller.results;

    final visibleTracks = results.tracks
        .where(_hasAvailableMedia)
        .toList(growable: false);

    final visibleArtists = _hasAvailabilityCatalog
        ? _visibleArtists(results.artists)
        : results.artists;

    final visibleAlbums = _hasAvailabilityCatalog
        ? _visibleAlbums(results.albums)
        : results.albums;

    if (!controller.isSearching &&
        visibleArtists.isEmpty &&
        visibleAlbums.isEmpty &&
        visibleTracks.isEmpty) {
      return _NoSearchResults(query: controller.query.trim());
    }

    final filter = _filter;
    bool shows(_SearchFilter kind) =>
        filter == _SearchFilter.all || filter == kind;
    final canSetBlocked = context.read<SongBlockService?>() != null;
    final gutter = SonusTheme.of(context).metrics.pageGutter;

    // Built lazily: large result sets only build the rows on screen.
    final items = <WidgetBuilder>[
      (context) => _SearchFilters(
        selected: filter,
        counts: {
          _SearchFilter.artists: visibleArtists.length,
          _SearchFilter.albums: visibleAlbums.length,
          _SearchFilter.tracks: visibleTracks.length,
        },
        onSelected: (value) => setState(() => _filter = value),
      ),
      if (shows(_SearchFilter.artists) && visibleArtists.isNotEmpty) ...[
        (context) =>
            _SectionHeader(title: 'Artists', count: visibleArtists.length),
        for (final artist in visibleArtists)
          (context) => _ArtistResultTile(
            artist: artist,
            onTap: () => _openArtist(artist),
          ),
      ],
      if (shows(_SearchFilter.albums) && visibleAlbums.isNotEmpty) ...[
        (context) =>
            _SectionHeader(title: 'Albums', count: visibleAlbums.length),
        for (final album in visibleAlbums)
          (context) =>
              _AlbumResultTile(album: album, onTap: () => _openAlbum(album)),
      ],
      if (shows(_SearchFilter.tracks) && visibleTracks.isNotEmpty) ...[
        (context) =>
            _SectionHeader(title: 'Tracks', count: visibleTracks.length),
        for (final track in visibleTracks)
          (context) => _TrackResultTile(
            track: track,
            isPlayable: _isPlayable(track),
            canSetBlocked: canSetBlocked,
            onTap: () => _playTrack(track, visibleTracks),
            onAction: (action) {
              switch (action) {
                case _TrackSearchAction.playNext:
                  _playNext(track);
                case _TrackSearchAction.addToQueue:
                  _addToQueue(track);
                case _TrackSearchAction.addToPlaylist:
                  showAddToPlaylistFlow(context, track);
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
    ];

    return ListView.builder(
      key: const ValueKey<String>('search-results'),
      // Dragging the results hides the keyboard, so they are not covered.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        gutter - 4,
        4,
        gutter - 4,
        32 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => items[index](context),
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

/// Which kind of result is shown; a view filter only, the search itself is
/// unchanged.
enum _SearchFilter { all, artists, albums, tracks }

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.textController,
    required this.focusNode,
    required this.hasQuery,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController textController;
  final FocusNode focusNode;
  final bool hasQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final radius = BorderRadius.circular(tokens.metrics.controlRadius);
    final gutter = tokens.metrics.pageGutter;

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 10),
      // Escape clears the query, like the clear button.
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (hasQuery) onClear();
          },
        },
        child: TextField(
          key: const ValueKey<String>('search-field'),
          controller: textController,
          focusNode: focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          onSubmitted: (_) => focusNode.unfocus(),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Artists, albums, tracks',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: hasQuery
                ? IconButton(
                    key: const ValueKey<String>('search-clear-button'),
                    tooltip: 'Clear search',
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                  )
                : null,
            filled: true,
            fillColor: colors.raisedSurface,
            border: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: colors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: colors.focus, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchFilters extends StatelessWidget {
  const _SearchFilters({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final _SearchFilter selected;
  final Map<_SearchFilter, int> counts;
  final ValueChanged<_SearchFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (sum, count) => sum + count);

    String label(_SearchFilter filter) => switch (filter) {
      _SearchFilter.all => 'All $total',
      _SearchFilter.artists => 'Artists ${counts[filter]}',
      _SearchFilter.albums => 'Albums ${counts[filter]}',
      _SearchFilter.tracks => 'Tracks ${counts[filter]}',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final filter in _SearchFilter.values)
            if (filter == _SearchFilter.all || (counts[filter] ?? 0) > 0)
              ChoiceChip(
                key: ValueKey<String>('search-filter-${filter.name}'),
                label: Text(label(filter)),
                selected: selected == filter,
                onSelected: (_) => onSelected(filter),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
        ],
      ),
    );
  }
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt();

  @override
  Widget build(BuildContext context) {
    return const SonusStateView(
      key: ValueKey<String>('search-prompt'),
      icon: Icons.manage_search_rounded,
      title: 'Search your library',
      message: 'Find artists, albums, and tracks in Sonus.',
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return SonusStateView(
      key: const ValueKey<String>('search-error'),
      icon: Icons.error_outline_rounded,
      isError: true,
      title: 'Search failed',
      message: 'Something went wrong while searching your library.',
      action: FilledButton.icon(
        key: const ValueKey<String>('search-retry-button'),
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry'),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return SonusStateView(
      key: const ValueKey<String>('search-empty'),
      icon: Icons.search_off_rounded,
      title: 'No results for "$query"',
      message: 'Try another artist, album, or track name.',
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: tokens.colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.labelLarge?.copyWith(
              color: tokens.colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.rowKey,
    required this.artwork,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key rowKey;
  final Widget artwork;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = SonusTheme.of(context);
    final colors = tokens.colors;
    final theme = Theme.of(context);
    final largeText =
        MediaQuery.textScalerOf(context).scale(1) > sonusLargeTextScale;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.metrics.cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: rowKey,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              child: Row(
                children: [
                  artwork,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: largeText ? 3 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: largeText ? 3 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
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

    return _ResultRow(
      rowKey: ValueKey<String>('search-artist-${artist.artistId}'),
      onTap: onTap,
      artwork: SonusArtworkImage(
        path: artworkPath,
        size: 52,
        circular: true,
        placeholderIcon: Icons.person_rounded,
      ),
      title: artist.name,
      subtitle:
          '${artist.albumCount} ${artist.albumCount == 1 ? 'album' : 'albums'}'
          ' • '
          '${artist.songCount} ${artist.songCount == 1 ? 'track' : 'tracks'}',
    );
  }
}

class _AlbumResultTile extends StatelessWidget {
  const _AlbumResultTile({required this.album, required this.onTap});

  final LibraryAlbum album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ResultRow(
      rowKey: ValueKey<String>('search-album-${album.albumId}'),
      onTap: onTap,
      artwork: SonusArtworkImage(
        path: album.artworkPath,
        size: 52,
        placeholderIcon: Icons.album_rounded,
      ),
      title: album.title,
      subtitle:
          '${album.artistName} • '
          '${album.trackCount} ${album.trackCount == 1 ? 'track' : 'tracks'}',
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
    return SonusTrackTile(
      inkKey: ValueKey<String>('search-track-${track.songId}'),
      onTap: onTap,
      enabled: isPlayable,
      artworkPath: track.artworkPath,
      title: track.title,
      subtitle: track.isBlocked
          ? '${track.artistName} • Blacklisted'
          : !track.isAvailable ||
                track.filePath == null ||
                track.filePath!.trim().isEmpty
          ? '${track.artistName} • Unavailable'
          : '${track.artistName} • ${track.albumTitle}',
      duration: sonusFormatDuration(track.durationSeconds),
      trailing: PopupMenuButton<_TrackSearchAction>(
        key: ValueKey<String>('search-track-menu-${track.songId}'),
        tooltip: 'Song options',
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
            const PopupMenuItem<_TrackSearchAction>(
              value: _TrackSearchAction.addToPlaylist,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.playlist_add_rounded),
                title: Text('Add to playlist'),
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

enum _TrackSearchAction {
  playNext,
  addToQueue,
  addToPlaylist,
  goToArtist,
  goToAlbum,
  toggleBlocked,
}
