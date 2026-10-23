import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/import/application/services/import_duration_repair_service.dart';
import 'package:sonus_next/features/import/presentation/scopes/import_scope.dart';
import 'package:sonus_next/features/library/application/services/malformed_artist_identity_repair_scan_service.dart';
import 'package:sonus_next/features/library/application/services/malformed_artist_identity_repair_service.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_artist_repository.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

import '../../../../support/library_seed.dart';

void main() {
  sqfliteFfiInit();

  late List<String> messages;
  late List<int> levels;
  late List<StackTrace?> stackTraces;

  setUp(() {
    messages = [];
    levels = [];
    stackTraces = [];
  });

  void log(String message, {required int level, StackTrace? stackTrace}) {
    messages.add(message);
    levels.add(level);
    stackTraces.add(stackTrace);
  }

  group('startup maintenance stage', () {
    test('a successful stage completes and logs nothing', () async {
      var runs = 0;

      final completed = await runStartupMaintenanceStage(
        'artist identity repair',
        () async => runs++,
        log: log,
      );

      expect(completed, isTrue);
      expect(runs, 1);
      expect(messages, isEmpty);
    });

    test('a restore rejection is reported as stopped, once', () async {
      var runs = 0;

      final completed = await runStartupMaintenanceStage(
        'artist identity repair',
        () async {
          runs++;
          throw const LibraryMutationUnavailable('restoring user-1 library');
        },
        log: log,
      );

      expect(completed, isFalse);
      expect(runs, 1);
      expect(messages, [
        'Startup artist identity repair stopped: library restoration is '
            'active.',
      ]);
      expect(levels, [800]);
    });

    test('an ordinary failure is reported by type only', () async {
      final completed = await runStartupMaintenanceStage(
        'artist identity repair',
        () async =>
            throw StateError('Artist "Private Name" at /private/music/x.mp3'),
        log: log,
      );

      expect(completed, isFalse);
      expect(messages, ['Startup artist identity repair failed: StateError.']);
      expect(levels, [1000]);
      expect(stackTraces.single, isNotNull);
      expect(messages.single, isNot(contains('Private')));
    });

    test('a late asynchronous failure never escapes an unawaited stage', () {
      final uncaught = <Object>[];
      final finished = Completer<bool>();

      runZonedGuarded(() {
        unawaited(
          runStartupMaintenanceStage('artist identity repair', () async {
            await Future<void>.value();
            throw StateError('late failure');
          }, log: log).then(finished.complete),
        );
      }, (error, _) => uncaught.add(error));

      return finished.future.then((completed) async {
        await pumpEventQueue();

        expect(completed, isFalse);
        expect(uncaught, isEmpty);
        expect(messages, [
          'Startup artist identity repair failed: StateError.',
        ]);
      });
    });
  });

  group('artist identity repair as a startup stage', () {
    late AppDatabase appDatabase;
    late MalformedArtistIdentityRepairScanService scan;
    late String malformedId;

    setUp(() async {
      appDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final db = await appDatabase.database;
      final now = DateTime.utc(2026, 10, 3, 12);

      final clean = EntityFactory.createArtist(name: 'Beyonce', now: now);
      final malformed = EntityFactory.createArtist(
        name: 'Beyonce [Ft. Jack White]',
        now: now,
      );
      await ArtistDao(db).insert(clean);
      await ArtistDao(db).insert(malformed);
      malformedId = malformed.id;

      // Composed as ImportScope composes it.
      scan = MalformedArtistIdentityRepairScanService(
        artistRepository: SqliteArtistRepository(ArtistDao(db)),
        repairArtist: MalformedArtistIdentityRepairService(
          mutationRunner: SyncMutationTransactionRunner(
            appDatabase: appDatabase,
          ),
        ).repairArtist,
      );
    });

    tearDown(() async {
      await appDatabase.close();
    });

    test('is stopped by a restore, then repairs once it has ended', () async {
      final db = await appDatabase.database;
      final before = await snapshotDatabase(db);
      final entered = Completer<void>();
      final release = Completer<void>();
      final restore = appDatabase.mutationCoordinator.runExclusiveRestore(
        () async {
          entered.complete();
          await release.future;
        },
      );
      await entered.future;

      final bool stopped;
      try {
        stopped = await runStartupMaintenanceStage(
          'artist identity repair',
          () => scan.repairAll(userId: null),
          log: log,
        );
      } finally {
        release.complete();
        await restore;
      }

      expect(stopped, isFalse);
      expect(messages, [
        'Startup artist identity repair stopped: library restoration is '
            'active.',
      ]);
      expect(await snapshotDatabase(db), before);
      expect(appDatabase.mutationCoordinator.activeMutations, 0);

      final completed = await runStartupMaintenanceStage(
        'artist identity repair',
        () => scan.repairAll(userId: null),
        log: log,
      );

      expect(completed, isTrue);
      expect(messages, hasLength(1));
      expect(await ArtistDao(db).findById(malformedId), isNull);
    });
  });

  group('duration repair diagnostics', () {
    ImportDurationRepairSummary summary({required int failed}) {
      return ImportDurationRepairSummary(
        examined: 5,
        repaired: 2,
        skipped: 3 - failed,
        failed: failed,
      );
    }

    test('ordinary failures are reported as an aggregate', () async {
      await repairDurationsReportingFailures(
        () async => summary(failed: 2),
        log: log,
      );

      expect(messages, [
        'Startup duration repair could not repair 2 of 5 songs.',
      ]);
      expect(levels, [900]);
    });

    test('a clean repair reports nothing', () async {
      await repairDurationsReportingFailures(
        () async => summary(failed: 0),
        log: log,
      );

      expect(messages, isEmpty);
    });

    test(
      'an interrupted repair stops the chain before review cleanup',
      () async {
        var cleanups = 0;

        await runStartupDurationMaintenance(
          repairDurations: () => repairDurationsReportingFailures(
            () async => throw const LibraryMutationUnavailable('restoring'),
            log: log,
          ),
          cleanupReviews: () async => cleanups++,
          log: log,
        );

        expect(cleanups, 0);
        expect(messages, [
          'Startup duration repair stopped: library restoration is active.',
        ]);
      },
    );
  });
}
