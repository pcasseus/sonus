import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/playback_preferences.dart';

typedef PlaybackGetString = Future<String?> Function(String key);
typedef PlaybackSetString = Future<void> Function(String key, String value);

/// What was read from storage, with any fields that had to fall back.
@immutable
class PlaybackPreferencesSnapshot {
  const PlaybackPreferencesSnapshot({
    required this.preferences,
    required this.issues,
  });

  final PlaybackPreferences preferences;

  /// Unreadable or unsupported stored values. Empty when the stored
  /// document was complete and valid, or when nothing was stored.
  final List<String> issues;
}

/// Device-local playback preferences in SharedPreferences, as one versioned
/// JSON document. Nothing here touches SQLite, backups or sync.
class PlaybackPreferencesStore {
  PlaybackPreferencesStore({this._preferences});

  @visibleForTesting
  PlaybackPreferencesStore.forTesting({
    required PlaybackGetString getString,
    required PlaybackSetString setString,
  }) : _preferences = null,
       _getStringOverride = getString,
       _setStringOverride = setString;

  static const String preferencesKey = 'playback.preferences';

  SharedPreferencesAsync? _preferences;
  PlaybackGetString? _getStringOverride;
  PlaybackSetString? _setStringOverride;

  // Created on first use, so constructing the store never touches the
  // platform plugin.
  SharedPreferencesAsync get _platform =>
      _preferences ??= SharedPreferencesAsync();

  /// Reads the stored preferences. Corrupt or unsupported content falls
  /// back to defaults and is reported; storage failures are thrown.
  Future<PlaybackPreferencesSnapshot> load() async {
    final raw = await (_getStringOverride ?? _platform.getString)(
      preferencesKey,
    );

    if (raw == null) {
      return const PlaybackPreferencesSnapshot(
        preferences: PlaybackPreferences(),
        issues: [],
      );
    }

    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return const PlaybackPreferencesSnapshot(
        preferences: PlaybackPreferences(),
        issues: ['unreadable'],
      );
    }

    if (json is! Map<String, Object?>) {
      return const PlaybackPreferencesSnapshot(
        preferences: PlaybackPreferences(),
        issues: ['unreadable'],
      );
    }

    // A document from a newer Sonus may mean something different.
    if (json['version'] != PlaybackPreferences.version) {
      return const PlaybackPreferencesSnapshot(
        preferences: PlaybackPreferences(),
        issues: ['version'],
      );
    }

    final issues = <String>[];
    final preferences = PlaybackPreferences.fromJson(json, issues);
    return PlaybackPreferencesSnapshot(
      preferences: preferences,
      issues: List.unmodifiable(issues),
    );
  }

  Future<void> save(PlaybackPreferences preferences) {
    return (_setStringOverride ?? _platform.setString)(
      preferencesKey,
      jsonEncode(preferences.toJson()),
    );
  }
}
