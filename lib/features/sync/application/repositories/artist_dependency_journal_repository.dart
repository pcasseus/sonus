import '../../domain/models/artist_dependency_journal_entry.dart';

abstract class ArtistDependencyJournalRepository {
  Future<ArtistDependencyJournalEntry?> findUnresolved({
    required String userId,
    required String artistId,
  });

  Future<List<ArtistDependencyJournalEntry>> findUnresolvedForUser(
    String userId,
  );

  Future<void> prepare(ArtistDependencyJournalEntry entry);

  Future<int> removeVerified(ArtistDependencyJournalEntry entry);
}
