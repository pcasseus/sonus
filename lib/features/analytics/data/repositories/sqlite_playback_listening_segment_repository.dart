import '../../domain/entities/playback_listening_segment.dart';
import '../../domain/repositories/playback_listening_segment_repository.dart';
import '../daos/playback_listening_segment_dao.dart';
import '../mappers/playback_listening_segment_row_mapper.dart';

class SqlitePlaybackListeningSegmentRepository
    implements PlaybackListeningSegmentRepository {
  const SqlitePlaybackListeningSegmentRepository(this.dao);

  final PlaybackListeningSegmentDao dao;

  @override
  Future<void> create(PlaybackListeningSegment segment) {
    return dao.insert(PlaybackListeningSegmentRowMapper.toRow(segment));
  }

  @override
  Future<void> save(PlaybackListeningSegment segment) {
    return dao.update(PlaybackListeningSegmentRowMapper.toRow(segment));
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
