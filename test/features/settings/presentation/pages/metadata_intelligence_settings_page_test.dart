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

    expect(
      find.byKey(
        const ValueKey<String>('metadata-intelligence-cover-art-suggestions'),
      ),
      findsOneWidget,
    );

    expect(find.text('MusicBrainz'), findsOneWidget);
    expect(find.text('Cover Art Archive'), findsOneWidget);
  });

  testWidgets('disabling online lookup disables cover art control', (
    tester,
  ) async {
    final controller = MetadataIntelligenceSettingsController();

    addTearDown(controller.dispose);

    await controller.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: MetadataIntelligenceSettingsPage()),
      ),
    );

    final onlineFinder = find.byKey(
      const ValueKey<String>('metadata-intelligence-online-lookup'),
    );

    await tester.tap(onlineFinder);
    await tester.pumpAndSettle();

    expect(controller.onlineMetadataLookupEnabled, isFalse);

    final coverArtTile = tester.widget<SwitchListTile>(
      find.byKey(
        const ValueKey<String>('metadata-intelligence-cover-art-suggestions'),
      ),
    );

    expect(coverArtTile.onChanged, isNull);
  });
}
