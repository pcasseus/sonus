import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/song.dart';
import '../mappers/song_row_mapper.dart';

class SongDao {
  const SongDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(Song song) async {
    await db.insert(
      DatabaseTables.songs,
      SongRowMapper.toRow(song),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(Song song) async {
    final count = await db.update(
      DatabaseTables.songs,
      SongRowMapper.toRow(song),
      where: 'id = ?',
      whereArgs: [song.id],
    );

    if (count != 1) {
      throw StateError('Song not found: ${song.id}');
    }
  }

  Future<Song?> findById(String id) async {
    final rows = await db.query(
      DatabaseTables.songs,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return SongRowMapper.fromRow(rows.single);
  }

  Future<List<Song>> findAll() async {
    final rows = await db.query(
      DatabaseTables.songs,
      orderBy: 'title COLLATE NOCASE ASC, id ASC',
    );

    return rows.map(SongRowMapper.fromRow).toList(growable: false);
  }

  Future<List<Song>> findRecentlyAdded(int limit) async {
    if (limit <= 0) {
      return const [];
    }

    final rows = await db.query(
      DatabaseTables.songs,
      orderBy: 'created_at DESC, title COLLATE NOCASE ASC, id ASC',
      limit: limit,
    );

    return rows.map(SongRowMapper.fromRow).toList(growable: false);
  }

  Future<List<Song>> findByAlbumId(String albumId) async {
    final rows = await db.query(
      DatabaseTables.songs,
      where: 'album_id = ?',
      whereArgs: [albumId],
      orderBy: 'track_number ASC, title COLLATE NOCASE ASC, id ASC',
    );

    return rows.map(SongRowMapper.fromRow).toList(growable: false);
  }

  Future<List<Song>> findByEditionId(String editionId) async {
    final rows = await db.query(
      DatabaseTables.songs,
      where: 'album_edition_id = ?',
      whereArgs: [editionId],
      orderBy: 'track_number ASC, title COLLATE NOCASE ASC, id ASC',
    );

    return rows.map(SongRowMapper.fromRow).toList(growable: false);
  }

  Future<List<Song>> findByArtistId(String artistId) async {
    final rows = await db.query(
      DatabaseTables.songs,
      where: 'artist_id = ?',
      whereArgs: [artistId],
      orderBy:
          'album_id ASC, track_number ASC, title COLLATE NOCASE ASC, id ASC',
    );

    return rows.map(SongRowMapper.fromRow).toList(growable: false);
  }
}
