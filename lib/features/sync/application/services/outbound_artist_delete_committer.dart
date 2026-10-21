import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import 'cloud_conditional_write_result.dart';
import 'sync_mutation_runner.dart';

/// Completes a verified artist cloud deletion locally.
///
/// The server write must finish before this method is called.
/// Revision reconciliation and outbox acknowledgement are atomic.
class OutboundArtistDeleteCommitter {
  const OutboundArtistDeleteCommitter({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  Future<void> commitApplied({
    required String userId,
    required SyncOutboxEntry entry,
    required CloudConditionalWriteResult result,
  }) async {
    final owner = userId.trim();

    if (owner.isEmpty || entry.userId != owner) {
      throw StateError('Artist deletion owner mismatch.');
    }

    if (entry.entityType != CloudDataEntity.artist ||
        entry.operation != SyncOutboxOperation.delete ||
        entry.entityId.trim().isEmpty ||
        entry.id.trim().isEmpty ||
        entry.mutationRevision < 1) {
      throw StateError('Expected a valid artist deletion mutation.');
    }

    if (result.outcome != CloudConditionalWriteOutcome.applied &&
        result.outcome != CloudConditionalWriteOutcome.replayed) {
      throw StateError(
        'Cannot acknowledge an unverified artist cloud deletion.',
      );
    }

    final revision = result.serverRevision;

    if (revision == null || revision < 1) {
      throw StateError(
        'Verified artist deletion has no valid server revision.',
      );
    }

    await mutationRunner.run<void>((context) async {
      final baselines = context.cloudRevisionBaselineRepository;

      if (baselines == null) {
        throw StateError(
          'Cloud revision baseline repository is required '
          'for artist deletion acknowledgement.',
        );
      }

      // Keep the verified cloud revision even when a newer
      // local mutation has replaced the uploaded outbox state.
      await baselines.saveObservedRevision(
        userId: owner,
        entityType: CloudDataEntity.artist,
        entityId: entry.entityId,
        serverRevision: revision,
      );

      // Compare-and-delete: never remove a newer local edit
      // or a different pending outbox operation.
      await context.localSyncRepository.markProcessed(
        userId: owner,
        outboxEntryId: entry.id,
        expectedRevision: entry.mutationRevision,
        expectedOperation: SyncOutboxOperation.delete,
      );
    });
  }
}
