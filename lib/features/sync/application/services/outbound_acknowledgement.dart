import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import 'sync_mutation_context.dart';
import 'sync_mutation_runner.dart';

/// Acknowledges a cloud-accepted outbox mutation and clears the conflict
/// it resolves, both inside [context]'s transaction.
///
/// Neither write can commit without the other, so a conflict never
/// outlives its acknowledged mutation. Both are conditional: the outbox
/// entry is removed only at the pushed revision and operation, so a newer
/// local edit stays pending, and a conflict recorded for that newer edit
/// is kept.
Future<void> acknowledgeOutboundMutation(
  SyncMutationContext context, {
  required String userId,
  required CloudDataEntity entityType,
  required String entityId,
  required String outboxId,
  required int mutationRevision,
  required SyncOutboxOperation operation,
}) async {
  await context.localSyncRepository.markProcessed(
    userId: userId,
    outboxEntryId: outboxId,
    expectedRevision: mutationRevision,
    expectedOperation: operation,
  );

  await context.outboundConflictRepository?.clearResolved(
    userId: userId,
    entityType: entityType,
    entityId: entityId,
    outboxId: outboxId,
    mutationRevision: mutationRevision,
  );
}

/// Acknowledges pushed outbox entries in their own coordinated transaction.
class TransactionalOutboundAcknowledgement {
  const TransactionalOutboundAcknowledgement({required this.mutationRunner});

  final SyncMutationRunner mutationRunner;

  Future<void> acknowledge({
    required String userId,
    required SyncOutboxEntry entry,
  }) {
    return mutationRunner.run<void>(
      (context) => acknowledgeOutboundMutation(
        context,
        userId: userId,
        entityType: entry.entityType,
        entityId: entry.entityId,
        outboxId: entry.id,
        mutationRevision: entry.mutationRevision,
        operation: entry.operation,
      ),
    );
  }
}
