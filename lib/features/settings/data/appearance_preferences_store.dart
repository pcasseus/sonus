import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/appearance_preferences.dart';

typedef AppearanceGetString = Future<String?> Function(String key);
typedef AppearanceSetString = Future<void> Function(String key, String value);

/// What was read from storage, with any fields that had to fall back.
@immutable
class AppearanceStoreSnapshot {
  const AppearanceStoreSnapshot({
    required this.preferences,
    required this.device,
    required this.issues,
  });

  final AppearancePreferences preferences;
  final AppearanceDeviceSettings device;

  /// Unreadable or unsupported stored values, by field. Empty when the
  /// stored documents were complete and valid.
  final List<String> issues;
}

/// Device-local appearance storage in SharedPreferences.
///
/// Two versioned JSON documents keep portable user preferences apart from
/// device-only settings, so the portable one can later join backups and
/// cloud sync unchanged. Nothing here touches SQLite.
class AppearancePreferencesStore {
  AppearancePreferencesStore({this._preferences});

  @visibleForTesting
  AppearancePreferencesStore.forTesting({
    required AppearanceGetString getString,
    required AppearanceSetString setString,
  }) : _preferences = null,
       _getStringOverride = getString,
       _setStringOverride = setString;

  static const String preferencesKey = 'appearance.preferences';
  static const String deviceKey = 'appearance.device';

  SharedPreferencesAsync? _preferences;
  AppearanceGetString? _getStringOverride;
  AppearanceSetString? _setStringOverride;

  // Created on first use, so constructing the store never touches the
  // platform plugin.
  SharedPreferencesAsync get _platform =>
      _preferences ??= SharedPreferencesAsync();

  Future<String?> _getString(String key) =>
      (_getStringOverride ?? _platform.getString)(key);

  Future<void> _setString(String key, String value) =>
      (_setStringOverride ?? _platform.setString)(key, value);

  /// Reads both documents. Corrupt or unsupported content falls back to
  /// defaults field by field and is reported in the snapshot's issues;
  /// storage failures are thrown to the caller.
  Future<AppearanceStoreSnapshot> load() async {
    final issues = <String>[];

    final preferences = _decode(
      await _getString(preferencesKey),
      'preferences',
      AppearancePreferences.version,
      issues,
      (json) => AppearancePreferences.fromJson(json, issues),
      const AppearancePreferences(),
    );

    final device = _decode(
      await _getString(deviceKey),
      'device',
      AppearanceDeviceSettings.version,
      issues,
      (json) => AppearanceDeviceSettings.fromJson(json, issues),
      const AppearanceDeviceSettings(),
    );

    return AppearanceStoreSnapshot(
      preferences: preferences,
      device: device,
      issues: List.unmodifiable(issues),
    );
  }

  Future<void> savePreferences(AppearancePreferences preferences) {
    return _setString(preferencesKey, jsonEncode(preferences.toJson()));
  }

  Future<void> saveDevice(AppearanceDeviceSettings device) {
    return _setString(deviceKey, jsonEncode(device.toJson()));
  }

  T _decode<T>(
    String? raw,
    String document,
    int supportedVersion,
    List<String> issues,
    T Function(Map<String, Object?> json) parse,
    T defaults,
  ) {
    if (raw == null) {
      return defaults;
    }

    final Object? json;

    try {
      json = jsonDecode(raw);
    } on FormatException {
      issues.add('$document.unreadable');
      return defaults;
    }

    if (json is! Map<String, Object?>) {
      issues.add('$document.unreadable');
      return defaults;
    }

    // A document from a newer Sonus may mean something different; it is
    // not reinterpreted.
    if (json['version'] != supportedVersion) {
      issues.add('$document.version');
      return defaults;
    }

    return parse(json);
  }
}
