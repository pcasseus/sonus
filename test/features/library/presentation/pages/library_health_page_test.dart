import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/account/domain/entities/account_user.dart';
import 'package:sonus_next/features/account/domain/repositories/account_repository.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/library/application/models/library_health_report.dart';
import 'package:sonus_next/features/library/application/services/album_edition_management_service.dart';
import 'package:sonus_next/features/library/application/services/library_integrity_service.dart';
import 'package:sonus_next/features/library/data/daos/library_integrity_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
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
      const ValueKey<String>('library-health-review-releaseFormats'),
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

  group('SN-50 #4: re-send edition placements', () {
    Widget signedIn(Widget home) => ChangeNotifierProvider<AccountController>(
      create: (_) =>
          AccountController(repository: const _SignedInAccountRepository()),
      child: MaterialApp(home: home),
    );

    final tile = find.byKey(
      const ValueKey<String>('library-health-resend-placements'),
    );
    final action = find.byKey(
      const ValueKey<String>('library-health-resend-placements-action'),
    );

    Future<void> reveal(WidgetTester tester) async {
      final report = find.byKey(
        const ValueKey<String>('library-health-report'),
      );
      await settle(tester, until: report);
      await tester.scrollUntilVisible(
        action,
        200,
        scrollable: find
            .descendant(of: report, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
    }

    Future<List<Map<String, Object?>>> queuedFor(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          final db = await appDatabase.database;
          return db.query(
            DatabaseTables.syncOutbox,
            where: 'user_id = ?',
            whereArgs: ['user-1'],
          );
        }))!;

    testWidgets('signed out, it is not offered', (tester) async {
      await seedAlbumWithoutPrimary(tester);

      await tester.pumpWidget(
        MaterialApp(home: LibraryHealthPage(service: service)),
      );
      await settle(
        tester,
        until: find.byKey(const ValueKey<String>('library-health-report')),
      );

      // Scroll to the very end so a lazily built tile would exist.
      final report = find.byKey(
        const ValueKey<String>('library-health-report'),
      );
      await tester.fling(report, const Offset(0, -5000), 3000);
      await tester.pumpAndSettle();
      expect(find.text('Verified'), findsOneWidget);
      expect(tile, findsNothing);
      expect(find.text('Sync'), findsNothing);
    });

    testWidgets('signed in, it queues only after confirming and says how '
        'many', (tester) async {
      await seedAlbumWithoutPrimary(tester);
      await tester.runAsync(() async {
        final db = await appDatabase.database;
        final home = (await db.query(DatabaseTables.albumEditions)).single;
        await service.editions.createEdition(
          albumId: home['album_id']! as String,
          title: 'Album (Deluxe)',
          type: AlbumEditionType.deluxe,
          includeSongsFrom: home['id']! as String,
          now: now,
        );
      });

      await tester.pumpWidget(signedIn(LibraryHealthPage(service: service)));
      await reveal(tester);

      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Re-send placements?'), findsOneWidget);
      expect(
        find.text(
          'Songs listed on more than one edition will be sent with the next '
          "sync. This device's edition placements will replace the "
          'corresponding placements currently stored in your cloud library. '
          'This may overwrite placement changes made on another device. Your '
          'songs, audio files and listening history will not be deleted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await queuedFor(tester), isEmpty);

      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('library-health-resend-confirm')),
      );
      final done = find.text('1 song will be sent with the next sync.');
      await settle(tester, until: done);

      expect(done, findsOneWidget);
      final rows = await queuedFor(tester);
      expect(rows, hasLength(1));
      expect(rows.single['entity_type'], 'song');
    });

    testWidgets('with nothing listed away from home it says so', (
      tester,
    ) async {
      await seedAlbumWithoutPrimary(tester);

      await tester.pumpWidget(signedIn(LibraryHealthPage(service: service)));
      await reveal(tester);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('library-health-resend-confirm')),
      );
      final none = find.text('No songs are listed on more than one edition.');
      await settle(tester, until: none);

      expect(none, findsOneWidget);
      expect(await queuedFor(tester), isEmpty);
    });
  });
}

class _SignedInAccountRepository implements AccountRepository {
  const _SignedInAccountRepository();

  static const _user = AccountUser(id: 'user-1', email: 'test@example.com');

  @override
  AccountUser? get currentUser => _user;

  @override
  Stream<AccountUser?> watchAuthState() => const Stream.empty();

  @override
  Future<AccountUser?> signInWithGoogle() async => _user;

  @override
  Future<void> signOut() async {}
}
