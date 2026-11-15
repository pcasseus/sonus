import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../library/application/models/library_track.dart';
import '../../../library/presentation/models/alphabet_index.dart';
import '../../application/models/playlist_add_result.dart';

/// How the song picker lists the library (App Update 1.3).
enum PlaylistPickerMode {
  songs('Songs'),
  artists('Artists'),
  albums('Albums');

  const PlaylistPickerMode(this.label);

  final String label;
}

/// An artist or a release in the picker, with its songs that match the
/// search, in their natural order (an artist's by title, a release's by
/// disc and track).
class PlaylistPickerGroup {
  const PlaylistPickerGroup({
    required this.id,
    required this.title,
    required this.tracks,
    this.detail,
    this.artworkPath,
  });

  /// The library's own identity: the artist ID or the album ID.
  final String id;
  final String title;

  /// A release's artist; null for an artist.
  final String? detail;

  /// A release's cover; null for an artist.
  final String? artworkPath;

  final List<LibraryTrack> tracks;
}

/// App Update 1.2 (BUG-07), extended in App Update 1.3: choosing songs to
/// add to one playlist.
///
/// Offers the songs a playlist shows: not blocked, with an available file
/// (the playlist service's rule), each Song ID once. They are browsed as
/// Songs (A–Z by title), Artists or Albums (A–Z groups, each opening its
/// songs), filtered by a search over title, artist, featured artists and
/// release. Songs already in the playlist are marked and cannot be chosen
/// again.
///
/// One selection, by Song ID, is shared by every mode, search and group,
/// so it survives all of them and a song is never chosen twice.
/// [addSelected] appends it in the order the songs were chosen, with one
/// call to the playlist service (the same local-first, synced write as
/// every other add): the playlist's existing order is never changed.
class PlaylistSongPickerController extends ChangeNotifier {
  PlaylistSongPickerController({
    required this._loadTracks,
    required Set<String> songIdsInPlaylist,
    required this._add,
  }) : _inPlaylist = Set.unmodifiable(songIdsInPlaylist);

  final Future<List<LibraryTrack>> Function() _loadTracks;
  final Set<String> _inPlaylist;
  final Future<PlaylistAddResult> Function(List<String> songIds) _add;

  List<LibraryTrack> _tracks = const [];
  List<LibraryTrack> _matching = const [];
  List<PlaylistPickerGroup> _artists = const [];
  List<PlaylistPickerGroup> _albums = const [];
  final LinkedHashSet<String> _selected = LinkedHashSet<String>();
  PlaylistPickerMode _mode = PlaylistPickerMode.songs;
  String? _openGroupId;
  String _query = '';
  bool _isLoading = false;
  bool _isAdding = false;
  Object? _error;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  bool get isAdding => _isAdding;
  bool get hasError => _error != null;

  PlaylistPickerMode get mode => _mode;

  /// The artist or release whose songs are open, if any.
  PlaylistPickerGroup? get openGroup {
    final id = _openGroupId;
    if (id == null) return null;
    for (final group in _groupsOf(_mode)) {
      if (group.id == id) return group;
    }
    // Nothing in it matches the search: shown empty, still open.
    return PlaylistPickerGroup(
      id: id,
      title: _groupTitles[id] ?? '',
      tracks: const [],
    );
  }

  final Map<String, String> _groupTitles = {};

  /// The songs listed now: every match A–Z in Songs, or the open group's.
  List<LibraryTrack> get visibleTracks => switch (_mode) {
    PlaylistPickerMode.songs => _matching,
    _ => openGroup?.tracks ?? const [],
  };

  /// The artists or releases listed now (empty in Songs), A–Z.
  List<PlaylistPickerGroup> get visibleGroups =>
      _openGroupId == null ? _groupsOf(_mode) : const [];

  /// Every song the picker offers, before searching.
  int get totalCount => _tracks.length;

  String get query => _query;

  /// Every chosen song, wherever it is listed.
  int get selectedCount => _selected.length;

  bool isInPlaylist(String songId) => _inPlaylist.contains(songId);

  bool isSelected(String songId) => _selected.contains(songId);

  /// The chosen songs, in the order they were chosen.
  List<LibraryTrack> get selectedTracks {
    final byId = {for (final track in _tracks) track.songId: track};
    return [
      for (final id in _selected)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// [tracks] that can still be chosen (not already in the playlist).
  List<LibraryTrack> choosable(Iterable<LibraryTrack> tracks) => [
    for (final track in tracks)
      if (!_inPlaylist.contains(track.songId)) track,
  ];

  /// How many of [tracks] are chosen.
  int selectedIn(Iterable<LibraryTrack> tracks) =>
      tracks.where((track) => _selected.contains(track.songId)).length;

  /// Whether every choosable song of [tracks] is chosen (false when none
  /// can be).
  bool allSelected(Iterable<LibraryTrack> tracks) {
    final open = choosable(tracks);
    return open.isNotEmpty && open.every((t) => _selected.contains(t.songId));
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    _notify();
    try {
      final tracks = await _loadTracks();
      final seen = <String>{};
      _tracks = [
        for (final track in tracks)
          if (_isOffered(track) && seen.add(track.songId)) track,
      ]..sort(_compareSongs);
      _applyQuery();
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  void search(String query) {
    if (query == _query) return;
    _query = query;
    _applyQuery();
    _notify();
  }

  /// Lists the library as [mode]. The selection and search are kept.
  void setMode(PlaylistPickerMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    _openGroupId = null;
    _notify();
  }

  /// Opens an artist's or a release's songs.
  void openGroupById(String id) {
    if (_mode == PlaylistPickerMode.songs) return;
    _openGroupId = id;
    for (final group in _groupsOf(_mode)) {
      if (group.id == id) _groupTitles[id] = group.title;
    }
    _notify();
  }

  /// Back to the list of artists or releases.
  void closeGroup() {
    if (_openGroupId == null) return;
    _openGroupId = null;
    _notify();
  }

  /// Chooses or un-chooses [songId]. Songs already in the playlist cannot
  /// be chosen.
  void toggle(String songId) {
    if (_isAdding || _inPlaylist.contains(songId)) return;
    if (!_selected.remove(songId)) _selected.add(songId);
    _notify();
  }

  /// Chooses every choosable song of [tracks], in their order; when all
  /// already are, un-chooses them. Other choices are kept.
  void toggleAll(Iterable<LibraryTrack> tracks) {
    if (_isAdding) return;
    final open = choosable(tracks);
    if (open.isEmpty) return;
    if (allSelected(open)) {
      for (final track in open) {
        _selected.remove(track.songId);
      }
    } else {
      for (final track in open) {
        _selected.add(track.songId);
      }
    }
    _notify();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    _notify();
  }

  /// Adds the chosen songs. Returns the service's result, or null when
  /// nothing was chosen or the add failed (the choice is kept to retry).
  Future<PlaylistAddResult?> addSelected() async {
    if (_selected.isEmpty || _isAdding) return null;
    _isAdding = true;
    _error = null;
    _notify();
    try {
      return await _add(List.unmodifiable(_selected));
    } catch (error) {
      _error = error;
      return null;
    } finally {
      _isAdding = false;
      _notify();
    }
  }

  /// The sort key a song, artist or release is filed under on the A–Z
  /// rail; the lists are ordered so each letter's rows are together.
  static String songKey(LibraryTrack track) => track.title;
  static String groupKey(PlaylistPickerGroup group) => group.title;

  List<PlaylistPickerGroup> _groupsOf(PlaylistPickerMode mode) =>
      switch (mode) {
        PlaylistPickerMode.songs => const [],
        PlaylistPickerMode.artists => _artists,
        PlaylistPickerMode.albums => _albums,
      };

  /// The playlist's own rule: a blocked song or one without a file to
  /// play is not shown in a playlist, so it is not offered.
  static bool _isOffered(LibraryTrack track) =>
      !track.isBlocked &&
      track.isAvailable &&
      (track.filePath?.trim().isNotEmpty ?? false);

  void _applyQuery() {
    final terms = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    _matching = terms.isEmpty
        ? _tracks
        : [
            for (final track in _tracks)
              if (terms.every(_searchText(track).contains)) track,
          ];
    _artists = _group(
      _matching,
      idOf: (track) => track.artistId,
      titleOf: (track) => track.artistName,
      order: _compareSongs,
    );
    _albums = _group(
      _matching,
      idOf: (track) => track.albumId,
      titleOf: (track) => track.albumDisplayTitle,
      detailOf: (track) => track.artistName,
      artworkOf: _releaseCover,
      order: _compareInRelease,
    );
  }

  static List<PlaylistPickerGroup> _group(
    List<LibraryTrack> tracks, {
    required String Function(LibraryTrack) idOf,
    required String Function(LibraryTrack) titleOf,
    required int Function(LibraryTrack, LibraryTrack) order,
    String Function(LibraryTrack)? detailOf,
    String? Function(List<LibraryTrack>)? artworkOf,
  }) {
    final byId = <String, List<LibraryTrack>>{};
    for (final track in tracks) {
      byId.putIfAbsent(idOf(track), () => []).add(track);
    }
    final groups = [
      for (final MapEntry(key: id, value: members) in byId.entries)
        PlaylistPickerGroup(
          id: id,
          title: titleOf(members.first),
          detail: detailOf?.call(members.first),
          artworkPath: artworkOf?.call(members),
          tracks: List.unmodifiable(members..sort(order)),
        ),
    ];
    groups.sort((a, b) {
      final byKey = _compareKeys(groupKey(a), groupKey(b));
      if (byKey != 0) return byKey;
      final byDetail = (a.detail ?? '').toLowerCase().compareTo(
        (b.detail ?? '').toLowerCase(),
      );
      return byDetail != 0 ? byDetail : a.id.compareTo(b.id);
    });
    return List.unmodifiable(groups);
  }

  /// A release's cover: the artwork most of its songs show (a song with a
  /// cover of its own does not replace the release's); ties go to the
  /// first song's.
  static String? _releaseCover(List<LibraryTrack> tracks) {
    final counts = <String, int>{};
    String? best;
    for (final track in tracks) {
      final path = track.artworkPath?.trim();
      if (path == null || path.isEmpty) continue;
      final count = counts[path] = (counts[path] ?? 0) + 1;
      if (best == null || count > counts[best]!) best = path;
    }
    return best;
  }

  /// A–Z by the rail's letter ('#' first), then title, artist and ID.
  static int _compareSongs(LibraryTrack a, LibraryTrack b) {
    final byKey = _compareKeys(songKey(a), songKey(b));
    if (byKey != 0) return byKey;
    final byArtist = a.artistName.toLowerCase().compareTo(
      b.artistName.toLowerCase(),
    );
    return byArtist != 0 ? byArtist : a.songId.compareTo(b.songId);
  }

  /// A release's songs by disc and track, then title and ID.
  static int _compareInRelease(LibraryTrack a, LibraryTrack b) {
    for (final comparison in [
      a.discNumber.compareTo(b.discNumber),
      a.trackNumber.compareTo(b.trackNumber),
      a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      a.songId.compareTo(b.songId),
    ]) {
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static int _compareKeys(String a, String b) {
    final letters = AlphabetIndex.letters;
    final byLetter = letters
        .indexOf(AlphabetIndex.letterOf(a))
        .compareTo(letters.indexOf(AlphabetIndex.letterOf(b)));
    if (byLetter != 0) return byLetter;
    return a.trim().toLowerCase().compareTo(b.trim().toLowerCase());
  }

  static String _searchText(LibraryTrack track) => [
    track.displayTitle,
    track.title,
    track.artistName,
    ...track.featuredArtists,
    track.albumTitle,
    track.albumDisplayTitle,
  ].join(' ').toLowerCase();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
