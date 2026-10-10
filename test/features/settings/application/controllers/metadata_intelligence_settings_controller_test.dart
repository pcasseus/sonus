import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sonus_next/features/settings/application/controllers/metadata_intelligence_settings_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults both metadata features on', () async {
    final controller = MetadataIntelligenceSettingsController();

    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.isLoaded, isTrue);
    expect(controller.onlineMetadataLookupEnabled, isTrue);
    expect(controller.coverArtSuggestionsEnabled, isTrue);
    expect(controller.effectiveCoverArtSuggestionsEnabled, isTrue);
  });

  test('loads saved preferences', () async {
    SharedPreferences.setMockInitialValues({
      MetadataIntelligenceSettingsController.onlineMetadataLookupKey: false,
      MetadataIntelligenceSettingsController.coverArtSuggestionsKey: false,
    });

    final controller = MetadataIntelligenceSettingsController();

    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.onlineMetadataLookupEnabled, isFalse);
    expect(controller.coverArtSuggestionsEnabled, isFalse);
    expect(controller.effectiveCoverArtSuggestionsEnabled, isFalse);
  });

  test('persists online metadata lookup preference', () async {
    final controller = MetadataIntelligenceSettingsController();

    addTearDown(controller.dispose);

    await controller.load();
    await controller.setOnlineMetadataLookupEnabled(false);

    final preferences = await SharedPreferences.getInstance();

    expect(controller.onlineMetadataLookupEnabled, isFalse);
    expect(
      preferences.getBool(
        MetadataIntelligenceSettingsController.onlineMetadataLookupKey,
      ),
      isFalse,
    );
  });

  test(
    'cover art becomes ineffective when online lookup is disabled',
    () async {
      final controller = MetadataIntelligenceSettingsController();

      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.coverArtSuggestionsEnabled, isTrue);

      await controller.setOnlineMetadataLookupEnabled(false);

      expect(controller.coverArtSuggestionsEnabled, isTrue);
      expect(controller.effectiveCoverArtSuggestionsEnabled, isFalse);
    },
  );
}
