import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/services/library_view_preferences_store.dart';
import '../widgets/library_view_switch.dart';

/// The Library view the person chose, shared by the Library tab and
/// Settings, and saved on the device: the Artist Roster unless the Film
/// Reel was chosen.
class LibraryViewController extends ChangeNotifier {
  LibraryViewController({LibraryViewPreferencesStore? store})
    : _store = store ?? LibraryViewPreferencesStore();

  final LibraryViewPreferencesStore _store;

  LibraryView _view = LibraryView.roster;
  bool _loaded = false;
  bool _changedBeforeLoad = false;

  LibraryView get view => _view;

  /// Whether the saved choice has been read.
  bool get isLoaded => _loaded;

  /// Reads the saved choice. A choice made meanwhile wins.
  Future<void> load() async {
    final saved = await _store.load();
    if (_changedBeforeLoad) return;
    _loaded = true;
    if (saved == _view) return;
    _view = saved;
    notifyListeners();
  }

  /// Shows [view] and remembers it.
  void choose(LibraryView view) {
    if (!_loaded) _changedBeforeLoad = true;
    _loaded = true;
    if (view == _view) return;
    _view = view;
    notifyListeners();
    unawaited(_store.save(view));
  }
}
