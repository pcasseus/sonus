import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/pending_possible_recording.dart';

typedef PossibleRecordingGetString = Future<String?> Function(String key);
typedef PossibleRecordingSetString =
    Future<void> Function(String key, String value);

/// Possible different recordings waiting for the user's decision, and the
/// files the user said are the same recording. Kept on this device only;
/// unreadable stored data is ignored.
class PossibleRecordingStore {
  PossibleRecordingStore({SharedPreferencesAsync? preferences})
    : this._fromPreferences(_LazyPreferences(preferences));

  PossibleRecordingStore._fromPreferences(_LazyPreferences preferences)
    : this._(
        getString: (key) => preferences.instance.getString(key),
        setString: (key, value) => preferences.instance.setString(key, value),
      );

  PossibleRecordingStore.forTesting({
    required PossibleRecordingGetString getString,
    required PossibleRecordingSetString setString,
  }) : this._(getString: getString, setString: setString);

  PossibleRecordingStore._({
    required this._getString,
    required this._setString,
  });

  static const String _pendingKey = 'import.possible_recordings.pending';
  static const String _sameRecordingKey =
      'import.possible_recordings.same_recording';

  final PossibleRecordingGetString _getString;
  final PossibleRecordingSetString _setString;

  Future<void> _lastWrite = Future<void>.value();

  /// Pending files, oldest first.
  Future<List<PendingPossibleRecording>> getPending() async {
    final entries = [
      for (final json in await _readList(_pendingKey))
        ?PendingPossibleRecording.tryFromJson(json),
    ];
    entries.sort((a, b) => a.firstSeenAt.compareTo(b.firstSeenAt));
    return List.unmodifiable(entries);
  }

  /// Adds [entry], or replaces the entry for the same path while keeping
  /// when it was first seen.
  Future<void> upsert(PendingPossibleRecording entry) => _write(() async {
    final entries = await getPending();
    final existing = entries
        .where((e) => e.normalizedPath == entry.normalizedPath)
        .firstOrNull;
    final saved = existing == null
        ? entry
        : entry.copyWith(firstSeenAt: existing.firstSeenAt);

    await _savePending([
      for (final e in entries)
        if (e.normalizedPath != entry.normalizedPath) e,
      saved,
    ]);
  });

  Future<void> remove(String normalizedPath) => _write(() async {
    final entries = await getPending();
    if (!entries.any((e) => e.normalizedPath == normalizedPath)) return;

    await _savePending([
      for (final e in entries)
        if (e.normalizedPath != normalizedPath) e,
    ]);
  });

  /// Whether the user said this file is the same recording as the song.
  /// A different song or duration at the path is a different file.
  Future<bool> isSameRecording({
    required String normalizedPath,
    required String candidateSongId,
    required int durationSeconds,
  }) async {
    for (final json in await _readList(_sameRecordingKey)) {
      if (json is Map &&
          json['normalizedPath'] == normalizedPath &&
          json['candidateSongId'] == candidateSongId &&
          json['durationSeconds'] == durationSeconds) {
        return true;
      }
    }
    return false;
  }

  /// Records that [entry] is the same recording as its song and removes it
  /// from the pending files.
  Future<void> markSameRecording(PendingPossibleRecording entry) =>
      _write(() async {
        final kept = [
          for (final json in await _readList(_sameRecordingKey))
            if (json is Map && json['normalizedPath'] != entry.normalizedPath)
              json,
        ];

        await _setString(
          _sameRecordingKey,
          jsonEncode([
            ...kept,
            {
              'normalizedPath': entry.normalizedPath,
              'candidateSongId': entry.candidateSongId,
              'durationSeconds': entry.durationSeconds,
            },
          ]),
        );

        final entries = await getPending();
        await _savePending([
          for (final e in entries)
            if (e.normalizedPath != entry.normalizedPath) e,
        ]);
      });

  Future<void> _savePending(List<PendingPossibleRecording> entries) {
    return _setString(
      _pendingKey,
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }

  Future<List<Object?>> _readList(String key) async {
    try {
      final value = await _getString(key);
      if (value == null || value.trim().isEmpty) return const [];
      final json = jsonDecode(value);
      return json is List ? json : const [];
    } on FormatException {
      return const [];
    } on TypeError {
      // Another type stored under the key.
      return const [];
    }
  }

  /// Runs read-modify-write updates one at a time.
  Future<void> _write(Future<void> Function() update) {
    final next = _lastWrite.catchError((Object _) {}).then((_) => update());
    _lastWrite = next;
    return next;
  }
}

/// Creates the platform preferences on first use, so building the store
/// never fails where no platform is set up.
class _LazyPreferences {
  _LazyPreferences(this._preferences);

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get instance =>
      _preferences ??= SharedPreferencesAsync();
}
