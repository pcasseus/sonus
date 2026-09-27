import '../../domain/models/listening_history_cursor.dart';
import '../../domain/entities/playback_session.dart';
import '../../domain/repositories/playback_session_repository.dart';
import '../daos/playback_session_dao.dart';
import '../mappers/playback_session_row_mapper.dart';

class SqlitePlaybackSessionRepository implements PlaybackSessionRepository {
  const SqlitePlaybackSessionRepository(this.dao);

  final PlaybackSessionDao dao;

  @override
  Future<void> create(PlaybackSession session) {
    return dao.insert(PlaybackSessionRowMapper.toRow(session));
  }

  @override
  Future<void> save(PlaybackSession session) {
    return dao.update(PlaybackSessionRowMapper.toRow(session));
  }

  @override
  Future<PlaybackSession?> getById(String id) async {
    final row = await dao.findById(id);

    return row == null ? null : PlaybackSessionRowMapper.fromRow(row);
  }

  @override
  Future<List<PlaybackSession>> getOpen() async {
    final rows = await dao.findOpen();

    return rows.map(PlaybackSessionRowMapper.fromRow).toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getAll({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
  }) async {
    final rows = await dao.findAll(
      startedAtOrAfter: startedAtOrAfter,
      startedBefore: startedBefore,
    );

    return rows.map(PlaybackSessionRowMapper.fromRow).toList(growable: false);
  }

  @override
  Future<List<PlaybackSession>> getHistoryPage({
    DateTime? startedAtOrAfter,
    DateTime? startedBefore,
    ListeningHistoryCursor? before,
    required int limit,
  }) async {
    final rows = await dao.findHistoryPage(
      startedAtOrAfter: startedAtOrAfter,
      startedBefore: startedBefore,
      cursorStartedAt: before?.startedAt,
      cursorSessionId: before?.sessionId,
      limit: limit,
    );

    return rows.map(PlaybackSessionRowMapper.fromRow).toList(growable: false);
  }
}
