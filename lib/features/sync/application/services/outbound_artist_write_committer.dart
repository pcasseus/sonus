import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import 'cloud_conditional_write_result.dart';
import 'outbound_acknowledgement.dart';
import 'sync_mutation_runner.dart';

/// Completes an already-applied artist cloud update locally.
///
/// Cloud requests must finish before this method is called.
/// The baseline, the mutation acknowledgement and the clearing of the
/// conflict it resolves share one SQLite transaction.
class OutboundArtistWriteCommitter {
  const OutboundArtistWriteCommitter({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  Future<void> commitApplied({
    required String userId,
    required SyncOutboxEntry entry,
    required CloudConditionalWriteResult result,
  }) async {
    final owner = userId.trim();

    if (owner.isEmpty || entry.userId != owner) {
      throw StateError('Artist write owner mismatch.');
    }

    if (entry.entityType != CloudDataEntity.artist ||
        entry.operation != SyncOutboxOperation.upsert ||
        entry.entityId.trim().isEmpty) {
      throw StateError('Expected an artist upsert mutation.');
    }

    if (result.outcome != CloudConditionalWriteOutcome.applied &&
        result.outcome != CloudConditionalWriteOutcome.replayed) {
      throw StateError('Cannot acknowledge an unverified artist cloud write.');
    }

    final revision = result.serverRevision;

    if (revision == null || revision < 1) {
      throw StateError('Applied artist write has no valid revision.');
    }

    await mutationRunner.run<void>((context) async {
      // Persist the revision even if a newer local mutation now exists.
      // The newer edit must use this revision on its next upload.
      final baselineRepository = context.cloudRevisionBaselineRepository;

      if (baselineRepository == null) {
        throw StateError(
          'Cloud revision baseline repository is required for outbound acknowledgement.',
        );
      }

      await baselineRepository.saveObservedRevision(
        userId: owner,
        entityType: CloudDataEntity.artist,
        entityId: entry.entityId,
        serverRevision: revision,
      );

      // This is a compare-and-delete. If a local edit arrived during
      // upload, its mutation revision changed and the entry survives.
      await acknowledgeOutboundMutation(
        context,
        userId: owner,
        entityType: CloudDataEntity.artist,
        entityId: entry.entityId,
        outboxId: entry.id,
        mutationRevision: entry.mutationRevision,
        operation: entry.operation,
      );
    });
  }
}
