import '../../domain/entities/playback_listening_segment.dart';

abstract final class PlaybackListeningSegmentRowMapper {
  static PlaybackListeningSegment fromRow(Map<String, Object?> row) {
    return PlaybackListeningSegment(
      id: row['id']! as String,
      playbackSessionId: row['playback_session_id']! as String,
      startedAt: DateTime.parse(row['started_at']! as String),
      endedAt: row['ended_at'] == null
          ? null
          : DateTime.parse(row['ended_at']! as String),
      listenedDuration: Duration(
        milliseconds: row['listened_duration_ms']! as int,
      ),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }

  static Map<String, Object?> toRow(PlaybackListeningSegment segment) {
    return <String, Object?>{
      'id': segment.id,
      'playback_session_id': segment.playbackSessionId,
      'started_at': segment.startedAt.toUtc().toIso8601String(),
      'ended_at': segment.endedAt?.toUtc().toIso8601String(),
      'listened_duration_ms': segment.listenedDuration.inMilliseconds,
      'created_at': segment.createdAt.toUtc().toIso8601String(),
      'updated_at': segment.updatedAt.toUtc().toIso8601String(),
    };
  }
}
