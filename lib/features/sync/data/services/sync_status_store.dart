import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

typedef SyncStatusGetString = Future<String?> Function(String key);
typedef SyncStatusSetString = Future<void> Function(String key, String value);

class SyncStatusStore {
  SyncStatusStore({SharedPreferencesAsync? preferences})
    : this._(
        getString: (preferences ?? SharedPreferencesAsync()).getString,
        setString: (preferences ?? SharedPreferencesAsync()).setString,
      );

  SyncStatusStore.forTesting({
    required SyncStatusGetString getString,
    required SyncStatusSetString setString,
  }) : this._(getString: getString, setString: setString);

  SyncStatusStore._({required this._getString, required this._setString});

  static const String _lastSuccessfulSyncPrefix = 'sync.last_successful_sync.';
  static const String _pausedPrefix = 'sync.paused.';

  final SyncStatusGetString _getString;
  final SyncStatusSetString _setString;

  Future<DateTime?> getLastSuccessfulSync(String userId) async {
    final normalizedUserId = _normalizeUserId(userId);

    final value = await _getString(
      '$_lastSuccessfulSyncPrefix$normalizedUserId',
    );

    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(value)?.toUtc();
  }

  Future<void> saveLastSuccessfulSync(String userId, DateTime timestamp) {
    final normalizedUserId = _normalizeUserId(userId);

    return _setString(
      '$_lastSuccessfulSyncPrefix$normalizedUserId',
      timestamp.toUtc().toIso8601String(),
    );
  }

  /// Why and since when sync is paused for [userId] (a permanent failure),
  /// or null. Kept per account on this device, across sign-out.
  Future<SyncPause?> getPause(String userId) async {
    final value = await _getString('$_pausedPrefix${_normalizeUserId(userId)}');
    if (value == null || value.trim().isEmpty) return null;
    try {
      final json = jsonDecode(value);
      if (json is! Map) return null;
      final code = json['code'];
      final since = DateTime.tryParse('${json['sinceUtc']}');
      if (code is! String || since == null) return null;
      return SyncPause(code: code, sinceUtc: since.toUtc());
    } on FormatException {
      return null;
    }
  }

  Future<void> savePause(String userId, SyncPause pause) => _setString(
    '$_pausedPrefix${_normalizeUserId(userId)}',
    jsonEncode({
      'code': pause.code,
      'sinceUtc': pause.sinceUtc.toUtc().toIso8601String(),
    }),
  );

  Future<void> clearPause(String userId) =>
      _setString('$_pausedPrefix${_normalizeUserId(userId)}', '');

  String _normalizeUserId(String userId) {
    final normalized = userId.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    return normalized;
  }
}

/// Sync stopped for a failure that retrying on its own cannot fix.
class SyncPause {
  const SyncPause({required this.code, required this.sinceUtc});

  final String code;
  final DateTime sinceUtc;
}
