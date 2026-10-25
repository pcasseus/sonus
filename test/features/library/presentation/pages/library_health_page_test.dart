import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/library/application/models/library_health_report.dart';
import 'package:sonus_next/features/library/application/services/album_edition_management_service.dart';
import 'package:sonus_next/features/library/application/services/library_integrity_service.dart';
import 'package:sonus_next/features/library/data/daos/library_integrity_dao.dart';
import 'package:sonus_next/features/library/presentation/pages/library_health_page.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late LibraryIntegrityService service;
  final now = DateTime.utc(2026, 10, 25, 12);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    service = LibraryIntegrityService(
      dao: LibraryIntegrityDao(await appDatabase.database),
      editions: AlbumEditionManagementService(
        mutationRunner: SyncMutationTransactionRunner(appDatabase: appDatabase),
      ),
      fileExists: (_) async => true,
      now: () => now,
    );
  });

  tearDown(() => appDatabase.close());

  Future<void> seedAlbumWithoutPrimary(WidgetTester tester) async {
    await tester.runAsync(() async {
      const path = 'A/Album/One.mp3';
      await AtomicLibraryImporter(appDatabase: appDatabase).import(
        candidate: ImportCandidate(
          filePath: path,
          normalizedPath: path.toLowerCase(),
          discoveredAt: now,
        ),
        metadata: const AudioMetadata(
          title: 'One',
          artistName: 'Artist',
          albumTitle: 'Album',
          durationSeconds: 180,
          trackNumber: 1,
          discNumber: 1,
          isSingle: false,
          featuredArtists: [],
        ),
        now: now,
      );
      final db = await appDatabase.database;
      await db.update(DatabaseTables.albumEditions, {'is_primary': 0});
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('shows the report grouped by what it needs', (tester) async {
    await seedAlbumWithoutPrimary(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryHealthPage(
          service: service,
          importCounts: const ImportHealthCounts(
            imported: 1,
            relinked: 0,
            skipped: 0,
            failed: 0,
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Import Health Report'), findsOneWidget);
    expect(find.text('Safe corrections'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.textContaining('1 imported'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('library-health-apply-primaryEdition')),
      findsOneWidget,
    );
  });

  testWidgets('a correction is applied only after confirming', (tester) async {
    await seedAlbumWithoutPrimary(tester);

    await tester.pumpWidget(
      MaterialApp(home: LibraryHealthPage(service: service)),
    );
    await settle(tester);

    final apply = find.byKey(
      const ValueKey<String>('library-health-apply-primaryEdition'),
    );

    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    final db = await tester.runAsync(() => appDatabase.database);
    final stillNone = await tester.runAsync(
      () => db!.query(DatabaseTables.albumEditions, where: 'is_primary = 1'),
    );
    expect(stillNone, isEmpty);

    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('library-health-confirm')),
    );
    await settle(tester);

    final primary = await tester.runAsync(
      () => db!.query(DatabaseTables.albumEditions, where: 'is_primary = 1'),
    );
    expect(primary, hasLength(1));
    await settle(tester);
    expect(find.text('Nothing needs your attention.'), findsOneWidget);
  });
}
