import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/import_batch_record.dart';
import '../mappers/import_batch_record_row_mapper.dart';

class ImportBatchDao {
  const ImportBatchDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(ImportBatchRecord batch) async {
    await db.insert(
      DatabaseTables.importBatches,
      ImportBatchRecordRowMapper.toRow(batch),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(ImportBatchRecord batch) async {
    final count = await db.update(
      DatabaseTables.importBatches,
      ImportBatchRecordRowMapper.toRow(batch),
      where: 'id = ?',
      whereArgs: [batch.id],
    );

    if (count != 1) {
      throw StateError('Import batch not found: ${batch.id}');
    }
  }

  Future<ImportBatchRecord?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.importBatches,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return ImportBatchRecordRowMapper.fromRow(rows.single);
  }

  Future<List<ImportBatchRecord>> findAll() async {
    final rows = await db.query(
      DatabaseTables.importBatches,
      orderBy: 'created_at DESC',
    );

    return rows.map(ImportBatchRecordRowMapper.fromRow).toList(growable: false);
  }
}
