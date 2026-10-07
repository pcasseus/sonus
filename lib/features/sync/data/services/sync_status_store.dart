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

  String _normalizeUserId(String userId) {
    final normalized = userId.trim();

    if (normalized.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    return normalized;
  }
}
