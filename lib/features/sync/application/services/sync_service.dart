import 'package:flutter/foundation.dart';

import '../../../account/application/repositories/local_account_binding_repository.dart';
import '../../domain/models/local_sync_models.dart';
import '../repositories/local_sync_repository.dart';
import 'inbound_sync_processor.dart';
import 'outbound_sync_processor.dart';
import 'sync_run_guard.dart';

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
    this._attachAccount,
    this._runGuard,
    this._firstLinkGuard,
    this._syncArchive,
  }) : _bindToUser = accountBindingRepository.bindToUser,
       _claimUnowned = localSyncOwnershipRepository.claimUnowned,
       _getPending = localSyncRepository.getPending,
       _pushPending = outboundSyncProcessor.pushPending,
       _pushPendingIsolated = outboundSyncProcessor.pushPendingIsolated,
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
    this._attachAccount,
    this._runGuard,
    this._pushPendingIsolated,
    this._firstLinkGuard,
    this._syncArchive,
  }) : _now = now ?? DateTime.now;

  final Future<int> Function(String userId)? _attachAccount;

  /// Throws SyncNeedsCloudLibraryChoice before this device is linked to an
  /// account that already has a cloud library.
  final Future<void> Function(String userId)? _firstLinkGuard;

  /// Playlists, listening history, lyrics, crops, organization and
  /// all-time Moments; runs after the library.
  final Future<void> Function(String userId)? _syncArchive;

  // Guards the entire run, so attachment, push, and pull are all covered.
  final SyncRunGuard? _runGuard;
  final Future<void> Function(String userId) _bindToUser;
  final Future<int> Function(String userId) _claimUnowned;
  final Future<List<SyncOutboxEntry>> Function(String userId) _getPending;
  final Future<void> Function(String userId) _pushPending;
  final Future<OutboundPushReport> Function(String userId)?
  _pushPendingIsolated;
  final Future<int> Function(String userId) _pullAll;
  final SyncClock _now;

  /// Local changes still waiting to be sent to the cloud.
  Future<int> pendingCount(String userId) async =>
      (await _getPending(userId.trim())).length;

  Future<SyncRunResult> synchronize(String userId) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    final guard = _runGuard;

    if (guard == null) {
      return _synchronize(normalizedUserId);
    }

    return guard.guard(() => _synchronize(normalizedUserId));
  }

  Future<SyncRunResult> _synchronize(String normalizedUserId) async {
    final startedAt = _now().toUtc();

    // Before anything is bound, claimed, uploaded or downloaded.
    await _firstLinkGuard?.call(normalizedUserId);

    final attachAccount = _attachAccount;
    final int claimedUnownedCount;

    if (attachAccount != null) {
      claimedUnownedCount = await attachAccount(normalizedUserId);
    } else {
      await _bindToUser(normalizedUserId);
      claimedUnownedCount = await _claimUnowned(normalizedUserId);
    }

    final pendingBeforePush = (await _getPending(normalizedUserId)).length;

    final pushIsolated = _pushPendingIsolated;
    final int pulledRecordCount;

    if (pushIsolated == null) {
      await _pushPending(normalizedUserId);
      pulledRecordCount = await _pullAll(normalizedUserId);
      await _syncArchive?.call(normalizedUserId);
    } else {
      // Safety holds throw here and stop the run before any pull.
      final report = await pushIsolated(normalizedUserId);

      // Failed entries stay pending. Inbound still runs because it defers,
      // and never overwrites, records with pending local mutations.
      pulledRecordCount = await _pullAll(normalizedUserId);

      // The archive does not depend on the library push having finished;
      // a failure of either is reported, the library's first.
      Object? archiveError;
      StackTrace? archiveStack;
      try {
        await _syncArchive?.call(normalizedUserId);
      } catch (error, stackTrace) {
        archiveError = error;
        archiveStack = stackTrace;
      }

      if (!report.isComplete) {
        final first = report.failures.first;
        Error.throwWithStackTrace(first.error, first.stackTrace);
      }
      if (archiveError != null) {
        Error.throwWithStackTrace(archiveError, archiveStack!);
      }
    }

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
