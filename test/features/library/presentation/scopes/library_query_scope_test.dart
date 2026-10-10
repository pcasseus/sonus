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

  testWidgets('registers CAA discovery alongside MusicBrainz', (tester) async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );

    addTearDown(database.close);

    CoverArtCandidateDiscoveryService? discovery;
    MetadataProvider? metadata;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryQueryScope(
          database: database,
          child: Builder(
            builder: (context) {
              discovery = context.watch<CoverArtCandidateDiscoveryService?>();
              metadata = context.watch<MetadataProvider?>();
              return const Scaffold(body: Text('Scope ready'));
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(discovery, isNotNull);
    expect(metadata, isNotNull);
    expect(discovery!.client.transport, isNotNull);
    expect(discovery!.client.userAgent, isNotEmpty);
  });

  testWidgets('disables MusicBrainz and CAA when online lookup is disabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      MetadataIntelligenceSettingsController.onlineMetadataLookupKey: false,
      MetadataIntelligenceSettingsController.coverArtSuggestionsKey: true,
    });

    final database = AppDatabase(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );

    addTearDown(database.close);

    CoverArtCandidateDiscoveryService? discovery;
    MetadataProvider? metadata;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryQueryScope(
          database: database,
          child: Builder(
            builder: (context) {
              discovery = context.watch<CoverArtCandidateDiscoveryService?>();
              metadata = context.watch<MetadataProvider?>();
              return const Scaffold(body: Text('Scope ready'));
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(metadata, isNull);
    expect(discovery, isNull);
  });

  testWidgets('disables only CAA when artwork suggestions are disabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      MetadataIntelligenceSettingsController.onlineMetadataLookupKey: true,
      MetadataIntelligenceSettingsController.coverArtSuggestionsKey: false,
    });

    final database = AppDatabase(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );

    addTearDown(database.close);

    CoverArtCandidateDiscoveryService? discovery;
    MetadataProvider? metadata;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryQueryScope(
          database: database,
          child: Builder(
            builder: (context) {
              discovery = context.watch<CoverArtCandidateDiscoveryService?>();
              metadata = context.watch<MetadataProvider?>();
              return const Scaffold(body: Text('Scope ready'));
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(metadata, isNotNull);
    expect(discovery, isNull);
  });

  testWidgets('updates provider availability when settings change', (
    tester,
  ) async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );

    addTearDown(database.close);

    CoverArtCandidateDiscoveryService? discovery;
    MetadataProvider? metadata;
    MetadataIntelligenceSettingsController? settings;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryQueryScope(
          database: database,
          child: Builder(
            builder: (context) {
              settings = context
                  .watch<MetadataIntelligenceSettingsController>();
              discovery = context.watch<CoverArtCandidateDiscoveryService?>();
              metadata = context.watch<MetadataProvider?>();
              return const Scaffold(body: Text('Scope ready'));
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(metadata, isNotNull);
    expect(discovery, isNotNull);

    await settings!.setOnlineMetadataLookupEnabled(false);
    await tester.pump();

    expect(metadata, isNull);
    expect(discovery, isNull);

    await settings!.setOnlineMetadataLookupEnabled(true);
    await settings!.setCoverArtSuggestionsEnabled(false);
    await tester.pump();

    expect(metadata, isNotNull);
    expect(discovery, isNull);
  });
}
