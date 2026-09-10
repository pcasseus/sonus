import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/album_edition.dart';
import '../mappers/album_edition_row_mapper.dart';

class AlbumEditionDao {
  const AlbumEditionDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(AlbumEdition edition) async {
    await db.insert(
      DatabaseTables.albumEditions,
      AlbumEditionRowMapper.toRow(edition),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(AlbumEdition edition) async {
    final count = await db.update(
      DatabaseTables.albumEditions,
      AlbumEditionRowMapper.toRow(edition),
      where: 'id = ?',
      whereArgs: [edition.id],
    );

    if (count != 1) {
      throw StateError('Album edition not found: ${edition.id}');
    }
  }

  Future<AlbumEdition?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.albumEditions,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return AlbumEditionRowMapper.fromRow(rows.single);
  }

  Future<List<AlbumEdition>> findByAlbumId(String albumId) async {
    final rows = await db.query(
      DatabaseTables.albumEditions,
      where: 'album_id = ?',
      whereArgs: [albumId],
      orderBy: 'is_primary DESC, release_date ASC, title COLLATE NOCASE ASC',
    );

    return rows.map(AlbumEditionRowMapper.fromRow).toList(growable: false);
  }
}
