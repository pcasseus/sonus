import '../entities/playback_listening_segment.dart';

abstract interface class PlaybackListeningSegmentRepository {
  Future<void> create(PlaybackListeningSegment segment);

  Future<void> save(PlaybackListeningSegment segment);

  Future<PlaybackListeningSegment?> getById(String id);

  Future<PlaybackListeningSegment?> getOpenForSession(String playbackSessionId);

  Future<List<PlaybackListeningSegment>> getForSession(
    String playbackSessionId,
  );

  Future<List<PlaybackListeningSegment>> getAll({DateTime? startedBefore});
}
