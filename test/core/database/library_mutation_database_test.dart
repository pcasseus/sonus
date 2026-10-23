import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase appDatabase;

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('database transactions register as active mutations', () async {
    final entered = Completer<void>();
    final release = Completer<void>();

    final operation = appDatabase.transaction((transaction) async {
      entered.complete();
      await release.future;

      await transaction.execute(
        'CREATE TEMP TABLE IF NOT EXISTS coordinator_test (value INTEGER)',
      );
    });

    await entered.future;

    expect(appDatabase.mutationCoordinator.activeMutations, 1);

    release.complete();
    await operation;

    expect(appDatabase.mutationCoordinator.activeMutations, 0);
  });

  test('restore admission blocks new database transactions', () async {
    final coordinator = appDatabase.mutationCoordinator;

    final entered = Completer<void>();
    final release = Completer<void>();

    final exclusive = coordinator.runExclusiveRestore(() async {
      entered.complete();
      await release.future;
    });

    await entered.future;

    await expectLater(
      appDatabase.transaction((transaction) async {
        await transaction.rawQuery('SELECT 1');
      }),
      throwsA(isA<LibraryMutationUnavailable>()),
    );

    release.complete();
    await exclusive;

    await appDatabase.transaction((transaction) async {
      final result = await transaction.rawQuery('SELECT 1 AS value');
      expect(result.single['value'], 1);
    });
  });

  test('exclusive restore waits for an active SQLite writer', () async {
    final writerEntered = Completer<void>();
    final releaseWriter = Completer<void>();
    final restoreEntered = Completer<void>();

    final writer = appDatabase.transaction((transaction) async {
      await transaction.execute(
        'CREATE TABLE IF NOT EXISTS restore_race_test (value INTEGER)',
      );
      await transaction.insert('restore_race_test', {'value': 42});
      writerEntered.complete();
      await releaseWriter.future;
    });

    await writerEntered.future;

    final exclusive = appDatabase.mutationCoordinator.runExclusiveRestore(
      () async {
        restoreEntered.complete();
        final db = await appDatabase.database;
        final rows = await db.rawQuery('SELECT value FROM restore_race_test');
        expect(rows.single['value'], 42);
      },
    );

    expect(appDatabase.mutationCoordinator.isRestoreRequested, isTrue);
    expect(restoreEntered.isCompleted, isFalse);

    await expectLater(
      appDatabase.transaction((transaction) async {
        await transaction.rawQuery('SELECT 1');
      }),
      throwsA(isA<LibraryMutationUnavailable>()),
    );

    releaseWriter.complete();
    await writer;
    await exclusive;

    expect(restoreEntered.isCompleted, isTrue);
    expect(appDatabase.mutationCoordinator.activeMutations, 0);
    expect(appDatabase.mutationCoordinator.isRestoreRequested, isFalse);
  });

  test('writer drains successfully and permits another restore', () async {
    final writerEntered = Completer<void>();
    final releaseWriter = Completer<void>();

    final writer = appDatabase.transaction((transaction) async {
      await transaction.execute(
        'CREATE TABLE IF NOT EXISTS admission_timeout_test (value INTEGER)',
      );
      await transaction.insert('admission_timeout_test', {'value': 7});
      writerEntered.complete();
      await releaseWriter.future;
    });

    await writerEntered.future;

    final coordinator = appDatabase.mutationCoordinator;

    // This database's coordinator has the normal two-minute timeout.
    // Instead of waiting for it, verify the blocked state and allow
    // the writer to drain normally before retrying.
    final exclusive = coordinator.runExclusiveRestore(() async {
      final db = await appDatabase.database;
      final rows = await db.rawQuery(
        'SELECT value FROM admission_timeout_test',
      );
      expect(rows.single['value'], 7);
    });

    expect(coordinator.isRestoreRequested, isTrue);
    expect(coordinator.activeMutations, 1);

    releaseWriter.complete();
    await writer;
    await exclusive;

    await coordinator.runExclusiveRestore(() async {
      expect(coordinator.activeMutations, 0);
    });
  });
}
