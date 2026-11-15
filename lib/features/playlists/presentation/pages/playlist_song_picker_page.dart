import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design/widgets/sonus_artwork_image.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../library/application/models/library_track.dart';
import '../../application/models/playlist_add_result.dart';
import '../controllers/playlist_song_picker_controller.dart';

/// What the song picker added: the service's result and the songs chosen,
/// for the confirmation message.
class PlaylistSongPickerResult {
  const PlaylistSongPickerResult({required this.result, required this.tracks});

  final PlaylistAddResult result;
  final List<LibraryTrack> tracks;
}

/// App Update 1.2 (BUG-07): a dedicated screen to search the library and
/// add several songs to [playlistName] at once. Pops with a
/// [PlaylistSongPickerResult] after adding, or null when closed without.
class PlaylistSongPickerPage extends StatefulWidget {
  const PlaylistSongPickerPage({
    super.key,
    required this.playlistName,
    required this.controller,
  });

  final String playlistName;

  /// Owned by the page: disposed with it.
  final PlaylistSongPickerController controller;

  /// Opens the picker for a playlist. [add] appends the chosen song ids.
  static Future<PlaylistSongPickerResult?> open(
    BuildContext context, {
    required String playlistName,
    required Set<String> songIdsInPlaylist,
    required Future<List<LibraryTrack>> Function() loadTracks,
    required Future<PlaylistAddResult> Function(List<String> songIds) add,
  }) {
    return Navigator.of(context).push<PlaylistSongPickerResult>(
      MaterialPageRoute<PlaylistSongPickerResult>(
        builder: (_) => PlaylistSongPickerPage(
          playlistName: playlistName,
          controller: PlaylistSongPickerController(
            loadTracks: loadTracks,
            songIdsInPlaylist: songIdsInPlaylist,
            add: add,
          ),
        ),
      ),
    );
  }

  @override
  State<PlaylistSongPickerPage> createState() => _PlaylistSongPickerPageState();
}

/// Cover thumbnails in the list: the size Sonus song rows use.
const double _artworkSize = 48;

class _PlaylistSongPickerPageState extends State<PlaylistSongPickerPage> {
  final TextEditingController _search = TextEditingController();

  PlaylistSongPickerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _search.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addSelected() async {
    final tracks = _controller.selectedTracks;
    final result = await _controller.addSelected();
    if (!mounted) return;
    if (result == null) {
      if (_controller.hasError) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not add the songs. Try again.'),
            ),
          );
      }
      return;
    }
    Navigator.of(
      context,
    ).pop(PlaylistSongPickerResult(result: result, tracks: tracks));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey<String>('playlist-song-picker'),
      appBar: AppBar(
        title: Text('Add to ${widget.playlistName}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const ValueKey<String>('song-picker-search'),
              controller: _search,
              onChanged: _controller.search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search songs, artists or releases',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: ListenableBuilder(
                  listenable: _search,
                  builder: (context, _) => _search.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          key: const ValueKey<String>(
                            'song-picker-search-clear',
                          ),
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _controller.search('');
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _body(context),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _AddBar(
          count: _controller.selectedCount,
          busy: _controller.isAdding,
          onClear: _controller.clearSelection,
          onAdd: () => unawaited(_addSelected()),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final controller = _controller;
    if (controller.isLoading && controller.totalCount == 0) {
      return const SonusStateView.loading();
    }
    if (controller.hasError && controller.totalCount == 0) {
      return SonusStateView(
        icon: Icons.error_outline_rounded,
        isError: true,
        title: 'Could not load your songs.',
        action: FilledButton.tonal(
          onPressed: () => unawaited(controller.load()),
          child: const Text('Try again'),
        ),
      );
    }
    if (controller.totalCount == 0) {
      return const SonusStateView(
        icon: Icons.library_music_outlined,
        title: 'No songs yet',
        message: 'Songs will appear here as music is added to your library.',
      );
    }
    final tracks = controller.visibleTracks;
    if (tracks.isEmpty) {
      return SonusStateView(
        icon: Icons.search_off_rounded,
        title: 'No songs match "${controller.query.trim()}"',
      );
    }
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final theme = Theme.of(context);
    // Lazy: only rows on screen are built, so large libraries scroll
    // smoothly.
    return ListView.builder(
      key: const PageStorageKey<String>('song-picker-list'),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final inPlaylist = controller.isInPlaylist(track.songId);
        final selected = controller.isSelected(track.songId);
        final subtitle = [
          track.artistName,
          if (track.albumTitle.isNotEmpty) track.albumTitle,
        ].join(' • ');
        // Checkbox, then the song's cover, then its title and details
        // (App Update 1.3). The cover is the library's resolved song
        // artwork (the song's own, else its release's), decoded at
        // thumbnail size, with the shared placeholder when there is none.
        // It is decorative: the row is read by its title and details.
        return CheckboxListTile(
          key: ValueKey<String>('song-picker-row-${track.songId}'),
          value: inPlaylist || selected,
          onChanged: inPlaylist || controller.isAdding
              ? null
              : (_) => controller.toggle(track.songId),
          controlAffinity: ListTileControlAffinity.leading,
          title: Row(
            children: [
              SonusArtworkImage(
                key: ValueKey<String>('song-picker-artwork-${track.songId}'),
                path: track.artworkPath,
                size: _artworkSize,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.displayTitle,
                      // Large text: a second line rather than cutting a
                      // long title short.
                      maxLines: largeText ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      inPlaylist ? 'In playlist • $subtitle' : subtitle,
                      key: inPlaylist
                          ? ValueKey<String>(
                              'song-picker-in-playlist-${track.songId}',
                            )
                          : null,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AddBar extends StatelessWidget {
  const _AddBar({
    required this.count,
    required this.busy,
    required this.onClear,
    required this.onAdd,
  });

  final int count;
  final bool busy;
  final VoidCallback onClear;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          // One line normally: the count, then the buttons at the end. With
          // large text on a narrow phone the buttons wrap below the count
          // instead of running off the screen.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  count == 1 ? '1 selected' : '$count selected',
                  key: const ValueKey<String>('song-picker-count'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (count > 0)
                    TextButton(
                      key: const ValueKey<String>('song-picker-clear'),
                      onPressed: busy ? null : onClear,
                      child: const Text('Clear'),
                    ),
                  FilledButton.icon(
                    key: const ValueKey<String>('song-picker-add'),
                    onPressed: count == 0 || busy ? null : onAdd,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.playlist_add_rounded),
                    label: const Text('Add selected'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
