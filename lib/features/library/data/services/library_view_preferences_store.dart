import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../presentation/widgets/library_view_switch.dart';

typedef LibraryViewGetString = Future<String?> Function(String key);
typedef LibraryViewSetString = Future<void> Function(String key, String value);

/// The device's chosen Library view (`library.view`: `roster` or
/// `filmReel`). Device-local: nothing here touches SQLite, backups or
/// sync. An unreadable value means the default, the Artist Roster, and
/// nothing here ever throws.
class LibraryViewPreferencesStore {
  LibraryViewPreferencesStore({this._preferences}) : _get = null, _set = null;

  @visibleForTesting
  LibraryViewPreferencesStore.forTesting({
    required LibraryViewGetString getString,
    required LibraryViewSetString setString,
  }) : _preferences = null,
       _get = getString,
       _set = setString;

  static const String key = 'library.view';

  final SharedPreferencesAsync? _preferences;
  final LibraryViewGetString? _get;
  final LibraryViewSetString? _set;

  SharedPreferencesAsync get _shared =>
      _preferences ?? SharedPreferencesAsync();

  Future<LibraryView> load() async {
    try {
      final stored = await (_get ?? _shared.getString)(key);
      return LibraryView.fromStorage(stored);
    } catch (error, stackTrace) {
      _log('read', error, stackTrace);
      return LibraryView.roster;
    }
  }

  Future<void> save(LibraryView view) async {
    try {
      await (_set ?? _shared.setString)(key, view.storageName);
    } catch (error, stackTrace) {
      _log('saved', error, stackTrace);
    }
  }

  static void _log(String what, Object error, StackTrace stackTrace) {
    developer.log(
      'Library view could not be $what (${error.runtimeType})',
      name: 'sonus.library.view',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
