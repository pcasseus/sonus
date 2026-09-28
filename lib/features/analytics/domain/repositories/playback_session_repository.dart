import '../models/listening_history_cursor.dart';
import '../entities/playback_session.dart';

abstract interface class PlaybackSessionRepository {
  Future<void> create(PlaybackSession session);

  Future<void> save(PlaybackSession session);

  Future<PlaybackSession?> getById(String id);

  Future<List<PlaybackSession>> getByIds(Iterable<String> ids);

  Future<List<PlaybackSession>> getOpen();

  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  });

  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  });
}
