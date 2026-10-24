import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/playback_session_snapshot.dart';

typedef SessionGetString = Future<String?> Function(String key);
typedef SessionSetString = Future<void> Function(String key, String value);
typedef SessionRemove = Future<void> Function(String key);

/// Device-local storage for the last playback session, as one versioned
/// JSON document. It never touches SQLite, backups or sync, and holds no
/// listening history: only which songs were queued and where playback was.
class PlaybackSessionStore {
  PlaybackSessionStore({this._preferences});

  @visibleForTesting
  PlaybackSessionStore.forTesting({
    required SessionGetString getString,
    required SessionSetString setString,
    required SessionRemove remove,
  }) : _preferences = null,
       _getStringOverride = getString,
       _setStringOverride = setString,
       _removeOverride = remove;

  static const String sessionKey = 'playback.session';

  SharedPreferencesAsync? _preferences;
  SessionGetString? _getStringOverride;
  SessionSetString? _setStringOverride;
  SessionRemove? _removeOverride;

  // Created on first use, so constructing the store never touches the
  // platform plugin.
  SharedPreferencesAsync get _platform =>
      _preferences ??= SharedPreferencesAsync();

  /// The saved session, or null when there is none or it is unreadable.
  /// Storage failures are thrown to the caller.
  Future<PlaybackSessionSnapshot?> load() async {
    final raw = await (_getStringOverride ?? _platform.getString)(sessionKey);
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw);
      return json is Map<String, Object?>
          ? PlaybackSessionSnapshot.fromJson(json)
          : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(PlaybackSessionSnapshot snapshot) {
    return (_setStringOverride ?? _platform.setString)(
      sessionKey,
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<void> clear() {
    return (_removeOverride ?? _platform.remove)(sessionKey);
  }
}
