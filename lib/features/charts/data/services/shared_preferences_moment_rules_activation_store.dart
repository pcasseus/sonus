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
    implements
        MomentRulesActivationStore,
        MomentDevicePolishStore,
        MomentChronicleStore,
        MomentDominanceStore {
  SharedPreferencesMomentRulesActivationStore([
    SharedPreferencesAsync? preferences,
  ]) : _preferences = preferences;

  static const String key = 'charts.moments.rules_activated_utc';

  /// Where refined catalog [version] (2 or later) started (SN-50 R-V).
  static String catalogStartKey(int version) =>
      'charts.moments.refined_catalog_v${version}_from_utc';

  /// Where the climb wording revision started (SN-50 device polish).
  static const String devicePolishKey = 'charts.moments.device_polish_from_utc';

  /// Where the App Update 1.1 Moments chronicle started.
  static const String chronicleKey = 'charts.moments.chronicle_1_1_from_utc';

  /// Where App Update 1.2 artist-dominance Moments started (REF-19).
  static const String dominanceKey = 'charts.moments.dominance_1_2_from_utc';

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

  @override
  Future<String?> readDevicePolishStart() =>
      _platform.getString(devicePolishKey);

  @override
  Future<void> writeDevicePolishStart(String fromUtc) =>
      _platform.setString(devicePolishKey, fromUtc);

  @override
  Future<String?> readChronicleStart() => _platform.getString(chronicleKey);

  @override
  Future<void> writeChronicleStart(String fromUtc) =>
      _platform.setString(chronicleKey, fromUtc);

  @override
  Future<String?> readDominanceStart() => _platform.getString(dominanceKey);

  @override
  Future<void> writeDominanceStart(String fromUtc) =>
      _platform.setString(dominanceKey, fromUtc);
}
