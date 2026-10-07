import 'package:flutter/foundation.dart';

import '../../../account/application/repositories/local_account_binding_repository.dart';
import '../../domain/models/local_sync_models.dart';
import '../repositories/local_sync_repository.dart';
import 'inbound_sync_processor.dart';
import 'outbound_sync_processor.dart';

typedef SyncClock = DateTime Function();

class SyncRunResult {
  const SyncRunResult({
    required this.userId,
    required this.startedAt,
    required this.completedAt,
    required this.claimedUnownedCount,
    required this.pendingBeforePush,
    required this.pulledRecordCount,
    required this.pendingAfterSync,
  });

  final String userId;
  final DateTime startedAt;
  final DateTime completedAt;
  final int claimedUnownedCount;
  final int pendingBeforePush;
  final int pulledRecordCount;
  final int pendingAfterSync;

  int get pushedMutationCount => pendingBeforePush;

  bool get hasRemainingPendingChanges => pendingAfterSync > 0;
}

class SyncService {
  SyncService({
    required LocalAccountBindingRepository accountBindingRepository,
    required LocalSyncRepository localSyncRepository,
    required LocalSyncOwnershipRepository localSyncOwnershipRepository,
    required OutboundSyncProcessor outboundSyncProcessor,
    required InboundSyncProcessor inboundSyncProcessor,
    SyncClock? now,
  }) : _bindToUser = accountBindingRepository.bindToUser,
       _claimUnowned = localSyncOwnershipRepository.claimUnowned,
       _getPending = localSyncRepository.getPending,
       _pushPending = outboundSyncProcessor.pushPending,
       _pullAll = ((userId) => inboundSyncProcessor.pullAll(userId: userId)),
       _now = now ?? DateTime.now;

  @visibleForTesting
  SyncService.forTesting({
    required this._bindToUser,
    required this._claimUnowned,
    required this._getPending,
    required this._pushPending,
    required this._pullAll,
    SyncClock? now,
  }) : _now = now ?? DateTime.now;

  final Future<void> Function(String userId) _bindToUser;
  final Future<int> Function(String userId) _claimUnowned;
  final Future<List<SyncOutboxEntry>> Function(String userId) _getPending;
  final Future<void> Function(String userId) _pushPending;
  final Future<int> Function(String userId) _pullAll;
  final SyncClock _now;

  Future<SyncRunResult> synchronize(String userId) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    final startedAt = _now().toUtc();

    await _bindToUser(normalizedUserId);

    final claimedUnownedCount = await _claimUnowned(normalizedUserId);

    final pendingBeforePush = (await _getPending(normalizedUserId)).length;

    await _pushPending(normalizedUserId);

    final pulledRecordCount = await _pullAll(normalizedUserId);

    final pendingAfterSync = (await _getPending(normalizedUserId)).length;

    return SyncRunResult(
      userId: normalizedUserId,
      startedAt: startedAt,
      completedAt: _now().toUtc(),
      claimedUnownedCount: claimedUnownedCount,
      pendingBeforePush: pendingBeforePush,
      pulledRecordCount: pulledRecordCount,
      pendingAfterSync: pendingAfterSync,
    );
  }
}
