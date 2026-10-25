import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef DismissalsGetList = Future<List<String>?> Function(String key);
typedef DismissalsSetList = Future<void> Function(String key, List<String> v);

/// Songs the user chose to keep off an edition when Album Studio offered
/// them (for example "keep Deluxe as it is"), so the offer is not repeated.
///
/// Device-local preferences only: nothing in the library, backups or sync
/// changes, and clearing them only brings the offer back.
class EditionFollowUpDismissals {
  EditionFollowUpDismissals({this._preferences});

  @visibleForTesting
  EditionFollowUpDismissals.forTesting({
    required DismissalsGetList getList,
    required DismissalsSetList setList,
  }) : _preferences = null,
       _getOverride = getList,
       _setOverride = setList;

  static String keyFor(String targetEditionId) =>
      'library.edition_follow_up.dismissed.$targetEditionId';

  SharedPreferencesAsync? _preferences;
  DismissalsGetList? _getOverride;
  DismissalsSetList? _setOverride;

  SharedPreferencesAsync get _platform =>
      _preferences ??= SharedPreferencesAsync();

  Future<Set<String>> dismissed(String targetEditionId) async {
    final key = keyFor(targetEditionId);
    final values = await (_getOverride ?? _platform.getStringList)(key);
    return {...?values};
  }

  Future<void> dismiss(String targetEditionId, Iterable<String> songIds) async {
    final current = await dismissed(targetEditionId);
    await (_setOverride ?? _platform.setStringList)(keyFor(targetEditionId), [
      ...{...current, ...songIds},
    ]);
  }
}
