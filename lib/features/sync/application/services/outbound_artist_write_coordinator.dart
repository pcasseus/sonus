import '../repositories/cloud_revision_baseline_repository.dart';
import '../../domain/models/cloud_records.dart';
import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import 'cloud_conditional_write_result.dart';
import 'outbound_artist_write_committer.dart';

typedef CreateCloudArtist =
    Future<CloudConditionalWriteResult> Function({
      required CloudArtistRecord artist,
    });

typedef UpdateCloudArtist =
    Future<CloudConditionalWriteResult> Function({
      required CloudArtistRecord artist,
      required int expectedServerRevision,
    });

typedef ReceiptCreateCloudArtist =
    Future<CloudConditionalWriteResult> Function({
      required CloudArtistRecord artist,
      required String outboxId,
      required int mutationRevision,
    });

typedef ReceiptUpdateCloudArtist =
    Future<CloudConditionalWriteResult> Function({
      required CloudArtistRecord artist,
      required int expectedServerRevision,
      required String outboxId,
      required int mutationRevision,
    });

/// A cloud result that must not acknowledge the pending local mutation.
///
/// The reported server revision is diagnostic only. It must not be
/// adopted as a local baseline without reconciliation.
class OutboundArtistWriteConflict implements Exception {
  const OutboundArtistWriteConflict({
    required this.artistId,
    required this.outcome,
    required this.expectedServerRevision,
    required this.observedServerRevision,
  });

  final String artistId;
  final CloudConditionalWriteOutcome outcome;
  final int? expectedServerRevision;
  final int? observedServerRevision;

  @override
  String toString() {
    return 'OutboundArtistWriteConflict('
        'artistId: $artistId, '
        'outcome: $outcome, '
        'expectedServerRevision: $expectedServerRevision, '
        'observedServerRevision: $observedServerRevision)';
  }
}

/// Routes explicit artist upsert mutations to safe cloud operations.
///
/// This does not upload dependencies, perform deletions, or decide
/// whether an artist needs an outbox mutation.
class OutboundArtistWriteCoordinator {
  const OutboundArtistWriteCoordinator({
    required this.baselineRepository,
    required this.createArtist,
    required this.updateArtist,
    required this.committer,
    this.createArtistWithReceipt,
    this.updateArtistWithReceipt,
  });

  final CloudRevisionBaselineRepository baselineRepository;
  final CreateCloudArtist createArtist;
  final UpdateCloudArtist updateArtist;
  final OutboundArtistWriteCommitter committer;
  final ReceiptCreateCloudArtist? createArtistWithReceipt;
  final ReceiptUpdateCloudArtist? updateArtistWithReceipt;

  Future<void> push({
    required String userId,
    required SyncOutboxEntry entry,
    required CloudArtistRecord artist,
  }) async {
    final owner = userId.trim();

    if (owner.isEmpty ||
        entry.userId != owner ||
        artist.userId != owner ||
        entry.entityType != CloudDataEntity.artist ||
        entry.operation != SyncOutboxOperation.upsert ||
        entry.entityId.trim().isEmpty ||
        artist.id != entry.entityId ||
        artist.isDeleted) {
      throw StateError('Invalid outbound artist mutation or ownership.');
    }

    if ((createArtistWithReceipt == null) !=
        (updateArtistWithReceipt == null)) {
      throw StateError(
        'Receipt-aware creation and update must be configured together.',
      );
    }

    final baseline = await baselineRepository.getRevision(
      userId: owner,
      entityType: CloudDataEntity.artist,
      entityId: entry.entityId,
    );

    if (baseline != null && baseline < 1) {
      throw StateError('Invalid stored artist server revision.');
    }

    final CloudConditionalWriteResult result;

    if (baseline == null) {
      final receiptCreate = createArtistWithReceipt;

      result = receiptCreate == null
          ? await createArtist(artist: artist)
          : await receiptCreate(
              artist: artist,
              outboxId: entry.id,
              mutationRevision: entry.mutationRevision,
            );
    } else {
      final receiptUpdate = updateArtistWithReceipt;

      result = receiptUpdate == null
          ? await updateArtist(artist: artist, expectedServerRevision: baseline)
          : await receiptUpdate(
              artist: artist,
              expectedServerRevision: baseline,
              outboxId: entry.id,
              mutationRevision: entry.mutationRevision,
            );
    }

    switch (result.outcome) {
      case CloudConditionalWriteOutcome.applied:
      case CloudConditionalWriteOutcome.replayed:
        final expectedResultRevision = baseline == null ? 1 : baseline + 1;

        if (result.serverRevision != expectedResultRevision) {
          throw StateError(
            'Unexpected applied artist revision: '
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
          artistId: artist.id,
          outcome: result.outcome,
          expectedServerRevision: baseline,
          observedServerRevision: result.serverRevision,
        );
    }
  }
}
