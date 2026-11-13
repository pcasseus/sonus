import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sonus_next/features/settings/application/controllers/metadata_intelligence_settings_controller.dart';
import 'package:sonus_next/features/settings/presentation/pages/metadata_intelligence_settings_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows unavailable state without controller', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MetadataIntelligenceSettingsPage()),
    );

    expect(
      find.byKey(
        const ValueKey<String>('metadata-intelligence-settings-unavailable'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows metadata intelligence controls', (tester) async {
    final controller = MetadataIntelligenceSettingsController();

    addTearDown(controller.dispose);

    await controller.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: MetadataIntelligenceSettingsPage()),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('metadata-intelligence-online-lookup')),
      findsOneWidget,
    );

    expect(find.text('MusicBrainz'), findsOneWidget);
  });

  testWidgets('REF-18: Cover Art Archive is not offered: no switch, no '
      'provider entry, and online lookup stays usable', (tester) async {
    final controller = MetadataIntelligenceSettingsController();
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: MetadataIntelligenceSettingsPage()),
      ),
    );

    expect(
      find.byKey(
        const ValueKey<String>('metadata-intelligence-cover-art-suggestions'),
      ),
      findsNothing,
    );
    expect(find.textContaining('Cover Art Archive'), findsNothing);
    expect(find.textContaining('artwork suggestions'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('metadata-intelligence-online-lookup')),
    );
    await tester.pumpAndSettle();
    expect(controller.onlineMetadataLookupEnabled, isFalse);
  });

  testWidgets('a saved Cover Art Archive choice is kept as it was', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      MetadataIntelligenceSettingsController.coverArtSuggestionsKey: false,
    });
    final controller = MetadataIntelligenceSettingsController();
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: MetadataIntelligenceSettingsPage()),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('metadata-intelligence-online-lookup')),
    );
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getBool(
        MetadataIntelligenceSettingsController.coverArtSuggestionsKey,
      ),
      isFalse,
    );
    expect(controller.coverArtSuggestionsEnabled, isFalse);
  });
}
