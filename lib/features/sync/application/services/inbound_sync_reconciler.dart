import 'dart:developer' as developer;

import '../../../../core/identity/text_normalizer.dart';
import '../../../artwork/application/services/owned_artwork_managed_storage.dart';
import '../../../artwork/domain/entities/artwork_asset.dart';
import '../repositories/local_sync_repository.dart';
import '../../domain/models/cloud_records.dart';
import '../../domain/models/inbound_deferred_record.dart';
import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import 'cloud_artwork_recovery_service.dart';
import 'cloud_sync_reader.dart';
import 'inbound_cloud_record_applier.dart';
import 'sync_mutation_context.dart';
import 'sync_mutation_runner.dart';

typedef InboundSyncClock = DateTime Function();

class InboundSyncBatchResult {
  const InboundSyncBatchResult({
    required this.processedCount,
    required this.hasMore,
    required this.lastReadPosition,
    this.deferredCount = 0,
  });

  final int processedCount;

  /// Records passed by the cursor but durably deferred for replay.
  final int deferredCount;
  final bool hasMore;
  final CloudSyncPosition? lastReadPosition;
}

/// Receives one diagnostic line per failed replay.
typedef InboundReplayLogger = void Function(String message);

/// A deferred record whose replay attempt failed. Its ledger row is kept.
class InboundReplayFailure {
  const InboundReplayFailure({
    required this.record,
    required this.error,
    required this.stackTrace,
    this.requeued = false,
    this.requeueError,
    this.requeueStackTrace,
  });

  final InboundDeferredRecord record;

  /// The original replay failure. Always the error reported to callers.
  final Object error;
  final StackTrace stackTrace;

  /// Whether the obligation moved to the back of the replay queue.
  final bool requeued;

  /// A failure to requeue, reported alongside [error], never instead of it.
  final Object? requeueError;
  final StackTrace? requeueStackTrace;
}

/// Outcome of one bounded replay pass over the deferred ledger.
class InboundReplayResult {
  const InboundReplayResult({
    this.appliedCount = 0,
    this.stillDeferredCount = 0,
    this.skippedCount = 0,
    this.unresolvedCount = 0,
    this.notAttemptedCount = 0,
    this.installedArtworkCount = 0,
    this.failures = const [],
  });

  /// Replays whose obligation is now satisfied and cleared.
  final int appliedCount;

  /// Cloud artwork downloaded and committed as a local asset.
  final int installedArtworkCount;

  /// Fetched and durably deferred again, possibly for a new reason.
  final int stillDeferredCount;

  /// Not fetched because the local blocker still holds.
  final int skippedCount;

  /// Fetched, but the cloud row is missing or older than the deferral.
  /// The obligation is preserved for later reconciliation.
  final int unresolvedCount;

  /// Eligible but beyond this pass's fetch limit.
  final int notAttemptedCount;

  final List<InboundReplayFailure> failures;
}

abstract interface class InboundSyncPageReconciler {
  Future<DateTime?> replayStart({
    required String userId,
    required CloudDataEntity entityType,
    required Duration replayWindow,
  });

  Future<InboundSyncBatchResult> reconcilePage({
    required String userId,
    required CloudDataEntity entityType,
    required int limit,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
  });

  /// Replays deferred revisions the cursor has already passed, fetching
  /// at most [maxFetches] current cloud rows. Never moves a cursor.
  Future<InboundReplayResult> replayDeferred({
    required String userId,
    required int maxFetches,
  });
}

class InboundSyncReconciler implements InboundSyncPageReconciler {
  InboundSyncReconciler({
    required this.reader,
    required this.localSyncRepository,
    required this.mutationRunner,
    InboundCloudRecordApplier? applier,
    InboundSyncClock? now,
    InboundReplayLogger? replayLogger,
    this.recoverArtwork,
    this.maxArtworkDownloads = 10,
  }) : applier = applier ?? const InboundCloudRecordApplier(),
       _now = now ?? DateTime.now,
       _logReplay = replayLogger ?? _developerLog;

  final CloudSyncReader reader;
  final LocalSyncRepository localSyncRepository;
  final SyncMutationRunner mutationRunner;
  final InboundCloudRecordApplier applier;
  final InboundSyncClock _now;
  final InboundReplayLogger _logReplay;

  /// Downloads cloud-only artwork during replay. Without it, artwork that
  /// exists only in the cloud stays deferred.
  final RecoverCloudArtwork? recoverArtwork;

  /// Upper bound on artwork downloads per replay pass.
  final int maxArtworkDownloads;

  static void _developerLog(String message) {
    developer.log(message, name: 'sonus.sync.replay', level: 900);
  }

  @override
  Future<DateTime?> replayStart({
    required String userId,
    required CloudDataEntity entityType,
    required Duration replayWindow,
  }) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    if (replayWindow.isNegative) {
      throw ArgumentError.value(
        replayWindow,
        'replayWindow',
        'Replay window must not be negative.',
      );
    }

    final cursor = await localSyncRepository.getCursor(
      normalizedUserId,
      entityType,
    );

    final position = _positionFromCursor(cursor);

    if (position == null) {
      return null;
    }

    return position.serverUpdatedAt.subtract(replayWindow).toUtc();
  }

  @override
  Future<InboundSyncBatchResult> reconcilePage({
    required String userId,
    required CloudDataEntity entityType,
    required int limit,
    CloudSyncPosition? after,
    DateTime? fromServerUpdatedAtInclusive,
  }) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    if (limit <= 0) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Limit must be greater than zero.',
      );
    }

    if (after != null && fromServerUpdatedAtInclusive != null) {
      throw ArgumentError(
        'after and fromServerUpdatedAtInclusive cannot both be provided.',
      );
    }

    final storedCursor = await localSyncRepository.getCursor(
      normalizedUserId,
      entityType,
    );

    final storedPosition = _positionFromCursor(storedCursor);

    final readPosition =
        after ?? (fromServerUpdatedAtInclusive == null ? storedPosition : null);

    final page = await reader.readPage(
      userId: normalizedUserId,
      entityType: entityType,
      after: readPosition,
      fromServerUpdatedAtInclusive: fromServerUpdatedAtInclusive,
      limit: limit,
    );

    var processedCount = 0;
    var deferredCount = 0;
    var highWaterPosition = storedPosition;

    for (final item in page.items) {
      if (item.record.userId != normalizedUserId) {
        throw StateError(
          'Cloud sync record ${item.record.id} belongs to a different user.',
        );
      }

      if (_entityTypeForRecord(item.record) != entityType) {
        throw StateError(
          'Cloud sync record ${item.record.id} does not match requested entity type ${entityType.name}.',
        );
      }

      final itemPosition = CloudSyncPosition(
        serverUpdatedAt: item.serverUpdatedAt.toUtc(),
        id: item.record.id,
      );

      await mutationRunner.run((context) async {
        final outcome = await _reconcileItem(
          context: context,
          userId: normalizedUserId,
          entityType: entityType,
          item: item,
        );

        if (outcome == _ItemOutcome.deferred) {
          deferredCount += 1;
        }

        if (_isAfter(itemPosition, highWaterPosition)) {
          await context.localSyncRepository.saveCursor(
            SyncCursor(
              userId: normalizedUserId,
              entityType: entityType,
              lastServerUpdatedAt: itemPosition.serverUpdatedAt,
              lastServerId: itemPosition.id,
              updatedAt: _now().toUtc(),
            ),
          );
        }
      });

      if (_isAfter(itemPosition, highWaterPosition)) {
        highWaterPosition = itemPosition;
      }

      processedCount += 1;
    }

    return InboundSyncBatchResult(
      processedCount: processedCount,
      hasMore: page.hasMore,
      lastReadPosition: page.lastPosition,
      deferredCount: deferredCount,
    );
  }

  @override
  Future<InboundReplayResult> replayDeferred({
    required String userId,
    required int maxFetches,
  }) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'User id must not be blank.');
    }

    if (maxFetches <= 0) {
      throw ArgumentError.value(
        maxFetches,
        'maxFetches',
        'Must be greater than zero.',
      );
    }

    // Local-only screening. A record whose blocker visibly still holds is
    // not fetched; a newer cloud revision reaches it through the cursor.
    final (
      :candidates,
      :skippedCount,
      :downloadKeys,
    ) = await mutationRunner.run((context) async {
      final ledger = await context.inboundDeferredRecordRepository?.getDeferred(
        normalizedUserId,
      );

      final pendingKeys = {
        for (final entry in await context.localSyncRepository.getPending(
          normalizedUserId,
        ))
          _key(entry.entityType, entry.entityId),
      };

      final candidates = <InboundDeferredRecord>[];
      final downloadKeys = <String>{};
      var skippedCount = 0;

      for (final record in ledger ?? const <InboundDeferredRecord>[]) {
        if (await _blockerStillHolds(context, record, pendingKeys)) {
          skippedCount += 1;
          continue;
        }

        candidates.add(record);

        if (record.reason == InboundDeferralReason.artworkDownloadRequired &&
            await context.artworkAssetRepository.getById(record.entityId) ==
                null) {
          downloadKeys.add(_key(record.entityType, record.entityId));
        }
      }

      return (
        candidates: candidates,
        skippedCount: skippedCount,
        downloadKeys: downloadKeys,
      );
    });

    // Least recently attempted first. Every attempt re-saves its row with a
    // new deferral time, so a bounded pass rotates through the ledger.
    candidates.sort((a, b) {
      final byAttempt = a.deferredAt.compareTo(b.deferredAt);

      return byAttempt != 0 ? byAttempt : _dependencyOrder(a, b);
    });

    // Downloads are heavier than fetches and have their own per-pass limit.
    final batch = <InboundDeferredRecord>[];
    var plannedDownloads = 0;

    for (final record in candidates) {
      if (batch.length == maxFetches) {
        break;
      }

      if (downloadKeys.contains(_key(record.entityType, record.entityId))) {
        if (plannedDownloads == maxArtworkDownloads) {
          continue;
        }

        plannedDownloads += 1;
      }

      batch.add(record);
    }

    batch.sort(_dependencyOrder);

    var appliedCount = 0;
    var installedArtworkCount = 0;
    var stillDeferredCount = 0;
    var unresolvedCount = 0;
    final failures = <InboundReplayFailure>[];

    for (var index = 0; index < batch.length; index++) {
      final record = batch[index];

      try {
        final current = await reader.fetchCurrent(
          userId: normalizedUserId,
          entityType: record.entityType,
          entityId: record.entityId,
        );

        // Download and decoding finish before the record's transaction
        // starts, so no database mutation is held open during them.
        final install =
            downloadKeys.contains(_key(record.entityType, record.entityId))
            ? await _recoverArtworkFor(record, current)
            : null;

        final _ItemOutcome outcome;
        var installed = false;

        try {
          outcome = await mutationRunner.run((context) async {
            final result = await _replayRecord(
              context: context,
              record: record,
              current: current,
              install: install,
            );

            installed =
                install != null &&
                (await context.artworkAssetRepository.getById(
                      record.entityId,
                    ))?.filePath ==
                    install.filePath;

            return result;
          });
        } catch (_) {
          // Nothing committed, so the downloaded file is not referenced.
          await _discardRecoveredArtwork(install, record);
          rethrow;
        }

        if (installed) {
          installedArtworkCount += 1;
        } else {
          // Not adopted, for example because another operation installed
          // this artwork first. Only our own file is removed.
          await _discardRecoveredArtwork(install, record);
        }

        switch (outcome) {
          case _ItemOutcome.applied:
          case _ItemOutcome.alreadyReconciled:
            appliedCount += 1;
          case _ItemOutcome.deferred:
            stillDeferredCount += 1;
          case _ItemOutcome.unresolved:
            unresolvedCount += 1;
        }
      } catch (error, stackTrace) {
        // The record's transaction rolled back, so the obligation is intact.
        // Requeue it separately so a persistent failure cannot hold the
        // front of the queue and starve later records.
        var requeued = false;
        Object? requeueError;
        StackTrace? requeueStackTrace;

        try {
          requeued = await mutationRunner.run(
            (context) => _requeue(context, record),
          );
        } catch (requeueFailure, requeueTrace) {
          requeueError = requeueFailure;
          requeueStackTrace = requeueTrace;
        }

        final failure = InboundReplayFailure(
          record: record,
          error: error,
          stackTrace: stackTrace,
          requeued: requeued,
          requeueError: requeueError,
          requeueStackTrace: requeueStackTrace,
        );

        failures.add(failure);
        _logFailure(
          failure,
          attempt: index + 1,
          batchSize: batch.length,
          maxFetches: maxFetches,
        );
      }
    }

    return InboundReplayResult(
      appliedCount: appliedCount,
      stillDeferredCount: stillDeferredCount,
      skippedCount: skippedCount,
      unresolvedCount: unresolvedCount,
      notAttemptedCount: candidates.length - batch.length,
      installedArtworkCount: installedArtworkCount,
      failures: List.unmodifiable(failures),
    );
  }

  /// Downloads artwork only for a live cloud row that matches the deferred
  /// identity and is not older than the deferral. Anything else is left to
  /// the transaction, which keeps or resolves the obligation without bytes.
  Future<OwnedArtworkImport?> _recoverArtworkFor(
    InboundDeferredRecord record,
    CloudSyncItem? current,
  ) async {
    final recover = recoverArtwork;
    final cloudRecord = current?.record;
    final revision = current?.serverRevision;

    if (recover == null ||
        cloudRecord is! CloudArtworkAssetRecord ||
        cloudRecord.isDeleted ||
        cloudRecord.userId != record.userId ||
        cloudRecord.id != record.entityId ||
        revision == null ||
        revision < record.serverRevision) {
      return null;
    }

    return recover(cloudRecord);
  }

  Future<void> _discardRecoveredArtwork(
    OwnedArtworkImport? install,
    InboundDeferredRecord record,
  ) async {
    if (install == null) {
      return;
    }

    try {
      await install.discard();
    } catch (error) {
      // The file is unreferenced either way; report it, keep the outcome.
      _logReplay(
        'Discarding recovered artwork failed: '
        'entityType=${record.entityType.name} '
        'entityId=${record.entityId} '
        'error=${error.runtimeType}',
      );
    }
  }

  Future<_ItemOutcome> _replayRecord({
    required SyncMutationContext context,
    required InboundDeferredRecord record,
    required CloudSyncItem? current,
    OwnedArtworkImport? install,
  }) async {
    final revision = current?.serverRevision;

    if (current == null ||
        revision == null ||
        revision < record.serverRevision) {
      // No cloud row at or beyond the deferred revision can be verified.
      // Keep the obligation and move it to the back of the queue.
      await _requeue(context, record);

      return _ItemOutcome.unresolved;
    }

    if (current.record.userId != record.userId ||
        current.record.id != record.entityId ||
        _entityTypeForRecord(current.record) != record.entityType) {
      throw StateError(
        'Replayed cloud record ${current.record.id} does not match its '
        'deferred identity.',
      );
    }

    return _reconcileItem(
      context: context,
      userId: record.userId,
      entityType: record.entityType,
      item: current,
      artworkInstall: install,
    );
  }

  /// Records recovered artwork as a local asset when none exists yet.
  ///
  /// Runs inside the reconciling transaction, after revision and hold
  /// checks, so the asset, baseline and ledger change commit together. An
  /// asset installed concurrently by another operation is left untouched.
  Future<void> _installRecoveredArtwork({
    required SyncMutationContext context,
    required CloudOwnedRecord record,
    required OwnedArtworkImport install,
  }) async {
    if (record is! CloudArtworkAssetRecord || record.isDeleted) {
      throw StateError('Recovered artwork must match a live artwork row.');
    }

    if (await context.artworkAssetRepository.getById(record.id) != null) {
      return;
    }

    await context.artworkAssetRepository.create(
      ArtworkAsset(
        id: record.id,
        filePath: install.filePath,
        normalizedPath: TextNormalizer.normalizePath(install.filePath),
        createdAt: record.createdAt,
        updatedAt: record.updatedAt,
      ),
    );
  }

  /// Moves [record] to the back of the replay queue only while the ledger
  /// still holds that exact revision. A newer deferral is never
  /// overwritten and a cleared obligation is never revived.
  Future<bool> _requeue(
    SyncMutationContext context,
    InboundDeferredRecord record,
  ) {
    final deferredRepository = context.inboundDeferredRecordRepository;

    if (deferredRepository == null) {
      throw StateError('Deferred replay requires a deferred record ledger.');
    }

    return deferredRepository.requeueDeferral(
      userId: record.userId,
      entityType: record.entityType,
      entityId: record.entityId,
      serverRevision: record.serverRevision,
      deferredAt: _now().toUtc(),
    );
  }

  /// Logs one failed replay with identifiers and retry context only. Error
  /// messages and cloud payloads are never logged, since either may carry
  /// library content.
  void _logFailure(
    InboundReplayFailure failure, {
    required int attempt,
    required int batchSize,
    required int maxFetches,
  }) {
    final record = failure.record;
    final requeueError = failure.requeueError;

    final queue = requeueError != null
        ? 'requeueFailed(${requeueError.runtimeType})'
        : failure.requeued
        ? 'requeued'
        : 'unchanged(obligation changed concurrently)';

    _logReplay(
      'Deferred replay failed: '
      'entityType=${record.entityType.name} '
      'entityId=${record.entityId} '
      'deferredRevision=${record.serverRevision} '
      'reason=${record.reason.name} '
      'error=${failure.error.runtimeType} '
      'previousAttemptAt=${record.deferredAt.toUtc().toIso8601String()} '
      'attempt=$attempt/$batchSize '
      'fetchLimit=$maxFetches '
      'queue=$queue',
    );
  }

  Future<bool> _blockerStillHolds(
    SyncMutationContext context,
    InboundDeferredRecord record,
    Set<String> pendingKeys,
  ) async {
    if (pendingKeys.contains(_key(record.entityType, record.entityId))) {
      return true;
    }

    if (record.entityType == CloudDataEntity.artist) {
      final writeJournal = await context.artistWriteJournalRepository
          ?.findUnresolved(userId: record.userId, artistId: record.entityId);
      final dependencyJournal = await context.artistDependencyJournalRepository
          ?.findUnresolved(userId: record.userId, artistId: record.entityId);

      if (writeJournal != null || dependencyJournal != null) {
        return true;
      }
    }

    return switch (record.reason) {
      // Without artwork recovery, bytes only arrive with a local asset.
      InboundDeferralReason.artworkDownloadRequired =>
        recoverArtwork == null &&
            await context.artworkAssetRepository.getById(record.entityId) ==
                null,

      // Local deletion is never automatic. Only a tombstone for an entity
      // that no longer exists locally can be reconciled.
      InboundDeferralReason.tombstoneRequiresLocalDeletion =>
        await _existsLocally(context, record.entityType, record.entityId),

      // Parents and artwork can only be checked against the fetched row.
      _ => false,
    };
  }

  Future<bool> _existsLocally(
    SyncMutationContext context,
    CloudDataEntity entityType,
    String entityId,
  ) async {
    final Object? existing = switch (entityType) {
      CloudDataEntity.artworkAsset =>
        await context.artworkAssetRepository.getById(entityId),
      CloudDataEntity.artist => await context.artistRepository.getById(
        entityId,
      ),
      CloudDataEntity.album => await context.albumRepository.getById(entityId),
      CloudDataEntity.albumEdition =>
        await context.albumEditionRepository.getById(entityId),
      CloudDataEntity.song => await context.songRepository.getById(entityId),
    };

    return existing != null;
  }

  static String _key(CloudDataEntity entityType, String entityId) {
    return '${entityType.name}:$entityId';
  }

  static int _dependencyOrder(
    InboundDeferredRecord a,
    InboundDeferredRecord b,
  ) {
    final byType = _replayOrder
        .indexOf(a.entityType)
        .compareTo(_replayOrder.indexOf(b.entityType));

    if (byType != 0) {
      return byType;
    }

    final byTime = a.serverUpdatedAt.compareTo(b.serverUpdatedAt);

    return byTime != 0 ? byTime : a.entityId.compareTo(b.entityId);
  }

  /// Parents before children, so a parent cleared in this pass unblocks
  /// its children in the same pass.
  static const List<CloudDataEntity> _replayOrder = [
    CloudDataEntity.artworkAsset,
    CloudDataEntity.artist,
    CloudDataEntity.album,
    CloudDataEntity.albumEdition,
    CloudDataEntity.song,
  ];

  /// Reconciles one verified cloud revision inside [context].
  ///
  /// Shared by cursor pages and deferred replay so both apply the same
  /// revision, hold and ledger rules. Never moves the cursor.
  Future<_ItemOutcome> _reconcileItem({
    required SyncMutationContext context,
    required String userId,
    required CloudDataEntity entityType,
    required CloudSyncItem item,
    OwnedArtworkImport? artworkInstall,
  }) async {
    final baselineRepository = context.cloudRevisionBaselineRepository;

    if (baselineRepository == null) {
      throw StateError(
        'Inbound reconciliation requires a cloud revision baseline repository.',
      );
    }

    final revision = item.serverRevision;
    if (revision == null || revision < 1) {
      throw StateError(
        'Inbound record ${item.record.id} has no valid server revision.',
      );
    }

    final baseline = await baselineRepository.getRevision(
      userId: userId,
      entityType: entityType,
      entityId: item.record.id,
    );

    final deferredRepository = context.inboundDeferredRecordRepository;

    if (baseline != null && revision <= baseline) {
      // Already reconciled. Any older replay obligation is obsolete.
      await deferredRepository?.clearThroughRevision(
        userId: userId,
        entityType: entityType,
        entityId: item.record.id,
        serverRevision: baseline,
      );

      return _ItemOutcome.alreadyReconciled;
    }

    // Pending local work and unresolved artist journals are holds:
    // the cloud revision is deferred and local data is untouched.
    final holdReason = await _holdReason(
      context: context,
      userId: userId,
      entityType: entityType,
      entityId: item.record.id,
    );

    if (holdReason == null && artworkInstall != null) {
      await _installRecoveredArtwork(
        context: context,
        record: item.record,
        install: artworkInstall,
      );
    }

    final deferralReason =
        holdReason ??
        (await applier.apply(
          record: item.record,
          context: context,
        )).deferralReason;

    if (deferralReason != null) {
      // The cursor may pass this revision only if its replay
      // obligation commits in the same transaction. No baseline
      // is recorded, so a replay still counts as newer.
      if (deferredRepository == null) {
        throw StateError(
          'Inbound record ${item.record.id} cannot be applied yet '
          'and no deferred record repository is available.',
        );
      }

      await deferredRepository.saveDeferred(
        InboundDeferredRecord(
          userId: userId,
          entityType: entityType,
          entityId: item.record.id,
          serverRevision: revision,
          serverUpdatedAt: item.serverUpdatedAt.toUtc(),
          reason: deferralReason,
          deferredAt: _now().toUtc(),
        ),
      );

      return _ItemOutcome.deferred;
    }

    await baselineRepository.saveObservedRevision(
      userId: userId,
      entityType: entityType,
      entityId: item.record.id,
      serverRevision: revision,
    );

    await deferredRepository?.clearThroughRevision(
      userId: userId,
      entityType: entityType,
      entityId: item.record.id,
      serverRevision: revision,
    );

    return _ItemOutcome.applied;
  }

  Future<InboundDeferralReason?> _holdReason({
    required SyncMutationContext context,
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    final pending = await context.localSyncRepository.getPending(userId);

    if (pending.any(
      (entry) => entry.entityType == entityType && entry.entityId == entityId,
    )) {
      return InboundDeferralReason.pendingLocalMutation;
    }

    if (entityType == CloudDataEntity.artist) {
      final writeJournal = await context.artistWriteJournalRepository
          ?.findUnresolved(userId: userId, artistId: entityId);
      final dependencyJournal = await context.artistDependencyJournalRepository
          ?.findUnresolved(userId: userId, artistId: entityId);

      if (writeJournal != null || dependencyJournal != null) {
        return InboundDeferralReason.unresolvedArtistJournal;
      }
    }

    return null;
  }

  bool _isAfter(CloudSyncPosition candidate, CloudSyncPosition? current) {
    if (current == null) {
      return true;
    }

    final timestampComparison = candidate.serverUpdatedAt.compareTo(
      current.serverUpdatedAt,
    );

    if (timestampComparison != 0) {
      return timestampComparison > 0;
    }

    return candidate.id.compareTo(current.id) > 0;
  }

  CloudDataEntity _entityTypeForRecord(CloudOwnedRecord record) {
    return switch (record) {
      CloudArtworkAssetRecord() => CloudDataEntity.artworkAsset,
      CloudArtistRecord() => CloudDataEntity.artist,
      CloudAlbumRecord() => CloudDataEntity.album,
      CloudAlbumEditionRecord() => CloudDataEntity.albumEdition,
      CloudSongRecord() => CloudDataEntity.song,
      _ => throw ArgumentError.value(
        record,
        'record',
        'Unsupported cloud record type.',
      ),
    };
  }

  CloudSyncPosition? _positionFromCursor(SyncCursor? cursor) {
    if (cursor == null) {
      return null;
    }

    final timestamp = cursor.lastServerUpdatedAt;
    final id = cursor.lastServerId;

    if (timestamp == null && id == null) {
      return null;
    }

    if (timestamp == null || id == null) {
      throw StateError(
        'Sync cursor must contain both lastServerUpdatedAt and lastServerId.',
      );
    }

    return CloudSyncPosition(serverUpdatedAt: timestamp.toUtc(), id: id);
  }
}

enum _ItemOutcome { applied, deferred, alreadyReconciled, unresolved }
