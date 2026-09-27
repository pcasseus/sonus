import '../entities/qualified_play.dart';

abstract interface class QualifiedPlayRepository {
  Future<void> create(QualifiedPlay play);

  Future<void> save(QualifiedPlay play);

  Future<QualifiedPlay?> getById(String id);

  Future<QualifiedPlay?> getByPlaybackSessionId(String playbackSessionId);

  Future<List<QualifiedPlay>> getByPlaybackSessionIds(
    Iterable<String> playbackSessionIds,
  );

  Future<List<QualifiedPlay>> getAll({
    DateTime? qualifiedAtOrAfter,
    DateTime? qualifiedBefore,
  });
}
