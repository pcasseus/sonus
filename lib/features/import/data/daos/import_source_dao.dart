import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/import_source.dart';

class ImportSourceDao {
  const ImportSourceDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(ImportSource source) async {
    await db.insert(
      DatabaseTables.importSources,
      _toRow(source),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(ImportSource source) async {
    final count = await db.update(
      DatabaseTables.importSources,
      _toRow(source),
      where: 'id = ?',
      whereArgs: [source.id],
    );

    if (count != 1) {
      throw StateError('Import source not found: ${source.id}');
    }
  }

  Future<ImportSource?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.importSources,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _fromRow(rows.single);
  }

  Future<ImportSource?> findByNormalizedRootPath(
    String normalizedRootPath,
  ) async {
    final rows = await db.query(
      DatabaseTables.importSources,
      where: 'normalized_root_path = ?',
      whereArgs: [normalizedRootPath],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _fromRow(rows.single);
  }

  Future<List<ImportSource>> findAll() async {
    final rows = await db.query(
      DatabaseTables.importSources,
      orderBy: 'created_at ASC, id ASC',
    );

    return rows.map(_fromRow).toList(growable: false);
  }

  Map<String, Object?> _toRow(ImportSource source) {
    return {
      'id': source.id,
      'root_path': source.rootPath,
      'normalized_root_path': source.normalizedRootPath,
      'last_scanned_at': source.lastScannedAt?.toUtc().toIso8601String(),
      'created_at': source.createdAt.toUtc().toIso8601String(),
      'updated_at': source.updatedAt.toUtc().toIso8601String(),
    };
  }

  ImportSource _fromRow(Map<String, Object?> row) {
    return ImportSource(
      id: row['id'] as String,
      rootPath: row['root_path'] as String,
      normalizedRootPath: row['normalized_root_path'] as String,
      lastScannedAt: row['last_scanned_at'] == null
          ? null
          : DateTime.parse(row['last_scanned_at'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
