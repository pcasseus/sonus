import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/media_file_binding.dart';
import '../mappers/media_file_binding_row_mapper.dart';

class MediaFileBindingDao {
  const MediaFileBindingDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(MediaFileBinding binding) async {
    await db.insert(
      DatabaseTables.mediaFileBindings,
      MediaFileBindingRowMapper.toRow(binding),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(MediaFileBinding binding) async {
    final count = await db.update(
      DatabaseTables.mediaFileBindings,
      MediaFileBindingRowMapper.toRow(binding),
      where: 'id = ?',
      whereArgs: [binding.id],
    );

    if (count != 1) {
      throw StateError('Media file binding not found: ${binding.id}');
    }
  }

  Future<MediaFileBinding?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.mediaFileBindings,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return MediaFileBindingRowMapper.fromRow(rows.single);
  }

  Future<List<MediaFileBinding>> findBySongId(String songId) async {
    final rows = await db.query(
      DatabaseTables.mediaFileBindings,
      where: 'song_id = ?',
      whereArgs: [songId],
      orderBy: 'is_available DESC, updated_at DESC',
    );

    return rows.map(MediaFileBindingRowMapper.fromRow).toList(growable: false);
  }

  Future<MediaFileBinding?> findByNormalizedPath(String normalizedPath) async {
    final rows = await db.query(
      DatabaseTables.mediaFileBindings,
      where: 'normalized_path = ?',
      whereArgs: [normalizedPath],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return MediaFileBindingRowMapper.fromRow(rows.single);
  }
}
