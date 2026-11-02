import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_tables.dart';
import '../../domain/entities/album_edition_track.dart';
import '../mappers/album_edition_track_row_mapper.dart';
import 'edition_track_order.dart';

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
    final rows = await db.rawQuery(
      '''
      SELECT aet.*
      FROM ${DatabaseTables.albumEditionTracks} aet
      WHERE aet.album_edition_id = ?
      ORDER BY ${editionTrackOrderBy('aet')}
      ''',
      [editionId],
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

  /// Songs listed on an edition other than their home edition (read only).
  Future<List<String>> songIdsListedAwayFromHome() async {
    final rows = await db.rawQuery('''
      SELECT DISTINCT aet.song_id AS song_id
      FROM ${DatabaseTables.albumEditionTracks} aet
      INNER JOIN ${DatabaseTables.songs} s
        ON s.id = aet.song_id
      WHERE s.album_edition_id IS NULL
        OR aet.album_edition_id <> s.album_edition_id
      ORDER BY aet.song_id ASC
    ''');

    return [for (final row in rows) row['song_id'] as String];
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
