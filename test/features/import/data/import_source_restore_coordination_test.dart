import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/import/data/daos/import_source_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_import_source_repository.dart';
import 'package:sonus_next/features/import/domain/entities/import_source.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SqliteImportSourceRepository repository;

  final createdAt = DateTime.utc(2026, 10, 23);

  ImportSource source(String id) => ImportSource(
    id: id,
    rootPath: 'C:/Music/$id',
    normalizedRootPath: 'c:/music/$id',
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    repository = SqliteImportSourceRepository(
      ImportSourceDao(await appDatabase.database),
      appDatabase: appDatabase,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('normal source creation and update succeed', () async {
    final original = source('normal');

    await repository.create(original);

    final scannedAt = createdAt.add(const Duration(minutes: 5));

    await repository.save(
      original.copyWith(lastScannedAt: scannedAt, updatedAt: scannedAt),
    );

    expect((await repository.getById(original.id))?.lastScannedAt, scannedAt);
  });

  test('restore rejects source create and save', () async {
    final existing = source('existing');
    await repository.create(existing);

    final coordinator = appDatabase.mutationCoordinator;
    final entered = Completer<void>();
    final release = Completer<void>();

    final exclusive = coordinator.runExclusiveRestore(() async {
      entered.complete();
      await release.future;
    });

    await entered.future;

    try {
      await expectLater(
        repository.create(source('blocked')),
        throwsA(isA<LibraryMutationUnavailable>()),
      );

      await expectLater(
        repository.save(
          existing.copyWith(
            lastScannedAt: createdAt.add(const Duration(hours: 1)),
          ),
        ),
        throwsA(isA<LibraryMutationUnavailable>()),
      );

      expect(await repository.getById('blocked'), isNull);

      final persisted = await repository.getById(existing.id);
      expect(persisted?.lastScannedAt, isNull);
    } finally {
      release.complete();
      await exclusive;
    }

    expect(coordinator.isRestoreRequested, isFalse);

    await repository.create(source('allowed'));

    expect(await repository.getById('allowed'), isNotNull);
  });
}
