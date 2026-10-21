import '../repositories/cloud_revision_baseline_repository.dart';
import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import 'cloud_conditional_write_result.dart';
import 'outbound_artist_delete_committer.dart';
import 'outbound_artist_write_coordinator.dart';

typedef ReceiptDeleteCloudArtist =
    Future<CloudConditionalWriteResult> Function({
      required String artistId,
      required int expectedServerRevision,
      required String outboxId,
      required int mutationRevision,
      required DateTime deletedAt,
    });

/// Coordinates an explicit artist deletion using a guarded cloud RPC.
///
/// An artist must have a reconciled cloud baseline before deletion.
/// The deletion receipt and server revision are verified before the
/// SQLite committer acknowledges the original mutation.
class OutboundArtistDeleteCoordinator {
  const OutboundArtistDeleteCoordinator({
    required this.baselineRepository,
    required this.deleteArtistWithReceipt,
    required this.committer,
  });

  final CloudRevisionBaselineRepository baselineRepository;
  final ReceiptDeleteCloudArtist deleteArtistWithReceipt;
  final OutboundArtistDeleteCommitter committer;

  Future<void> push({
    required String userId,
    required SyncOutboxEntry entry,
  }) async {
    final owner = userId.trim();

    if (owner.isEmpty ||
        entry.userId != owner ||
        entry.entityType != CloudDataEntity.artist ||
        entry.operation != SyncOutboxOperation.delete ||
        entry.id.trim().isEmpty ||
        entry.entityId.trim().isEmpty ||
        entry.mutationRevision < 1) {
      throw StateError(
        'Invalid outbound artist deletion mutation or ownership.',
      );
    }

    final baseline = await baselineRepository.getRevision(
      userId: owner,
      entityType: CloudDataEntity.artist,
      entityId: entry.entityId,
    );

    if (baseline == null) {
      throw StateError(
        'Artist deletion requires a reconciled cloud revision baseline.',
      );
    }

    if (baseline < 1 || baseline >= 9223372036854775807) {
      throw StateError('Invalid stored artist server revision.');
    }

    final result = await deleteArtistWithReceipt(
      artistId: entry.entityId,
      expectedServerRevision: baseline,
      outboxId: entry.id,
      mutationRevision: entry.mutationRevision,
      deletedAt: entry.updatedAt,
    );

    switch (result.outcome) {
      case CloudConditionalWriteOutcome.applied:
      case CloudConditionalWriteOutcome.replayed:
        final expectedResultRevision = baseline + 1;

        if (result.serverRevision != expectedResultRevision) {
          throw StateError(
            'Unexpected applied artist deletion revision: '
            '${result.serverRevision}; expected $expectedResultRevision.',
          );
        }

        await committer.commitApplied(
          userId: owner,
          entry: entry,
          result: result,
        );

      case CloudConditionalWriteOutcome.conflict:
      case CloudConditionalWriteOutcome.notFound:
        throw OutboundArtistWriteConflict(
          artistId: entry.entityId,
          outcome: result.outcome,
          expectedServerRevision: baseline,
          observedServerRevision: result.serverRevision,
        );
    }
  }
}
