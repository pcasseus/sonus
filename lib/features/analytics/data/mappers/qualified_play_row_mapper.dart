import '../../domain/entities/qualified_play.dart';

abstract final class QualifiedPlayRowMapper {
  static QualifiedPlay fromRow(Map<String, Object?> row) {
    return QualifiedPlay(
      id: row['id']! as String,
      playbackSessionId: row['playback_session_id']! as String,
      userId: row['user_id'] as String?,
      songId: row['song_id']! as String,
      artistId: row['artist_id']! as String,
      albumId: row['album_id']! as String,
      albumEditionId: row['album_edition_id']! as String,
      qualifiedAt: DateTime.parse(row['qualified_at']! as String),
      listenedDuration: Duration(
        milliseconds: row['listened_duration_ms']! as int,
      ),
      trackDuration: Duration(milliseconds: row['track_duration_ms']! as int),
      createdAt: DateTime.parse(row['created_at']! as String),
    );
  }

  static Map<String, Object?> toRow(QualifiedPlay play) {
    return <String, Object?>{
      'id': play.id,
      'playback_session_id': play.playbackSessionId,
      'user_id': play.userId,
      'song_id': play.songId,
      'artist_id': play.artistId,
      'album_id': play.albumId,
      'album_edition_id': play.albumEditionId,
      'qualified_at': play.qualifiedAt.toUtc().toIso8601String(),
      'listened_duration_ms': play.listenedDuration.inMilliseconds,
      'track_duration_ms': play.trackDuration.inMilliseconds,
      'created_at': play.createdAt.toUtc().toIso8601String(),
    };
  }
}
