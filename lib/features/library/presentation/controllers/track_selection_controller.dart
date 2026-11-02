import 'package:flutter/foundation.dart';

import '../../application/models/library_track.dart';

/// Which songs of a list are selected for a bulk action. Selection mode is
/// on from [start] until [exit], even with nothing selected.
class TrackSelectionController extends ChangeNotifier {
  final Set<String> _selectedIds = <String>{};
  bool _isActive = false;

  bool get isActive => _isActive;

  int get count => _selectedIds.length;

  bool isSelected(String songId) => _selectedIds.contains(songId);

  /// Turns selection mode on, selecting [songId] if given.
  void start([String? songId]) {
    _isActive = true;
    if (songId != null) _selectedIds.add(songId);
    notifyListeners();
  }

  void toggle(String songId) {
    if (!_selectedIds.remove(songId)) _selectedIds.add(songId);
    notifyListeners();
  }

  void selectAll(Iterable<String> songIds) {
    _selectedIds.addAll(songIds);
    notifyListeners();
  }

  /// Deselects everything; selection mode stays on.
  void clear() {
    _selectedIds.clear();
    notifyListeners();
  }

  void exit() {
    if (!_isActive && _selectedIds.isEmpty) return;
    _isActive = false;
    _selectedIds.clear();
    notifyListeners();
  }

  /// The selected songs in [visible], in list order, each once.
  List<LibraryTrack> selectedIn(List<LibraryTrack> visible) {
    final seen = <String>{};
    return [
      for (final track in visible)
        if (_selectedIds.contains(track.songId) && seen.add(track.songId))
          track,
    ];
  }

  /// Whether every song in [visible] is selected.
  bool allSelectedIn(List<LibraryTrack> visible) {
    return visible.isNotEmpty &&
        visible.every((track) => _selectedIds.contains(track.songId));
  }
}
