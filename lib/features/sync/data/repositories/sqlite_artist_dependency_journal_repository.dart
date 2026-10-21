import '../../application/repositories/artist_dependency_journal_repository.dart';
import '../../domain/models/artist_dependency_journal_entry.dart';
import '../daos/artist_dependency_journal_dao.dart';

class SqliteArtistDependencyJournalRepository
    implements ArtistDependencyJournalRepository {
  const SqliteArtistDependencyJournalRepository(this.dao);

  final ArtistDependencyJournalDao dao;

  @override
  Future<ArtistDependencyJournalEntry?> findUnresolved({
    required String userId,
    required String artistId,
  }) {
    return dao.findUnresolved(userId: userId, artistId: artistId);
  }

  @override
  Future<List<ArtistDependencyJournalEntry>> findUnresolvedForUser(
    String userId,
  ) {
    return dao.findUnresolvedForUser(userId);
  }

  @override
  Future<void> prepare(ArtistDependencyJournalEntry entry) {
    return dao.prepare(entry);
  }

  @override
  Future<int> removeVerified(ArtistDependencyJournalEntry entry) {
    return dao.removeVerified(entry);
  }
}
