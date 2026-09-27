import '../../domain/entities/playback_session.dart';

abstract final class PlaybackSessionRowMapper {
  static PlaybackSession fromRow(Map<String, Object?> row) {
    return PlaybackSession(
      id: row['id']! as String,
      userId: row['user_id'] as String?,
      songId: row['song_id']! as String,
      artistId: row['artist_id']! as String,
      albumId: row['album_id']! as String,
      albumEditionId: row['album_edition_id']! as String,
      songTitle: row['song_title']! as String,
      artistName: row['artist_name']! as String,
      albumTitle: row['album_title']! as String,
      albumEditionTitle: row['album_edition_title']! as String,
      startedAt: DateTime.parse(row['started_at']! as String),
      endedAt: row['ended_at'] == null
          ? null
          : DateTime.parse(row['ended_at']! as String),
      listenedDuration: Duration(
        milliseconds: row['listened_duration_ms']! as int,
      ),
      trackDuration: Duration(milliseconds: row['track_duration_ms']! as int),
      finalPosition: Duration(milliseconds: row['final_position_ms']! as int),
      endReason: row['end_reason'] == null
          ? null
          : PlaybackSessionEndReason.values.firstWhere(
              (value) => value.name == row['end_reason'],
            ),
      sourceContext: row['source_context'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }

  static Map<String, Object?> toRow(PlaybackSession session) {
    return <String, Object?>{
      'id': session.id,
      'user_id': session.userId,
      'song_id': session.songId,
      'artist_id': session.artistId,
      'album_id': session.albumId,
      'album_edition_id': session.albumEditionId,
      'song_title': session.songTitle,
      'artist_name': session.artistName,
      'album_title': session.albumTitle,
      'album_edition_title': session.albumEditionTitle,
      'started_at': session.startedAt.toUtc().toIso8601String(),
      'ended_at': session.endedAt?.toUtc().toIso8601String(),
      'listened_duration_ms': session.listenedDuration.inMilliseconds,
      'track_duration_ms': session.trackDuration.inMilliseconds,
      'final_position_ms': session.finalPosition.inMilliseconds,
      'end_reason': session.endReason?.name,
      'source_context': session.sourceContext,
      'created_at': session.createdAt.toUtc().toIso8601String(),
      'updated_at': session.updatedAt.toUtc().toIso8601String(),
    };
  }
}
