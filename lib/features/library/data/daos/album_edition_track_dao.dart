import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/album_edition_track.dart';
import '../mappers/album_edition_track_row_mapper.dart';

class AlbumEditionTrackDao {
  const AlbumEditionTrackDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(AlbumEditionTrack membership) async {
    await db.insert(
      DatabaseTables.albumEditionTracks,
      AlbumEditionTrackRowMapper.toRow(membership),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(AlbumEditionTrack membership) async {
    final count = await db.update(
      DatabaseTables.albumEditionTracks,
      AlbumEditionTrackRowMapper.toRow(membership),
      where: 'album_edition_id = ? AND song_id = ?',
      whereArgs: [membership.albumEditionId, membership.songId],
    );

    if (count != 1) {
      throw StateError(
        'Album edition track not found: '
        '${membership.albumEditionId}/${membership.songId}',
      );
    }
  }

  Future<List<AlbumEditionTrack>> findByEditionId(String editionId) async {
    final rows = await db.query(
      DatabaseTables.albumEditionTracks,
      where: 'album_edition_id = ?',
      whereArgs: [editionId],
      orderBy:
          'sort_position ASC, disc_number ASC, track_number ASC, song_id ASC',
    );

    return rows.map(AlbumEditionTrackRowMapper.fromRow).toList(growable: false);
  }

  Future<List<AlbumEditionTrack>> findBySongId(String songId) async {
    final rows = await db.query(
      DatabaseTables.albumEditionTracks,
      where: 'song_id = ?',
      whereArgs: [songId],
      orderBy: 'album_edition_id ASC, sort_position ASC',
    );

    return rows.map(AlbumEditionTrackRowMapper.fromRow).toList(growable: false);
  }

  Future<void> delete({
    required String editionId,
    required String songId,
  }) async {
    await db.delete(
      DatabaseTables.albumEditionTracks,
      where: 'album_edition_id = ? AND song_id = ?',
      whereArgs: [editionId, songId],
    );
  }
}
