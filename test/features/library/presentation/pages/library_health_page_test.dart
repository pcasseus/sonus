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

  Future<void> seedAlbumWithoutPrimary(
    WidgetTester tester, {
    bool statedFormat = true,
  }) async {
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
      if (statedFormat) {
        // A one-song album might be a Single; stating its format keeps the
        // report about the edition only.
        final album = (await db.query(DatabaseTables.albums)).single;
        await db.insert(DatabaseTables.albumReleaseClassifications, {
          'album_id': album['id'],
          'format': 'album',
          'format_authority': 'manual',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }
    });
  }

  /// Lets the real database work finish. With [until], keeps going (up to
  /// about 5s of real time) until it is on screen, so a slow, loaded run
  /// doesn't tap before the report has arrived.
  Future<void> settle(WidgetTester tester, {Finder? until}) async {
    for (var i = 0; i < 250; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (i >= 4 && (until == null || until.evaluate().isNotEmpty)) return;
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
    await settle(
      tester,
      until: find.byKey(
        const ValueKey<String>('library-health-apply-primaryEdition'),
      ),
    );

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
    final apply = find.byKey(
      const ValueKey<String>('library-health-apply-primaryEdition'),
    );
    await settle(tester, until: apply);

    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await settle(tester, until: apply);

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
    final healthy = find.text('Nothing needs your attention.');
    await settle(tester, until: healthy);
    expect(healthy, findsOneWidget);
  });

  testWidgets('releases that might be Singles are listed for review', (
    tester,
  ) async {
    await seedAlbumWithoutPrimary(tester, statedFormat: false);

    await tester.pumpWidget(
      MaterialApp(home: LibraryHealthPage(service: service)),
    );
    final review = find.byKey(
      const ValueKey<String>('library-health-review-formats'),
    );
    await settle(tester, until: review);

    expect(find.text('Needs your review'), findsOneWidget);
    expect(find.textContaining('1 release might be a Single'), findsOneWidget);

    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.text('Choose Single, EP or Album'), findsOneWidget);
    expect(find.text('Album'), findsOneWidget);
    expect(find.text('Artist · 1 song'), findsOneWidget);
  });
}
