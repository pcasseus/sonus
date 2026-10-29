import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../../application/services/moments_last_seen_store.dart';

/// Device-local only: nothing in the library, backups or sync changes, and
/// losing it only records a new mark on the next visit, without a dot.
///
/// Stored as `<occurred time>|<story id>`, or empty for a feed seen with
/// no stories.
class SharedPreferencesMomentsLastSeenStore implements MomentsLastSeenStore {
  SharedPreferencesMomentsLastSeenStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences;

  static const String key = 'charts.moments.last_seen_utc';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _platform =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<MomentsSeenMark?> read() async {
    final stored = await _platform.getString(key);
    if (stored == null) return null;
    if (stored.isEmpty) return const MomentsSeenMark.empty();

    final separator = stored.indexOf('|');
    final occurredAt = separator < 0
        ? null
        : DateTime.tryParse(stored.substring(0, separator));
    if (occurredAt == null) {
      developer.log(
        'The Moments last-seen mark is unreadable; the next visit records '
        'a new one',
        name: 'sonus.charts',
        level: 800,
      );
      return null;
    }

    return MomentsSeenMark(
      occurredAtUtc: occurredAt.toUtc(),
      storyId: stored.substring(separator + 1),
    );
  }

  @override
  Future<void> write(MomentsSeenMark newestSeen) {
    final occurredAt = newestSeen.occurredAtUtc;
    return _platform.setString(
      key,
      occurredAt == null
          ? ''
          : '${occurredAt.toUtc().toIso8601String()}|${newestSeen.storyId}',
    );
  }
}
