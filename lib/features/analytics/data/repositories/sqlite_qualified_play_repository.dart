import '../../domain/entities/qualified_play.dart';
import '../../domain/repositories/qualified_play_repository.dart';
import '../daos/qualified_play_dao.dart';
import '../mappers/qualified_play_row_mapper.dart';

class SqliteQualifiedPlayRepository implements QualifiedPlayRepository {
  const SqliteQualifiedPlayRepository(this.dao);

  final QualifiedPlayDao dao;

  @override
  Future<void> create(QualifiedPlay play) {
    return dao.insert(QualifiedPlayRowMapper.toRow(play));
  }

  @override
  Future<void> save(QualifiedPlay play) {
    return dao.update(QualifiedPlayRowMapper.toRow(play));
  }

  @override
  Future<QualifiedPlay?> getById(String id) async {
    final row = await dao.findById(id);

    return row == null ? null : QualifiedPlayRowMapper.fromRow(row);
  }

  @override
  Future<QualifiedPlay?> getByPlaybackSessionId(
    String playbackSessionId,
  ) async {
    final row = await dao.findByPlaybackSessionId(playbackSessionId);

    return row == null ? null : QualifiedPlayRowMapper.fromRow(row);
  }

  @override
  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  ) async {
    final rows = await dao.findByPlaybackSessionIds(playbackSessionIds);

    return rows.map(QualifiedPlayRowMapper.fromRow).toList(growable: false);
  }

  @override
  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  }) async {
    final rows = await dao.findAll(
      qualifiedAtOrAfter: qualifiedAtOrAfter,
      qualifiedBefore: qualifiedBefore,
    );

    return rows.map(QualifiedPlayRowMapper.fromRow).toList(growable: false);
  }
}
