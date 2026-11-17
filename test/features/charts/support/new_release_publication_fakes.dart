import 'package:sonus_next/features/charts/application/services/new_release_publication_store.dart';
import 'package:sonus_next/features/charts/domain/moments/new_release_publication.dart';

/// Publications kept in memory, first one per song wins, like the SQLite
/// store.
class MemoryNewReleasePublications implements NewReleasePublicationStore {
  final Map<String, NewReleasePublication> records = {};
  final List<List<NewReleasePublication>> writes = [];

  @override
  int restoreGeneration = 0;

  @override
  Future<Map<String, NewReleasePublication>> readAll() async => {...records};

  @override
  Future<Map<String, NewReleasePublication>> publish(
    Iterable<NewReleasePublication> publications, {
    required int restoreGeneration,
  }) async {
    final batch = publications.toList();
    writes.add(batch);
    if (restoreGeneration == this.restoreGeneration) {
      for (final publication in batch) {
        records.putIfAbsent(publication.songId, () => publication);
      }
    }
    return {
      for (final publication in batch)
        publication.songId: ?records[publication.songId],
    };
  }
}
