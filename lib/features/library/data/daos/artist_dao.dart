import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/artist.dart';
import '../mappers/artist_row_mapper.dart';

class ArtistDao {
  const ArtistDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(Artist artist) async {
    await db.insert(
      DatabaseTables.artists,
      ArtistRowMapper.toRow(artist),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(Artist artist) async {
    final count = await db.update(
      DatabaseTables.artists,
      ArtistRowMapper.toRow(artist),
      where: 'id = ?',
      whereArgs: [artist.id],
    );

    if (count != 1) {
      throw StateError('Artist not found: ${artist.id}');
    }
  }

  Future<void> delete(String id) async {
    final count = await db.delete(
      DatabaseTables.artists,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (count != 1) {
      throw StateError('Artist not found: $id');
    }
  }

  Future<Artist?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.artists,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return ArtistRowMapper.fromRow(rows.single);
  }

  Future<List<Artist>> findAll() async {
    final rows = await db.query(
      DatabaseTables.artists,
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map(ArtistRowMapper.fromRow).toList(growable: false);
  }
}
