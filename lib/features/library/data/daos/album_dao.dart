import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/album.dart';
import '../mappers/album_row_mapper.dart';

class AlbumDao {
  const AlbumDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(Album album) async {
    await db.insert(
      DatabaseTables.albums,
      AlbumRowMapper.toRow(album),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(Album album) async {
    final count = await db.update(
      DatabaseTables.albums,
      AlbumRowMapper.toRow(album),
      where: 'id = ?',
      whereArgs: [album.id],
    );

    if (count != 1) {
      throw StateError('Album not found: ${album.id}');
    }
  }

  Future<Album?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.albums,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return AlbumRowMapper.fromRow(rows.single);
  }

  Future<List<Album>> findAll() async {
    final rows = await db.query(
      DatabaseTables.albums,
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );

    return rows.map(AlbumRowMapper.fromRow).toList(growable: false);
  }

  Future<List<Album>> findRecentlyAdded(int limit) async {
    if (limit <= 0) {
      return const [];
    }

    final rows = await db.query(
      DatabaseTables.albums,
      orderBy: 'created_at DESC, title COLLATE NOCASE ASC, id ASC',
      limit: limit,
    );

    return rows.map(AlbumRowMapper.fromRow).toList(growable: false);
  }

  Future<List<Album>> findByArtistId(String artistId) async {
    final rows = await db.query(
      DatabaseTables.albums,
      where: 'artist_id = ?',
      whereArgs: [artistId],
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );

    return rows.map(AlbumRowMapper.fromRow).toList(growable: false);
  }
}
