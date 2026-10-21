import '../../application/services/cloud_conditional_write_result.dart';
import '../../domain/models/artist_dependency_journal_entry.dart';
import '../../domain/models/artist_write_journal_entry.dart';
import 'artist_journal_replay_gateway.dart';

/// Replays a durable dependency-only artist creation request.
///
/// Its request identity is not an actual sync outbox identity.
class ArtistDependencyReceiptReplayGateway {
  const ArtistDependencyReceiptReplayGateway({required this.artistGateway});

  final ArtistJournalReplayGateway artistGateway;

  Future<CloudConditionalWriteResult> replay(
    ArtistDependencyJournalEntry entry,
  ) {
    final request = ArtistWriteJournalEntry(
      userId: entry.userId,
      artistId: entry.artistId,
      outboxId: entry.requestId,
      mutationRevision: entry.mutationRevision,
      operation: ArtistWriteJournalOperation.create,
      expectedServerRevision: null,
      requestJson: entry.requestJson,
      createdAt: entry.createdAt,
    );

    return artistGateway.replay(request);
  }
}
