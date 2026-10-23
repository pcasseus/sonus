import 'local_sync_models.dart';
import 'sync_data_contract.dart';

/// Cloud state observed when a revision-guarded outbound write was
/// rejected.
enum OutboundConflictCloudState { live, tombstoned, absent }

/// A durable record of an outbound mutation that cloud state rejected.
///
/// The outbox entry stays pending until the conflict is resolved
/// explicitly or a later write succeeds.
class OutboundSyncConflict {
  const OutboundSyncConflict({
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.outboxId,
    required this.mutationRevision,
    required this.operation,
    required this.expectedServerRevision,
    required this.observedServerRevision,
    required this.observedState,
    required this.detectedAt,
  });

  final String userId;
  final CloudDataEntity entityType;
  final String entityId;
  final String outboxId;
  final int mutationRevision;
  final SyncOutboxOperation operation;

  /// The local baseline the write was conditioned on, if any.
  final int? expectedServerRevision;

  /// Diagnostic only. Never adopted as a baseline without resolution.
  final int? observedServerRevision;
  final OutboundConflictCloudState observedState;
  final DateTime detectedAt;
}
