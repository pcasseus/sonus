import 'package:shared_preferences/shared_preferences.dart';

import '../../application/services/moments_last_seen_store.dart';

/// Device-local only: nothing in the library, backups or sync changes, and
/// losing it only shows the dot once more.
class SharedPreferencesMomentsLastSeenStore implements MomentsLastSeenStore {
  SharedPreferencesMomentsLastSeenStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences;

  static const String key = 'charts.moments.last_seen_utc';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _platform =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<DateTime?> read() async {
    final stored = await _platform.getString(key);
    return stored == null ? null : DateTime.tryParse(stored)?.toUtc();
  }

  @override
  Future<void> write(DateTime newestSeenUtc) =>
      _platform.setString(key, newestSeenUtc.toUtc().toIso8601String());
}
