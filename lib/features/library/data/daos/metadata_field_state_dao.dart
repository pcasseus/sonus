import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/metadata/metadata_field_state.dart';
import '../mappers/metadata_field_state_row_mapper.dart';

class MetadataFieldStateDao {
  const MetadataFieldStateDao(this.db);

  final DatabaseExecutor db;

  Future<MetadataFieldState?> find({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
  }) async {
    final rows = await db.query(
      DatabaseTables.metadataFieldStates,
      where: 'entity_type = ? AND entity_id = ? AND field_name = ?',
      whereArgs: [entityType.name, entityId, fieldName],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return MetadataFieldStateRowMapper.fromRow(rows.single);
  }

  Future<List<MetadataFieldState>> findByEntity({
    required MetadataEntityType entityType,
    required String entityId,
  }) async {
    final rows = await db.query(
      DatabaseTables.metadataFieldStates,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType.name, entityId],
      orderBy: 'field_name COLLATE NOCASE ASC',
    );

    return rows
        .map(MetadataFieldStateRowMapper.fromRow)
        .toList(growable: false);
  }

  Future<void> upsert(MetadataFieldState state) async {
    await db.insert(
      DatabaseTables.metadataFieldStates,
      MetadataFieldStateRowMapper.toRow(state),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete({
    required MetadataEntityType entityType,
    required String entityId,
    required String fieldName,
  }) async {
    await db.delete(
      DatabaseTables.metadataFieldStates,
      where: 'entity_type = ? AND entity_id = ? AND field_name = ?',
      whereArgs: [entityType.name, entityId, fieldName],
    );
  }

  Future<void> deleteByEntity({
    required MetadataEntityType entityType,
    required String entityId,
  }) async {
    await db.delete(
      DatabaseTables.metadataFieldStates,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType.name, entityId],
    );
  }
}
