import '../../application/repositories/artist_write_journal_repository.dart';
import '../../domain/models/artist_write_journal_entry.dart';
import '../daos/artist_write_journal_dao.dart';

class SqliteArtistWriteJournalRepository
    implements ArtistWriteJournalRepository {
  const SqliteArtistWriteJournalRepository(this.dao);

  final ArtistWriteJournalDao dao;

  @override
  Future<ArtistWriteJournalEntry?> findUnresolved({
    required String userId,
    required String artistId,
  }) => dao.findUnresolved(userId: userId, artistId: artistId);

  @override
  Future<List<ArtistWriteJournalEntry>> findUnresolvedForUser(String userId) =>
      dao.findUnresolvedForUser(userId);

  @override
  Future<void> prepare(ArtistWriteJournalEntry entry) => dao.prepare(entry);

  @override
  Future<int> removeVerified(ArtistWriteJournalEntry entry) =>
      dao.removeVerified(entry);
}
