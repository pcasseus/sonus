import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/artwork/application/services/cover_art_candidate_discovery_service.dart';
import 'package:sonus_next/features/library/application/services/metadata_provider.dart';
import 'package:sonus_next/features/library/presentation/scopes/library_query_scope.dart';
import 'package:sonus_next/features/settings/application/controllers/metadata_intelligence_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  AppDatabase openDatabase() {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    return database;
  }

  testWidgets('registers MusicBrainz when online lookup is on', (tester) async {
    MetadataProvider? metadata;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryQueryScope(
          database: openDatabase(),
          child: Builder(
            builder: (context) {
              metadata = context.watch<MetadataProvider?>();
              return const Scaffold(body: Text('Scope ready'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(metadata, isNotNull);
  });

  testWidgets('REF-18: no Cover Art Archive search is provided, even with a '
      'saved "on" choice', (tester) async {
    SharedPreferences.setMockInitialValues({
      MetadataIntelligenceSettingsController.onlineMetadataLookupKey: true,
      MetadataIntelligenceSettingsController.coverArtSuggestionsKey: true,
    });
    var built = false;
    CoverArtCandidateDiscoveryService? discovery;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryQueryScope(
          database: openDatabase(),
          child: Builder(
            builder: (context) {
              built = true;
              // Nullable and not provided: provider gives null.
              discovery = context.watch<CoverArtCandidateDiscoveryService?>();
              return const Scaffold(body: Text('Scope ready'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(built, isTrue);
    expect(discovery, isNull);
  });

  testWidgets('MusicBrainz follows the online lookup setting', (tester) async {
    MetadataProvider? metadata;
    MetadataIntelligenceSettingsController? settings;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryQueryScope(
          database: openDatabase(),
          child: Builder(
            builder: (context) {
              settings = context
                  .watch<MetadataIntelligenceSettingsController>();
              metadata = context.watch<MetadataProvider?>();
              return const Scaffold(body: Text('Scope ready'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(metadata, isNotNull);

    await settings!.setOnlineMetadataLookupEnabled(false);
    await tester.pump();
    expect(metadata, isNull);

    await settings!.setOnlineMetadataLookupEnabled(true);
    await tester.pump();
    expect(metadata, isNotNull);
  });
}
