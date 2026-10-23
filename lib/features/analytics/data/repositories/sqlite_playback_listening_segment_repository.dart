import '../../../../core/database/app_database.dart';
import '../../domain/entities/playback_listening_segment.dart';
import '../../domain/repositories/playback_listening_segment_repository.dart';
import '../daos/playback_listening_segment_dao.dart';
import '../mappers/playback_listening_segment_row_mapper.dart';

class SqlitePlaybackListeningSegmentRepository
    implements PlaybackListeningSegmentRepository {
  const SqlitePlaybackListeningSegmentRepository(this.dao, {this.appDatabase});

  final PlaybackListeningSegmentDao dao;

  /// Coordinates standalone production writes with exclusive restoration.
  /// Omit when a caller already owns the transaction.
  final AppDatabase? appDatabase;

  @override
  Future<void> create(PlaybackListeningSegment segment) {
    final row = PlaybackListeningSegmentRowMapper.toRow(segment);
    final database = appDatabase;
    if (database == null) {
      return dao.insert(row);
    }

    return database.transaction(
      (transaction) => PlaybackListeningSegmentDao(transaction).insert(row),
    );
  }

  @override
  Future<void> save(PlaybackListeningSegment segment) {
    final row = PlaybackListeningSegmentRowMapper.toRow(segment);
    final database = appDatabase;
    if (database == null) {
      return dao.update(row);
    }

    return database.transaction(
      (transaction) => PlaybackListeningSegmentDao(transaction).update(row),
    );
  }

  @override
  Future<PlaybackListeningSegment?> getById(String id) async {
    final row = await dao.findById(id);

    return row == null ? null : PlaybackListeningSegmentRowMapper.fromRow(row);
  }

  @override
  Future<PlaybackListeningSegment?> getOpenForSession(
    String playbackSessionId,
  ) async {
    final row = await dao.findOpenForSession(playbackSessionId);

    return row == null ? null : PlaybackListeningSegmentRowMapper.fromRow(row);
  }

  @override
  Future<List<PlaybackListeningSegment>> getForSession(
    String playbackSessionId,
  ) async {
    final rows = await dao.findForSession(playbackSessionId);

    return rows
        .map(PlaybackListeningSegmentRowMapper.fromRow)
        .toList(growable: false);
  }

  @override
  Future<List<PlaybackListeningSegment>> getAll({
    DateTime? startedBefore,
  }) async {
    final rows = await dao.findAll(startedBefore: startedBefore);

    return rows
        .map(PlaybackListeningSegmentRowMapper.fromRow)
        .toList(growable: false);
  }
}
