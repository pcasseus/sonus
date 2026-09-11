import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/import/data/daos/import_batch_dao.dart';
import 'package:sonus_next/features/import/domain/entities/import_batch_record.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late ImportBatchDao dao;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    dao = ImportBatchDao(await appDatabase.database);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('inserts and finds import batch by id', () async {
    final batch = ImportBatchRecord(
      id: 'batch_insert',
      status: ImportBatchRecordStatus.pending,
      totalCount: 3,
      importedCount: 0,
      relinkedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      createdAt: DateTime.utc(2026, 9, 10),
    );

    await dao.insert(batch);

    final result = await dao.findById(batch.id);

    expect(result, isNotNull);
    expect(result!.id, batch.id);
    expect(result.status, ImportBatchRecordStatus.pending);
    expect(result.totalCount, 3);
  });

  test('updates existing import batch', () async {
    final batch = ImportBatchRecord(
      id: 'batch_update',
      status: ImportBatchRecordStatus.pending,
      totalCount: 3,
      importedCount: 0,
      relinkedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      createdAt: DateTime.utc(2026, 9, 10),
    );

    await dao.insert(batch);

    final updated = batch.copyWith(
      status: ImportBatchRecordStatus.running,
      importedCount: 1,
      startedAt: DateTime.utc(2026, 9, 10, 12),
    );

    await dao.update(updated);

    final result = await dao.findById(batch.id);

    expect(result, isNotNull);
    expect(result!.status, ImportBatchRecordStatus.running);
    expect(result.importedCount, 1);
    expect(result.startedAt, DateTime.utc(2026, 9, 10, 12));
  });

  test('throws when updating missing import batch', () async {
    final batch = ImportBatchRecord(
      id: 'batch_missing',
      status: ImportBatchRecordStatus.pending,
      totalCount: 1,
      importedCount: 0,
      relinkedCount: 0,
      skippedCount: 0,
      failedCount: 0,
      createdAt: DateTime.utc(2026, 9, 10),
    );

    await expectLater(dao.update(batch), throwsA(isA<StateError>()));
  });

  test('findAll returns newest batches first', () async {
    await dao.insert(
      ImportBatchRecord(
        id: 'batch_old',
        status: ImportBatchRecordStatus.pending,
        totalCount: 1,
        importedCount: 0,
        relinkedCount: 0,
        skippedCount: 0,
        failedCount: 0,
        createdAt: DateTime.utc(2026, 9, 9),
      ),
    );

    await dao.insert(
      ImportBatchRecord(
        id: 'batch_new',
        status: ImportBatchRecordStatus.pending,
        totalCount: 1,
        importedCount: 0,
        relinkedCount: 0,
        skippedCount: 0,
        failedCount: 0,
        createdAt: DateTime.utc(2026, 9, 10),
      ),
    );

    final results = await dao.findAll();

    expect(results.map((batch) => batch.id).toList(), [
      'batch_new',
      'batch_old',
    ]);
  });
}
