import 'package:shared_preferences/shared_preferences.dart';

import '../../application/services/moment_rules_activation.dart';

/// Device preferences, beside the Moments last-seen time: no database
/// table holds app settings, and nothing here touches the library schema.
///
/// Sonus library backups do not include it. A reinstall or a cleared app
/// loses it unless the platform restores app data; a restore that brings
/// it back keeps the original instant, otherwise an approved build
/// records a new one when it next runs.
class SharedPreferencesMomentRulesActivationStore
    implements MomentRulesActivationStore {
  SharedPreferencesMomentRulesActivationStore([
    SharedPreferencesAsync? preferences,
  ]) : _preferences = preferences;

  static const String key = 'charts.moments.rules_activated_utc';

  /// Where refined catalog [version] (2 or later) started (SN-50 R-V).
  static String catalogStartKey(int version) =>
      'charts.moments.refined_catalog_v${version}_from_utc';

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _platform =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<String?> read() => _platform.getString(key);

  @override
  Future<void> write(String activatedAtUtc) =>
      _platform.setString(key, activatedAtUtc);

  @override
  Future<String?> readCatalogStart(int version) =>
      _platform.getString(catalogStartKey(version));

  @override
  Future<void> writeCatalogStart(int version, String fromUtc) =>
      _platform.setString(catalogStartKey(version), fromUtc);
}
