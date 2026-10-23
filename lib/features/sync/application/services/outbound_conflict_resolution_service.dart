import '../../domain/models/local_sync_models.dart';
import '../../domain/models/outbound_sync_conflict.dart';
import '../../domain/models/sync_data_contract.dart';
import '../repositories/outbound_conflict_repository.dart';
import 'cloud_sync_gateway.dart';
import 'cloud_sync_reader.dart';
import 'inbound_cloud_record_applier.dart';
import 'sync_mutation_context.dart';
import 'sync_mutation_runner.dart';

/// Explicit, user-chosen resolution of a recorded outbound conflict.
///
/// Both choices refuse to act when the pending local mutation changed
/// after the conflict was recorded, and commit their local effects in a
/// single transaction.
class OutboundConflictResolutionService {
  const OutboundConflictResolutionService({
    required this.mutationRunner,
    required this.cloudSyncGateway,
    this.applier = const InboundCloudRecordApplier(),
  });

  final SyncMutationRunner mutationRunner;
  final CloudSyncGateway cloudSyncGateway;
  final InboundCloudRecordApplier applier;

  /// Keeps the pending local mutation and lets the next push replace the
  /// cloud revision observed now. A tombstoned cloud row is never revived.
  Future<void> keepLocal({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    final owner = _owner(userId);
    final conflict = await _requireConflict(owner, entityType, entityId);
    final current = await _fetchOwned(owner, entityType, entityId);

    await mutationRunner.run<void>((context) async {
      final entry = await _requireUnchangedEntry(context, conflict);
      final deleting = entry.operation == SyncOutboxOperation.delete;

      if (current == null) {
        if (!deleting) {
          throw StateError(
            'Cloud ${entityType.name} $entityId is absent; keep-local cannot '
            'target a revision for an upsert.',
          );
        }

        // Nothing owned by this account remains to delete.
        await _acknowledge(context, entry);
        await _conflicts(
          context,
        ).clear(userId: owner, entityType: entityType, entityId: entityId);
        return;
      }

      final revision = current.serverRevision!;

      if (current.record.isDeleted) {
        if (!deleting) {
          throw StateError(
            'Cloud ${entityType.name} $entityId is a tombstone; keep-local '
            'does not revive deleted cloud rows.',
          );
        }

        await _saveBaseline(context, owner, entityType, entityId, revision);
        await _acknowledge(context, entry);
      } else {
        // The pending mutation stays queued and is now conditioned on the
        // revision the user chose to replace.
        await _saveBaseline(context, owner, entityType, entityId, revision);
      }

      await _conflicts(
        context,
      ).clear(userId: owner, entityType: entityType, entityId: entityId);
    });
  }

  /// Applies the current cloud revision locally and retires the pending
  /// local mutation. Fails without changes if the revision cannot be
  /// applied yet (for example a missing parent or a local deletion).
  Future<void> keepCloud({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    final owner = _owner(userId);
    final conflict = await _requireConflict(owner, entityType, entityId);
    final current = await _fetchOwned(owner, entityType, entityId);

    if (current == null) {
      throw StateError(
        'Cloud ${entityType.name} $entityId is absent; there is no cloud '
        'revision to keep.',
      );
    }

    final revision = current.serverRevision!;

    await mutationRunner.run<void>((context) async {
      final entry = await _requireUnchangedEntry(context, conflict);

      final result = await applier.apply(
        record: current.record,
        context: context,
      );

      if (result.isDeferred) {
        throw StateError(
          'Cloud ${entityType.name} $entityId cannot be applied locally yet: '
          '${result.deferralReason!.name}.',
        );
      }

      await _saveBaseline(context, owner, entityType, entityId, revision);
      await _acknowledge(context, entry);
      await _conflicts(
        context,
      ).clear(userId: owner, entityType: entityType, entityId: entityId);
    });
  }

  String _owner(String userId) {
    final owner = userId.trim();

    if (owner.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be blank.');
    }

    return owner;
  }

  Future<OutboundSyncConflict> _requireConflict(
    String owner,
    CloudDataEntity entityType,
    String entityId,
  ) async {
    final conflict = await mutationRunner.run(
      (context) => _conflicts(
        context,
      ).get(userId: owner, entityType: entityType, entityId: entityId),
    );

    if (conflict == null) {
      throw StateError(
        'No recorded conflict for ${entityType.name} $entityId.',
      );
    }

    return conflict;
  }

  Future<CloudSyncItem?> _fetchOwned(
    String owner,
    CloudDataEntity entityType,
    String entityId,
  ) async {
    final current = await cloudSyncGateway.fetchCurrent(
      userId: owner,
      entityType: entityType,
      entityId: entityId,
    );

    if (current == null) {
      return null;
    }

    final revision = current.serverRevision;

    if (current.record.userId != owner ||
        current.record.id != entityId ||
        revision == null ||
        revision < 1) {
      throw StateError('Cloud ${entityType.name} $entityId is not verifiable.');
    }

    return current;
  }

  Future<SyncOutboxEntry> _requireUnchangedEntry(
    SyncMutationContext context,
    OutboundSyncConflict conflict,
  ) async {
    final pending = await context.localSyncRepository.getPending(
      conflict.userId,
    );

    for (final entry in pending) {
      if (entry.entityType == conflict.entityType &&
          entry.entityId == conflict.entityId) {
        if (entry.id == conflict.outboxId &&
            entry.mutationRevision == conflict.mutationRevision &&
            entry.operation == conflict.operation) {
          return entry;
        }

        break;
      }
    }

    throw StateError(
      'The local ${conflict.entityType.name} ${conflict.entityId} mutation '
      'changed after the conflict was recorded. Synchronize again first.',
    );
  }

  Future<void> _saveBaseline(
    SyncMutationContext context,
    String owner,
    CloudDataEntity entityType,
    String entityId,
    int revision,
  ) async {
    final baselines = context.cloudRevisionBaselineRepository;

    if (baselines == null) {
      throw StateError('Conflict resolution requires revision baselines.');
    }

    await baselines.saveObservedRevision(
      userId: owner,
      entityType: entityType,
      entityId: entityId,
      serverRevision: revision,
    );

    // Older inbound replay obligations are superseded by this decision.
    await context.inboundDeferredRecordRepository?.clearThroughRevision(
      userId: owner,
      entityType: entityType,
      entityId: entityId,
      serverRevision: revision,
    );
  }

  Future<void> _acknowledge(
    SyncMutationContext context,
    SyncOutboxEntry entry,
  ) {
    return context.localSyncRepository.markProcessed(
      userId: entry.userId!,
      outboxEntryId: entry.id,
      expectedRevision: entry.mutationRevision,
      expectedOperation: entry.operation,
    );
  }

  OutboundConflictRepository _conflicts(SyncMutationContext context) {
    final repository = context.outboundConflictRepository;

    if (repository == null) {
      throw StateError('Conflict resolution requires the conflict ledger.');
    }

    return repository;
  }
}
