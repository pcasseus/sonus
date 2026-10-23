import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/import/data/daos/import_batch_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_import_batch_repository.dart';
import 'package:sonus_next/features/import/domain/entities/import_batch_record.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SqliteImportBatchRepository repository;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    repository = SqliteImportBatchRepository(
      ImportBatchDao(await appDatabase.database),
      appDatabase: appDatabase,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('creates saves and retrieves import batch', () async {
    final batch = ImportBatchRecord(
      id: 'batch_repository',
      status: ImportBatchRecordStatus.pending,
      totalCount: 2,
      importedCount: 0,
      relinkedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      createdAt: DateTime.utc(2026, 9, 10),
    );

    await repository.create(batch);

    final created = await repository.getById(batch.id);

    expect(created, isNotNull);
    expect(created!.status, ImportBatchRecordStatus.pending);

    final completed = batch.copyWith(
      status: ImportBatchRecordStatus.completed,
      importedCount: 1,
      skippedCount: 1,
      startedAt: DateTime.utc(2026, 9, 10, 12),
      completedAt: DateTime.utc(2026, 9, 10, 12, 5),
    );

    await repository.save(completed);

    final saved = await repository.getById(batch.id);

    expect(saved, isNotNull);
    expect(saved!.status, ImportBatchRecordStatus.completed);
    expect(saved.importedCount, 1);
    expect(saved.skippedCount, 1);
    expect(saved.isComplete, isTrue);

    final all = await repository.getAll();

    expect(all, hasLength(1));
    expect(all.single.id, batch.id);
  });

  test('restore admission rejects batch create and save', () async {
    final existing = ImportBatchRecord(
      id: 'batch_protected',
      status: ImportBatchRecordStatus.pending,
      totalCount: 1,
      importedCount: 0,
      relinkedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      createdAt: DateTime.utc(2026, 9, 10),
    );

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
        repository.create(
          ImportBatchRecord(
            id: 'batch_rejected',
            status: ImportBatchRecordStatus.pending,
            totalCount: 0,
            importedCount: 0,
            relinkedCount: 0,
            skippedCount: 0,
            failedCount: 0,
            createdAt: DateTime.utc(2026, 9, 11),
          ),
        ),
        throwsA(isA<LibraryMutationUnavailable>()),
      );

      await expectLater(
        repository.save(
          existing.copyWith(
            status: ImportBatchRecordStatus.running,
            startedAt: DateTime.utc(2026, 9, 10, 12),
          ),
        ),
        throwsA(isA<LibraryMutationUnavailable>()),
      );

      expect(await repository.getById('batch_rejected'), isNull);
      expect(
        (await repository.getById(existing.id))?.status,
        ImportBatchRecordStatus.pending,
      );
    } finally {
      release.complete();
      await exclusive;
    }

    await repository.save(
      existing.copyWith(
        status: ImportBatchRecordStatus.running,
        startedAt: DateTime.utc(2026, 9, 10, 12),
      ),
    );

    expect(
      (await repository.getById(existing.id))?.status,
      ImportBatchRecordStatus.running,
    );
  });
  test('returns null for unknown import batch', () async {
    final result = await repository.getById('batch_missing');

    expect(result, isNull);
  });
}
