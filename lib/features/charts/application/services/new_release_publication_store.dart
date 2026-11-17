import '../../domain/moments/new_release_publication.dart';

/// Where published new-release debut stories are kept (App Update 1.3):
/// one per song, written once.
abstract interface class NewReleasePublicationStore {
  /// Advances whenever a restore is requested (LibraryMutationCoordinator).
  /// Read before the library facts a publication is composed from, and
  /// passed to [publish], so a restore in between writes nothing.
  int get restoreGeneration;

  /// Every stored publication, by song id.
  Future<Map<String, NewReleasePublication>> readAll();

  /// Stores each of [publications] whose song has none yet; a song that
  /// already has one keeps it. Returns what is now stored for those songs
  /// (the earlier record wherever one won). Writes nothing and returns the
  /// stored records when [restoreGeneration] is no longer current.
  Future<Map<String, NewReleasePublication>> publish(
    Iterable<NewReleasePublication> publications, {
    required int restoreGeneration,
  });
}
