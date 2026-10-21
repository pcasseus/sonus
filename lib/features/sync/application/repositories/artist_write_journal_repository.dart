import '../../domain/models/artist_write_journal_entry.dart';

abstract interface class ArtistWriteJournalRepository {
  Future<ArtistWriteJournalEntry?> findUnresolved({
    required String userId,
    required String artistId,
  });

  Future<List<ArtistWriteJournalEntry>> findUnresolvedForUser(String userId);

  Future<void> prepare(ArtistWriteJournalEntry entry);

  /// Only call after authoritative cloud verification, in a transaction
  /// that also persists the cloud revision and acknowledges the outbox.
  Future<int> removeVerified(ArtistWriteJournalEntry entry);
}
