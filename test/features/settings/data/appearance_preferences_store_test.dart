import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/core/design/sonus_theme_id.dart';
import 'package:sonus_next/core/design/sonus_typography.dart';
import 'package:sonus_next/features/settings/data/appearance_preferences_store.dart';
import 'package:sonus_next/features/settings/domain/models/appearance_preferences.dart';

void main() {
  late Map<String, String> storage;
  late AppearancePreferencesStore store;

  setUp(() {
    storage = {};
    store = AppearancePreferencesStore.forTesting(
      getString: (key) async => storage[key],
      setString: (key, value) async => storage[key] = value,
    );
  });

  test('a fresh device loads defaults without issues', () async {
    final snapshot = await store.load();

    expect(snapshot.preferences, const AppearancePreferences());
    expect(snapshot.device, const AppearanceDeviceSettings());
    expect(snapshot.issues, isEmpty);
  });

  test('saved preferences and device settings load back', () async {
    const preferences = AppearancePreferences(
      theme: SonusThemeId.haze2017,
      typography: SonusTypographyPreset.classicUi,
      highContrast: true,
    );
    const device = AppearanceDeviceSettings(lowEffects: true);

    await store.savePreferences(preferences);
    await store.saveDevice(device);

    final snapshot = await store.load();

    expect(snapshot.preferences, preferences);
    expect(snapshot.device, device);
    expect(snapshot.issues, isEmpty);
  });

  test(
    'portable preferences and device settings are separate documents',
    () async {
      await store.savePreferences(const AppearancePreferences());
      await store.saveDevice(const AppearanceDeviceSettings(lowEffects: true));

      final preferences =
          jsonDecode(storage[AppearancePreferencesStore.preferencesKey]!)
              as Map<String, Object?>;
      final device =
          jsonDecode(storage[AppearancePreferencesStore.deviceKey]!)
              as Map<String, Object?>;

      expect(preferences.containsKey('lowEffects'), isFalse);
      expect(preferences.containsKey('override'), isFalse);
      expect(device.containsKey('theme'), isFalse);
      expect(preferences['version'], 1);
      expect(device['version'], 1);
    },
  );

  test('corrupt documents fall back to defaults and are reported', () async {
    storage[AppearancePreferencesStore.preferencesKey] = '{not json';
    storage[AppearancePreferencesStore.deviceKey] = '[1, 2, 3]';

    final snapshot = await store.load();

    expect(snapshot.preferences, const AppearancePreferences());
    expect(snapshot.device, const AppearanceDeviceSettings());
    expect(snapshot.issues, ['preferences.unreadable', 'device.unreadable']);
  });

  test('a document from a newer Sonus is not reinterpreted', () async {
    storage[AppearancePreferencesStore.preferencesKey] = jsonEncode({
      'version': 2,
      'theme': 'kickflip',
    });

    final snapshot = await store.load();

    expect(snapshot.preferences.theme, SonusThemeId.defaultTheme);
    expect(snapshot.issues, ['preferences.version']);
  });

  test('storage failures reach the caller', () async {
    final failing = AppearancePreferencesStore.forTesting(
      getString: (key) async => throw StateError('disk unavailable'),
      setString: (key, value) async => throw StateError('disk full'),
    );

    await expectLater(failing.load(), throwsStateError);
    await expectLater(
      failing.savePreferences(const AppearancePreferences()),
      throwsStateError,
    );
  });
}
