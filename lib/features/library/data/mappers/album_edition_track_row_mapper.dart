import '../../domain/entities/album_edition_track.dart';

abstract final class AlbumEditionTrackRowMapper {
  static Map<String, Object?> toRow(AlbumEditionTrack membership) {
    return {
      'album_edition_id': membership.albumEditionId,
      'song_id': membership.songId,
      'disc_number': membership.discNumber,
      'track_number': membership.trackNumber,
      'sort_position': membership.sortPosition,
      'created_at': membership.createdAt.toUtc().toIso8601String(),
      'updated_at': membership.updatedAt.toUtc().toIso8601String(),
    };
  }

  static AlbumEditionTrack fromRow(Map<String, Object?> row) {
    return AlbumEditionTrack(
      albumEditionId: row['album_edition_id'] as String,
      songId: row['song_id'] as String,
      discNumber: row['disc_number'] as int? ?? 1,
      trackNumber: row['track_number'] as int? ?? 0,
      sortPosition: row['sort_position'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
