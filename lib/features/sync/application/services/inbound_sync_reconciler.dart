import '../repositories/local_sync_repository.dart';
import '../../domain/models/cloud_records.dart';
import '../../domain/models/inbound_deferred_record.dart';
import '../../domain/models/local_sync_models.dart';
import '../../domain/models/sync_data_contract.dart';
import 'cloud_sync_reader.dart';
import 'inbound_cloud_record_applier.dart';
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
}

class InboundSyncReconciler implements InboundSyncPageReconciler {
  InboundSyncReconciler({
    required this.reader,
    required this.localSyncRepository,
    required this.mutationRunner,
    InboundCloudRecordApplier? applier,
    InboundSyncClock? now,
  }) : applier = applier ?? const InboundCloudRecordApplier(),
       _now = now ?? DateTime.now;

  final CloudSyncReader reader;
  final LocalSyncRepository localSyncRepository;
  final SyncMutationRunner mutationRunner;
  final InboundCloudRecordApplier applier;
  final InboundSyncClock _now;

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

        final pending = await context.localSyncRepository.getPending(
          normalizedUserId,
        );

        final hasPendingLocalMutation = pending.any(
          (entry) =>
              entry.entityType == entityType &&
              entry.entityId == item.record.id,
        );

        if (hasPendingLocalMutation) {
          throw StateError(
            'Inbound record ${item.record.id} conflicts with a pending local mutation.',
          );
        }

        {
          final baseline = await baselineRepository.getRevision(
            userId: normalizedUserId,
            entityType: entityType,
            entityId: item.record.id,
          );

          if (baseline == null || revision > baseline) {
            final result = await applier.apply(
              record: item.record,
              context: context,
            );

            final deferredRepository = context.inboundDeferredRecordRepository;
            final deferralReason = result.deferralReason;

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
                  userId: normalizedUserId,
                  entityType: entityType,
                  entityId: item.record.id,
                  serverRevision: revision,
                  serverUpdatedAt: itemPosition.serverUpdatedAt,
                  reason: deferralReason,
                  deferredAt: _now().toUtc(),
                ),
              );

              deferredCount += 1;
            } else {
              await baselineRepository.saveObservedRevision(
                userId: normalizedUserId,
                entityType: entityType,
                entityId: item.record.id,
                serverRevision: revision,
              );

              await deferredRepository?.clearThroughRevision(
                userId: normalizedUserId,
                entityType: entityType,
                entityId: item.record.id,
                serverRevision: revision,
              );
            }
          }
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
