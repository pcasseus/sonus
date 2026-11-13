import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../library/application/models/library_track.dart';
import '../../application/models/playlist_add_result.dart';

/// App Update 1.2 (BUG-07): choosing songs to add to one playlist.
///
/// Lists the library's songs (blocked songs are left out, as playlists
/// hide them), filtered by a search over title, artist, featured artists
/// and release. Songs already in the playlist are marked and cannot be
/// chosen again. The selection survives searching, and [addSelected]
/// appends it in the order the songs were chosen, with one call to the
/// playlist service (the same local-first, synced write as every other
/// add): the playlist's existing order is never changed.
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
  List<LibraryTrack> _visible = const [];
  final LinkedHashSet<String> _selected = LinkedHashSet<String>();
  String _query = '';
  bool _isLoading = false;
  bool _isAdding = false;
  Object? _error;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  bool get isAdding => _isAdding;
  bool get hasError => _error != null;

  /// Songs matching the search, in library order.
  List<LibraryTrack> get visibleTracks => _visible;

  /// Every song the picker offers, before searching.
  int get totalCount => _tracks.length;

  String get query => _query;

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

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    _notify();
    try {
      final tracks = await _loadTracks();
      final seen = <String>{};
      _tracks = [
        for (final track in tracks)
          if (!track.isBlocked && seen.add(track.songId)) track,
      ];
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

  /// Chooses or un-chooses [songId]. Songs already in the playlist cannot
  /// be chosen.
  void toggle(String songId) {
    if (_isAdding || _inPlaylist.contains(songId)) return;
    if (!_selected.remove(songId)) _selected.add(songId);
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

  void _applyQuery() {
    final terms = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) {
      _visible = _tracks;
      return;
    }
    _visible = [
      for (final track in _tracks)
        if (terms.every(_searchText(track).contains)) track,
    ];
  }

  static String _searchText(LibraryTrack track) => [
    track.displayTitle,
    track.title,
    track.artistName,
    ...track.featuredArtists,
    track.albumTitle,
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
