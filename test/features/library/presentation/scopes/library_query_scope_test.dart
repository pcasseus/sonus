import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/artwork/application/services/cover_art_candidate_discovery_service.dart';
import 'package:sonus_next/features/library/application/services/metadata_provider.dart';
import 'package:sonus_next/features/library/presentation/scopes/library_query_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

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
}
