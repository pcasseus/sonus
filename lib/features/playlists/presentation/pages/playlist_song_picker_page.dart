import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design/widgets/sonus_artwork_image.dart';
import '../../../../core/design/widgets/sonus_state_view.dart';
import '../../../library/application/models/library_track.dart';
import '../../../library/presentation/models/alphabet_index.dart';
import '../../../library/presentation/widgets/alphabet_rail.dart';
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
/// [PlaylistSongPickerResult] after adding, or null when closed without
/// (nothing is changed then).
///
/// App Update 1.3: songs show their covers; the library can be browsed as
/// Songs, Artists or Albums, each A–Z with the shared letter rail (the
/// Tracks page's: '#' for titles starting with a digit or symbol, letters
/// without rows dimmed, a tap on one goes to the next letter that has
/// rows, else the one before). Artists and albums open their songs, with
/// Select all. One selection is shared by every mode, group and search.
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

/// Room kept free on the right of every row for the letter rail.
const double _railSpace = AlphabetRail.width + 6;

class _PlaylistSongPickerPageState extends State<PlaylistSongPickerPage> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _jumpTargetKey = GlobalKey();

  /// The row a letter jump brings to the top.
  String? _jumpId;
  String? _scrubLetter;

  List<String>? _indexedKeys;
  AlphabetIndex? _index;

  PlaylistSongPickerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
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

  /// A new list starts at its top.
  void _toTop() {
    _jumpId = null;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _setMode(PlaylistPickerMode mode) {
    _controller.setMode(mode);
    _toTop();
  }

  void _openGroup(String id) {
    _controller.openGroupById(id);
    _toTop();
  }

  void _closeGroup() {
    _controller.closeGroup();
    _toTop();
  }

  /// The letter index of [keys] (built once per list, in one pass), or
  /// null when the list has a single letter.
  AlphabetIndex? _alphabetFor(List<String> keys) {
    if (!identical(keys, _indexedKeys)) {
      _indexedKeys = keys;
      _index = AlphabetIndex.build(keys);
    }
    final index = _index;
    return index != null && index.isUseful ? index : null;
  }

  void _jumpToLetter(String letter, AlphabetIndex index, List<String> ids) {
    final row = index.indexFor(letter);
    if (row == null || !_scroll.hasClients) return;
    final position = _scroll.position;
    // The rows' average height as the list currently estimates it; the
    // exact row is then brought to the top.
    final extent = position.maxScrollExtent + position.viewportDimension;
    final rowHeight = ids.isEmpty ? 0.0 : extent / ids.length;
    _scroll.jumpTo((row * rowHeight).clamp(0.0, position.maxScrollExtent));
    setState(() => _jumpId = ids[row]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _jumpTargetKey.currentContext;
      if (target != null && mounted) {
        Scrollable.ensureVisible(target, alignment: 0);
      }
    });
  }

  Widget _jumpTarget(String id, Widget row) =>
      id == _jumpId ? KeyedSubtree(key: _jumpTargetKey, child: row) : row;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final open = _controller.openGroup;
        return PopScope(
          // Back closes an open artist or release first.
          canPop: open == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _closeGroup();
          },
          child: Scaffold(
            key: const ValueKey<String>('playlist-song-picker'),
            appBar: AppBar(title: Text('Add to ${widget.playlistName}')),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _searchField(),
                _modes(),
                Expanded(child: _body(context)),
              ],
            ),
            bottomNavigationBar: _AddBar(
              count: _controller.selectedCount,
              busy: _controller.isAdding,
              onClear: _controller.clearSelection,
              onAdd: () => unawaited(_addSelected()),
            ),
          ),
        );
      },
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        key: const ValueKey<String>('song-picker-search'),
        controller: _search,
        onChanged: (query) {
          _controller.search(query);
          _toTop();
        },
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
                    key: const ValueKey<String>('song-picker-search-clear'),
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      _controller.search('');
                      _toTop();
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _modes() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SegmentedButton<PlaylistPickerMode>(
        key: const ValueKey<String>('song-picker-mode'),
        showSelectedIcon: false,
        segments: [
          for (final mode in PlaylistPickerMode.values)
            ButtonSegment(
              value: mode,
              label: Text(
                mode.label,
                key: ValueKey<String>('song-picker-mode-${mode.name}'),
              ),
            ),
        ],
        selected: {_controller.mode},
        onSelectionChanged: (modes) => _setMode(modes.single),
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

    final open = controller.openGroup;
    if (open != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupHeader(
            group: open,
            mode: controller.mode,
            allSelected: controller.allSelected(open.tracks),
            canSelect:
                !controller.isAdding &&
                controller.choosable(open.tracks).isNotEmpty,
            onBack: _closeGroup,
            onSelectAll: () => controller.toggleAll(open.tracks),
          ),
          const Divider(height: 1),
          Expanded(
            child: open.tracks.isEmpty
                ? SonusStateView(
                    icon: Icons.search_off_rounded,
                    title: 'No songs match "${controller.query.trim()}"',
                  )
                : _songList(
                    open.tracks,
                    // A release keeps its track order: no letters.
                    withRail: controller.mode == PlaylistPickerMode.artists,
                    listKey: 'song-picker-group-list',
                  ),
          ),
        ],
      );
    }

    if (controller.mode == PlaylistPickerMode.songs) {
      final tracks = controller.visibleTracks;
      if (tracks.isEmpty) return _noMatch();
      return _songList(tracks, withRail: true, listKey: 'song-picker-list');
    }

    final groups = controller.visibleGroups;
    if (groups.isEmpty) return _noMatch();
    return _groupList(groups);
  }

  Widget _noMatch() => SonusStateView(
    icon: Icons.search_off_rounded,
    title: 'No songs match "${_controller.query.trim()}"',
  );

  /// Songs, with the letter rail beside them when they are A–Z.
  Widget _songList(
    List<LibraryTrack> tracks, {
    required bool withRail,
    required String listKey,
  }) {
    final controller = _controller;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final keys = withRail ? _keysOf(tracks) : null;
    final alphabet = keys == null ? null : _alphabetFor(keys);
    // Lazy: only rows on screen are built, so large libraries scroll
    // smoothly.
    final list = ListView.builder(
      key: PageStorageKey<String>(listKey),
      controller: _scroll,
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final inPlaylist = controller.isInPlaylist(track.songId);
        return _jumpTarget(
          track.songId,
          _SongRow(
            track: track,
            inPlaylist: inPlaylist,
            selected: controller.isSelected(track.songId),
            onToggle: inPlaylist || controller.isAdding
                ? null
                : () => controller.toggle(track.songId),
            largeText: largeText,
            endPadding: alphabet == null ? 16 : 16 + _railSpace,
          ),
        );
      },
    );
    return _withRail(
      list,
      alphabet,
      ids: [for (final track in tracks) track.songId],
    );
  }

  Widget _groupList(List<PlaylistPickerGroup> groups) {
    final controller = _controller;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final alphabet = _alphabetFor(_groupKeysOf(groups));
    final list = ListView.builder(
      key: PageStorageKey<String>('song-picker-groups-${controller.mode.name}'),
      controller: _scroll,
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return _jumpTarget(
          group.id,
          _GroupRow(
            group: group,
            isArtist: controller.mode == PlaylistPickerMode.artists,
            selectedCount: controller.selectedIn(group.tracks),
            largeText: largeText,
            endPadding: alphabet == null ? 16 : 16 + _railSpace,
            onOpen: () => _openGroup(group.id),
          ),
        );
      },
    );
    return _withRail(list, alphabet, ids: [for (final g in groups) g.id]);
  }

  Widget _withRail(
    Widget list,
    AlphabetIndex? alphabet, {
    required List<String> ids,
  }) {
    if (alphabet == null) return list;
    final scrubLetter = _scrubLetter;
    return Stack(
      children: [
        list,
        Positioned(
          right: 2,
          top: 8,
          bottom: 8,
          child: AlphabetRail(
            key: ValueKey<String>('song-picker-rail-${_controller.mode.name}'),
            available: alphabet.available,
            onLetter: (letter) => _jumpToLetter(letter, alphabet, ids),
            onScrubbing: (letter) => setState(() => _scrubLetter = letter),
          ),
        ),
        if (scrubLetter != null)
          Center(child: AlphabetScrubBubble(letter: scrubLetter)),
      ],
    );
  }

  // The keys are cached by list identity, so they are built once per list.
  List<LibraryTrack>? _keyedTracks;
  List<String> _trackKeys = const [];
  List<String> _keysOf(List<LibraryTrack> tracks) {
    if (!identical(tracks, _keyedTracks)) {
      _keyedTracks = tracks;
      _trackKeys = List.unmodifiable(
        tracks.map(PlaylistSongPickerController.songKey),
      );
    }
    return _trackKeys;
  }

  List<PlaylistPickerGroup>? _keyedGroups;
  List<String> _groupKeys = const [];
  List<String> _groupKeysOf(List<PlaylistPickerGroup> groups) {
    if (!identical(groups, _keyedGroups)) {
      _keyedGroups = groups;
      _groupKeys = List.unmodifiable(
        groups.map(PlaylistSongPickerController.groupKey),
      );
    }
    return _groupKeys;
  }
}

/// Checkbox, then the song's cover, then its title and details (App Update
/// 1.3). The cover is the library's resolved song artwork (the song's own,
/// else its release's), decoded at thumbnail size, with the shared
/// placeholder when there is none. It is decorative: the row is read as
/// one checkable item by its title (with any version) and details.
class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.track,
    required this.inPlaylist,
    required this.selected,
    required this.onToggle,
    required this.largeText,
    required this.endPadding,
  });

  final LibraryTrack track;
  final bool inPlaylist;
  final bool selected;
  final VoidCallback? onToggle;
  final bool largeText;
  final double endPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onToggle = this.onToggle;
    final subtitle = [
      track.artistName,
      if (track.albumTitle.isNotEmpty) track.albumDisplayTitle,
    ].join(' • ');
    return CheckboxListTile(
      key: ValueKey<String>('song-picker-row-${track.songId}'),
      value: inPlaylist || selected,
      onChanged: onToggle == null ? null : (_) => onToggle(),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsetsDirectional.only(start: 16, end: endPadding),
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
                  // Large text: a second line rather than cutting a long
                  // title short.
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
  }
}

/// An artist or a release in the list: its picture, name, how many songs
/// and how many are chosen. Opens its songs.
class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    required this.isArtist,
    required this.selectedCount,
    required this.largeText,
    required this.endPadding,
    required this.onOpen,
  });

  final PlaylistPickerGroup group;
  final bool isArtist;
  final int selectedCount;
  final bool largeText;
  final double endPadding;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final count = group.tracks.length;
    final details = [
      ?group.detail,
      count == 1 ? '1 song' : '$count songs',
      if (selectedCount > 0) '$selectedCount selected',
    ].join(' • ');
    return ListTile(
      key: ValueKey<String>('song-picker-group-${group.id}'),
      contentPadding: EdgeInsetsDirectional.only(start: 16, end: endPadding),
      leading: SonusArtworkImage(
        key: ValueKey<String>('song-picker-group-artwork-${group.id}'),
        path: group.artworkPath,
        size: _artworkSize,
        circular: isArtist,
        placeholderIcon: isArtist ? Icons.person_rounded : Icons.album_rounded,
      ),
      title: Text(
        group.title,
        maxLines: largeText ? 2 : 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onOpen,
    );
  }
}

/// The open artist or release: back to the list, its name, and Select all
/// (Clear all once every song is chosen).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.mode,
    required this.allSelected,
    required this.canSelect,
    required this.onBack,
    required this.onSelectAll,
  });

  final PlaylistPickerGroup group;
  final PlaylistPickerMode mode;
  final bool allSelected;
  final bool canSelect;
  final VoidCallback onBack;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = allSelected ? 'Clear all' : 'Select all';
    final button = TextButton(
      key: const ValueKey<String>('song-picker-select-all'),
      onPressed: canSelect ? onSelectAll : null,
      child: Text(action, semanticsLabel: '$action songs in ${group.title}'),
    );
    // Large text: Select all goes under the name instead of beside it.
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 12, 4),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey<String>('song-picker-group-back'),
            tooltip: 'Back to ${mode.label.toLowerCase()}',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    group.title,
                    key: const ValueKey<String>('song-picker-group-title'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (group.detail case final detail?)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                if (largeText) button,
              ],
            ),
          ),
          if (!largeText) button,
        ],
      ),
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
