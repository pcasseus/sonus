import '../../../../core/database/app_database.dart';
import '../../domain/entities/qualified_play.dart';
import '../../domain/repositories/qualified_play_repository.dart';
import '../daos/qualified_play_dao.dart';
import '../mappers/qualified_play_row_mapper.dart';

class SqliteQualifiedPlayRepository implements QualifiedPlayRepository {
  const SqliteQualifiedPlayRepository(this.dao, {this.appDatabase});

  final QualifiedPlayDao dao;

  /// Coordinates standalone production writes with exclusive restoration.
  /// Omit when a caller already owns the transaction.
  final AppDatabase? appDatabase;

  @override
  Future<void> create(QualifiedPlay play) {
    final row = QualifiedPlayRowMapper.toRow(play);
    final database = appDatabase;
    if (database == null) {
      return dao.insert(row);
    }

    return database.transaction(
      (transaction) => QualifiedPlayDao(transaction).insert(row),
    );
  }

  @override
  Future<void> save(QualifiedPlay play) {
    final row = QualifiedPlayRowMapper.toRow(play);
    final database = appDatabase;
    if (database == null) {
      return dao.update(row);
    }

    return database.transaction(
      (transaction) => QualifiedPlayDao(transaction).update(row),
    );
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
