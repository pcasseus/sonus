import '../../../library/domain/entities/album_edition_track.dart';
import '../../../library/domain/repositories/album_edition_track_repository.dart';
import '../../../library/domain/repositories/song_artist_credit_repository.dart';
import 'package:uuid/uuid.dart';

import '../../../artwork/domain/repositories/artwork_asset_repository.dart';
import '../../../library/domain/metadata/metadata_field_state.dart';
import '../../../library/domain/repositories/metadata_field_state_repository.dart';
import '../../../library/domain/repositories/album_edition_repository.dart';
import '../../../library/domain/repositories/album_repository.dart';
import '../../../library/domain/repositories/artist_repository.dart';
import '../../../library/domain/repositories/song_repository.dart';
import '../../application/mappers/cloud_record_mapper.dart';
import '../../application/repositories/local_sync_repository.dart';
import '../../application/repositories/cloud_revision_baseline_repository.dart';
import '../../application/repositories/outbound_conflict_repository.dart';
import '../../domain/models/cloud_records.dart';
import '../../domain/models/local_sync_models.dart';
import '../../domain/models/outbound_sync_conflict.dart';
import '../../domain/models/sync_data_contract.dart';
import 'cloud_artwork_storage.dart';
import 'cloud_conditional_write_result.dart';
import 'cloud_record_equivalence.dart';
import 'cloud_sync_gateway.dart';
import 'cloud_sync_reader.dart';
import 'outbound_artist_write_coordinator.dart';

/// Handles an explicit artist mutation and owns its acknowledgement.
typedef PushArtistMutation =
    Future<void> Function({
      required String userId,
      required SyncOutboxEntry entry,
      required CloudArtistRecord artist,
    });

/// Ensures a referenced cloud artist exists without acknowledging
/// an explicit artist outbox mutation.
typedef EnsureArtistDependency =
    Future<void> Function({
      required String userId,
      required CloudArtistRecord artist,
    });

/// Handles a guarded artist deletion and its local acknowledgement.
typedef PushArtistDeletion =
    Future<void> Function({
      required String userId,
      required SyncOutboxEntry entry,
    });

/// Reconciles durable artist receipts before reading the regular outbox.
typedef RecoverArtistWrites = Future<void> Function(String userId);

/// Acknowledges a cloud-accepted entry and clears the conflict it resolves
/// in one transaction; see `acknowledgeOutboundMutation`.
typedef AcknowledgeOutboundEntry =
    Future<void> Function({
      required String userId,
      required SyncOutboxEntry entry,
    });

/// A revision-guarded cloud write that did not apply.
///
/// The pending mutation stays queued. The observed revision is
/// diagnostic only and must not be adopted as a local baseline.
class OutboundRecordWriteConflict implements Exception {
  const OutboundRecordWriteConflict({
    required this.entityType,
    required this.entityId,
    required this.outcome,
    required this.expectedServerRevision,
    required this.observedServerRevision,
  });

  final CloudDataEntity entityType;
  final String entityId;
  final CloudConditionalWriteOutcome outcome;
  final int? expectedServerRevision;
  final int? observedServerRevision;

  @override
  String toString() {
    return 'OutboundRecordWriteConflict('
        'entityType: ${entityType.name}, '
        'entityId: $entityId, '
        'outcome: $outcome, '
        'expectedServerRevision: $expectedServerRevision, '
        'observedServerRevision: $observedServerRevision)';
  }
}

/// One outbox entry that could not be completed in a push run.
class OutboundEntryFailure {
  const OutboundEntryFailure({
    required this.entry,
    required this.error,
    required this.stackTrace,
  });

  final SyncOutboxEntry entry;
  final Object error;
  final StackTrace stackTrace;
}

/// Result of a push run whose safety holds all passed.
///
/// Failed entries stay pending. Holds (recovery, ownership and
/// configuration failures) are thrown instead and never reported here.
class OutboundPushReport {
  const OutboundPushReport({required this.failures});

  final List<OutboundEntryFailure> failures;

  bool get isComplete => failures.isEmpty;
}

typedef ArtworkVersionGenerator = String Function();
typedef OutboundClock = DateTime Function();

class OutboundSyncProcessor {
  OutboundSyncProcessor({
    required this.localSyncRepository,
    required this.artistRepository,
    required this.albumRepository,
    required this.albumEditionRepository,
    required this.songRepository,
    required this.metadataFieldStateRepository,
    required this.artworkAssetRepository,
    required this.cloudArtworkStorage,
    required this.cloudSyncGateway,
    this.cloudRevisionBaselineRepository,
    this.pushArtistMutation,
    this.pushArtistDeletion,
    this.ensureArtistDependency,
    this.recoverArtistWrites,
    this.outboundConflictRepository,
    this.acknowledgeEntry,
    this.albumEditionTrackRepository,
    this.songArtistCreditRepository,
    ArtworkVersionGenerator? newArtworkVersion,
    OutboundClock? now,
  }) : _newArtworkVersion = newArtworkVersion ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final LocalSyncRepository localSyncRepository;
  final ArtistRepository artistRepository;
  final AlbumRepository albumRepository;
  final AlbumEditionRepository albumEditionRepository;
  final SongRepository songRepository;
  final MetadataFieldStateRepository metadataFieldStateRepository;
  final ArtworkAssetRepository artworkAssetRepository;
  final CloudArtworkStorage cloudArtworkStorage;
  final CloudSyncGateway cloudSyncGateway;
  final CloudRevisionBaselineRepository? cloudRevisionBaselineRepository;
  final PushArtistMutation? pushArtistMutation;
  final PushArtistDeletion? pushArtistDeletion;
  final EnsureArtistDependency? ensureArtistDependency;
  final RecoverArtistWrites? recoverArtistWrites;
  final OutboundConflictRepository? outboundConflictRepository;

  /// Required with [outboundConflictRepository], so an acknowledged entry
  /// can never leave its conflict behind.
  final AcknowledgeOutboundEntry? acknowledgeEntry;

  /// With these, songs carry every edition listing and their full credits
  /// (SN-45). Without them, songs upload as before.
  final AlbumEditionTrackRepository? albumEditionTrackRepository;
  final SongArtistCreditRepository? songArtistCreditRepository;
  final ArtworkVersionGenerator _newArtworkVersion;
  final OutboundClock _now;

  // Serialize full outbound runs on this processor instance.
  // Recover from failure so subsequent retries can execute.
  Future<void> _pendingPushRun = Future<void>.value();

  /// Pushes every eligible entry and rethrows the first entry failure.
  Future<void> pushPending(String userId) async {
    final report = await pushPendingIsolated(userId);

    if (!report.isComplete) {
      final first = report.failures.first;
      Error.throwWithStackTrace(first.error, first.stackTrace);
    }
  }

  /// Pushes every eligible entry and reports entry failures.
  ///
  /// Safety-hold failures are still thrown before any entry is written.
  Future<OutboundPushReport> pushPendingIsolated(String userId) {
    final current = _pendingPushRun.then((_) => _pushPendingOnce(userId));

    _pendingPushRun = current.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );

    return current;
  }

  Future<OutboundPushReport> _pushPendingOnce(String userId) async {
    final trimmedUserId = userId.trim();

    if (trimmedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be blank.');
    }

    if ((pushArtistMutation == null) !=
        (cloudRevisionBaselineRepository == null)) {
      throw StateError(
        'Guarded artist sync requires coordinator and revision baselines.',
      );
    }

    if (pushArtistDeletion != null &&
        (pushArtistMutation == null ||
            cloudRevisionBaselineRepository == null)) {
      throw StateError(
        'Guarded artist deletion requires guarded artist mutations '
        'and revision baselines.',
      );
    }

    if (ensureArtistDependency != null && pushArtistMutation == null) {
      throw StateError(
        'Artist dependency creation requires guarded artist mutations.',
      );
    }

    if (outboundConflictRepository != null && acknowledgeEntry == null) {
      throw StateError(
        'Durable conflicts require a transactional acknowledgement.',
      );
    }

    final recover = recoverArtistWrites;

    if (recover != null) {
      if (pushArtistMutation == null ||
          pushArtistDeletion == null ||
          cloudRevisionBaselineRepository == null) {
        throw StateError(
          'Artist recovery requires guarded mutation, deletion, '
          'and revision baseline handlers.',
        );
      }

      // The journal is authoritative until its receipt is reconciled.
      // A recovery failure must stop all ordinary outbound writes.
      await recover(trimmedUserId);
    }

    final pending = await localSyncRepository.getPending(trimmedUserId);
    final ordered = [...pending]..sort(_compareEntries);

    final ensuredArtworkIds = <String>{};
    final ensuredArtistIds = <String>{};
    final ensuredAlbumIds = <String>{};
    final ensuredAlbumEditionIds = <String>{};
    final ensuredSongIds = <String>{};

    // Ownership is checked for the whole batch before any cloud write.
    for (final entry in ordered) {
      if (entry.userId != trimmedUserId) {
        throw StateError(
          'Outbox entry ${entry.id} does not belong to user $trimmedUserId.',
        );
      }
    }

    final failures = <OutboundEntryFailure>[];

    for (final entry in ordered) {
      try {
        await _pushEntry(
          entry,
          userId: trimmedUserId,
          ensuredArtworkIds: ensuredArtworkIds,
          ensuredArtistIds: ensuredArtistIds,
          ensuredAlbumIds: ensuredAlbumIds,
          ensuredAlbumEditionIds: ensuredAlbumEditionIds,
          ensuredSongIds: ensuredSongIds,
        );
      } catch (error, stackTrace) {
        // A failed entry stays pending. Later entries still run; any that
        // depend on it re-attempt the dependency and fail the same way.
        failures.add(
          OutboundEntryFailure(
            entry: entry,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }

    return OutboundPushReport(failures: List.unmodifiable(failures));
  }

  Future<void> _pushEntry(
    SyncOutboxEntry entry, {
    required String userId,
    required Set<String> ensuredArtworkIds,
    required Set<String> ensuredArtistIds,
    required Set<String> ensuredAlbumIds,
    required Set<String> ensuredAlbumEditionIds,
    required Set<String> ensuredSongIds,
  }) async {
    switch (entry.operation) {
      case SyncOutboxOperation.upsert:
        await _pushUpsert(
          entry,
          userId: userId,
          ensuredArtworkIds: ensuredArtworkIds,
          ensuredArtistIds: ensuredArtistIds,
          ensuredAlbumIds: ensuredAlbumIds,
          ensuredAlbumEditionIds: ensuredAlbumEditionIds,
          ensuredSongIds: ensuredSongIds,
        );

      case SyncOutboxOperation.delete:
        final guardedDeletion = pushArtistDeletion;

        if (entry.entityType == CloudDataEntity.artist &&
            guardedDeletion != null) {
          await guardedDeletion(userId: userId, entry: entry);
        } else if (cloudRevisionBaselineRepository != null) {
          await _deleteConditionally(entry, userId: userId);
        } else {
          await cloudSyncGateway.markDeleted(
            userId: userId,
            entityType: entry.entityType,
            entityId: entry.entityId,
            deletedAt: entry.updatedAt,
          );
        }
    }

    final guardedArtistMutation =
        pushArtistMutation != null &&
        entry.entityType == CloudDataEntity.artist &&
        entry.operation == SyncOutboxOperation.upsert;

    final guardedArtistDeletion =
        pushArtistDeletion != null &&
        entry.entityType == CloudDataEntity.artist &&
        entry.operation == SyncOutboxOperation.delete;

    // Guarded artist writes are acknowledged by their committers, which
    // clear the resolved conflict in the same transaction.
    if (!guardedArtistMutation && !guardedArtistDeletion) {
      final acknowledge = acknowledgeEntry;

      if (acknowledge != null) {
        await acknowledge(userId: userId, entry: entry);
      } else {
        await localSyncRepository.markProcessed(
          userId: userId,
          outboxEntryId: entry.id,
          expectedRevision: entry.mutationRevision,
          expectedOperation: entry.operation,
        );
      }
    }
  }

  Future<void> _pushUpsert(
    SyncOutboxEntry entry, {
    required String userId,
    required Set<String> ensuredArtworkIds,
    required Set<String> ensuredArtistIds,
    required Set<String> ensuredAlbumIds,
    required Set<String> ensuredAlbumEditionIds,
    required Set<String> ensuredSongIds,
  }) async {
    switch (entry.entityType) {
      case CloudDataEntity.artworkAsset:
        await _ensureArtwork(
          entry.entityId,
          userId: userId,
          ensuredArtworkIds: ensuredArtworkIds,
          explicitEntry: entry,
        );

      case CloudDataEntity.artist:
        await _ensureArtist(
          entry.entityId,
          userId: userId,
          ensuredArtworkIds: ensuredArtworkIds,
          ensuredArtistIds: ensuredArtistIds,
          explicitEntry: entry,
        );

      case CloudDataEntity.album:
        await _ensureAlbum(
          entry.entityId,
          userId: userId,
          ensuredArtworkIds: ensuredArtworkIds,
          ensuredArtistIds: ensuredArtistIds,
          ensuredAlbumIds: ensuredAlbumIds,
          explicitEntry: entry,
        );

      case CloudDataEntity.albumEdition:
        await _ensureAlbumEdition(
          entry.entityId,
          userId: userId,
          ensuredArtworkIds: ensuredArtworkIds,
          ensuredArtistIds: ensuredArtistIds,
          ensuredAlbumIds: ensuredAlbumIds,
          ensuredAlbumEditionIds: ensuredAlbumEditionIds,
          explicitEntry: entry,
        );

      case CloudDataEntity.song:
        await _ensureSong(
          entry.entityId,
          userId: userId,
          ensuredArtworkIds: ensuredArtworkIds,
          ensuredArtistIds: ensuredArtistIds,
          ensuredAlbumIds: ensuredAlbumIds,
          ensuredAlbumEditionIds: ensuredAlbumEditionIds,
          ensuredSongIds: ensuredSongIds,
          explicitEntry: entry,
        );
    }
  }

  /// Writes a non-artist record without overwriting newer cloud state.
  ///
  /// Without revision baselines this keeps the legacy unconditional
  /// upsert. With baselines, a known revision is compare-and-set and an
  /// unknown one is insert-if-absent. A dependency that already has a
  /// baseline is not rewritten.
  ///
  /// Returns true when the cloud row now holds [record]'s payload, and
  /// false when an existing dependency row was used as is.
  Future<bool> _writeRecord(
    CloudOwnedRecord record, {
    required CloudDataEntity entityType,
    required SyncOutboxEntry? explicitEntry,
  }) async {
    final baselines = cloudRevisionBaselineRepository;

    if (baselines == null) {
      await cloudSyncGateway.upsert(record);
      return true;
    }

    final baseline = await baselines.getRevision(
      userId: record.userId,
      entityType: entityType,
      entityId: record.id,
    );

    if (baseline != null && baseline < 1) {
      throw StateError('Invalid stored server revision for ${record.id}.');
    }

    if (explicitEntry == null && baseline != null) {
      return false;
    }

    final result = baseline == null
        ? await cloudSyncGateway.insertIfAbsent(record)
        : await cloudSyncGateway.updateIfRevision(
            record,
            expectedServerRevision: baseline,
          );

    final expectedRevision = baseline == null ? 1 : baseline + 1;

    switch (result.outcome) {
      case CloudConditionalWriteOutcome.applied:
      case CloudConditionalWriteOutcome.replayed:
        if (result.serverRevision != expectedRevision) {
          throw StateError(
            'Unexpected applied ${entityType.name} revision: '
            '${result.serverRevision}; expected $expectedRevision.',
          );
        }

        await baselines.saveObservedRevision(
          userId: record.userId,
          entityType: entityType,
          entityId: record.id,
          serverRevision: expectedRevision,
        );

        return true;

      case CloudConditionalWriteOutcome.conflict:
      case CloudConditionalWriteOutcome.notFound:
        return _reconcileRejectedWrite(
          record,
          entityType: entityType,
          explicitEntry: explicitEntry,
          baseline: baseline,
          expectedRevision: expectedRevision,
          result: result,
        );
    }
  }

  /// Handles a rejected conditional write.
  ///
  /// The cloud row is adopted only when it is owned, live, at or beyond
  /// the revision this write would have produced, and canonically
  /// identical to [record]. That covers a lost response and a cloud row
  /// that already holds this exact payload. Anything else is a durable
  /// conflict and the outbox entry stays pending.
  Future<bool> _reconcileRejectedWrite(
    CloudOwnedRecord record, {
    required CloudDataEntity entityType,
    required SyncOutboxEntry? explicitEntry,
    required int? baseline,
    required int expectedRevision,
    required CloudConditionalWriteResult result,
  }) async {
    final current = await cloudSyncGateway.fetchCurrent(
      userId: record.userId,
      entityType: entityType,
      entityId: record.id,
    );

    final currentRevision = current?.serverRevision;

    if (current != null &&
        currentRevision != null &&
        current.record.userId == record.userId &&
        !current.record.isDeleted &&
        currentRevision >= expectedRevision &&
        CloudRecordEquivalence.isEquivalent(current.record, record)) {
      await cloudRevisionBaselineRepository!.saveObservedRevision(
        userId: record.userId,
        entityType: entityType,
        entityId: record.id,
        serverRevision: currentRevision,
      );

      return true;
    }

    // A dependency only needs a live row. Its content is not adopted, and
    // a child is never written under a tombstoned parent.
    if (explicitEntry == null &&
        baseline == null &&
        current != null &&
        current.record.userId == record.userId &&
        !current.record.isDeleted) {
      return false;
    }

    if (explicitEntry != null) {
      await _recordConflict(
        entry: explicitEntry,
        expectedServerRevision: baseline,
        current: current,
      );
    }

    throw OutboundRecordWriteConflict(
      entityType: entityType,
      entityId: record.id,
      outcome: result.outcome,
      expectedServerRevision: baseline,
      observedServerRevision: currentRevision ?? result.serverRevision,
    );
  }

  /// Tombstones a cloud row only from a verified revision.
  ///
  /// A row that is already a tombstone or absent satisfies the deletion.
  /// A live row that is newer than, or unknown to, local state is never
  /// tombstoned; it becomes a durable conflict.
  Future<void> _deleteConditionally(
    SyncOutboxEntry entry, {
    required String userId,
  }) async {
    final baselines = cloudRevisionBaselineRepository!;

    final baseline = await baselines.getRevision(
      userId: userId,
      entityType: entry.entityType,
      entityId: entry.entityId,
    );

    if (baseline != null && baseline < 1) {
      throw StateError('Invalid stored server revision for ${entry.entityId}.');
    }

    CloudConditionalWriteResult? result;

    if (baseline != null) {
      result = await cloudSyncGateway.markDeletedIfRevision(
        userId: userId,
        entityType: entry.entityType,
        entityId: entry.entityId,
        deletedAt: entry.updatedAt,
        expectedServerRevision: baseline,
      );

      if (result.outcome == CloudConditionalWriteOutcome.applied ||
          result.outcome == CloudConditionalWriteOutcome.replayed) {
        if (result.serverRevision != baseline + 1) {
          throw StateError(
            'Unexpected deleted ${entry.entityType.name} revision: '
            '${result.serverRevision}; expected ${baseline + 1}.',
          );
        }

        await baselines.saveObservedRevision(
          userId: userId,
          entityType: entry.entityType,
          entityId: entry.entityId,
          serverRevision: baseline + 1,
        );

        return;
      }
    }

    final current = await cloudSyncGateway.fetchCurrent(
      userId: userId,
      entityType: entry.entityType,
      entityId: entry.entityId,
    );

    if (current == null) {
      // Nothing owned by this account exists to delete.
      return;
    }

    final currentRevision = current.serverRevision;

    if (current.record.isDeleted && currentRevision != null) {
      await baselines.saveObservedRevision(
        userId: userId,
        entityType: entry.entityType,
        entityId: entry.entityId,
        serverRevision: currentRevision,
      );

      return;
    }

    await _recordConflict(
      entry: entry,
      expectedServerRevision: baseline,
      current: current,
    );

    throw OutboundRecordWriteConflict(
      entityType: entry.entityType,
      entityId: entry.entityId,
      outcome: result?.outcome ?? CloudConditionalWriteOutcome.conflict,
      expectedServerRevision: baseline,
      observedServerRevision: currentRevision,
    );
  }

  Future<void> _recordConflict({
    required SyncOutboxEntry entry,
    required int? expectedServerRevision,
    required CloudSyncItem? current,
  }) async {
    final repository = outboundConflictRepository;

    if (repository == null) {
      return;
    }

    await repository.record(
      OutboundSyncConflict(
        userId: entry.userId!,
        entityType: entry.entityType,
        entityId: entry.entityId,
        outboxId: entry.id,
        mutationRevision: entry.mutationRevision,
        operation: entry.operation,
        expectedServerRevision: expectedServerRevision,
        observedServerRevision: current?.serverRevision,
        observedState: current == null
            ? OutboundConflictCloudState.absent
            : current.record.isDeleted
            ? OutboundConflictCloudState.tombstoned
            : OutboundConflictCloudState.live,
        detectedAt: _now().toUtc(),
      ),
    );
  }

  Future<void> _ensureArtwork(
    String artworkId, {
    required String userId,
    required Set<String> ensuredArtworkIds,
    SyncOutboxEntry? explicitEntry,
  }) async {
    final normalizedArtworkId = artworkId.trim();

    if (normalizedArtworkId.isEmpty ||
        ensuredArtworkIds.contains(normalizedArtworkId)) {
      return;
    }

    final entity = await artworkAssetRepository.getById(normalizedArtworkId);

    if (entity == null) {
      throw StateError(
        'Artwork asset $normalizedArtworkId is missing for sync.',
      );
    }

    final baselines = cloudRevisionBaselineRepository;

    if (baselines == null) {
      final storageObjectKey = await cloudArtworkStorage.upload(
        userId: userId,
        artworkAsset: entity,
      );

      await _writeRecord(
        CloudRecordMapper.artworkAsset(
          artworkAsset: entity,
          userId: userId,
          storageObjectKey: storageObjectKey,
        ),
        entityType: CloudDataEntity.artworkAsset,
        explicitEntry: explicitEntry,
      );

      ensuredArtworkIds.add(normalizedArtworkId);
      return;
    }

    if (explicitEntry == null) {
      // An artwork dependency that already exists in the cloud is used
      // as is: never re-uploaded and never rewritten.
      final baseline = await baselines.getRevision(
        userId: userId,
        entityType: CloudDataEntity.artworkAsset,
        entityId: normalizedArtworkId,
      );

      if (baseline != null) {
        ensuredArtworkIds.add(normalizedArtworkId);
        return;
      }

      final current = await cloudSyncGateway.fetchCurrent(
        userId: userId,
        entityType: CloudDataEntity.artworkAsset,
        entityId: normalizedArtworkId,
      );

      if (current != null && !current.record.isDeleted) {
        ensuredArtworkIds.add(normalizedArtworkId);
        return;
      }
    }

    // Immutable keys: a rejected row write cannot alter the bytes behind
    // the accepted row. An explicit entry reuses one key per mutation so
    // a lost response can be proven by canonical equivalence.
    final version = explicitEntry == null
        ? _newArtworkVersion()
        : '${explicitEntry.id}-r${explicitEntry.mutationRevision}';

    final storageObjectKey = await cloudArtworkStorage.uploadImmutable(
      userId: userId,
      artworkAsset: entity,
      version: version,
    );

    final bool accepted;

    try {
      accepted = await _writeRecord(
        CloudRecordMapper.artworkAsset(
          artworkAsset: entity,
          userId: userId,
          storageObjectKey: storageObjectKey,
        ),
        entityType: CloudDataEntity.artworkAsset,
        explicitEntry: explicitEntry,
      );
    } catch (_) {
      await _discardUnreferencedArtwork(
        userId: userId,
        artworkId: normalizedArtworkId,
        objectKey: storageObjectKey,
      );
      rethrow;
    }

    if (!accepted) {
      await _discardUnreferencedArtwork(
        userId: userId,
        artworkId: normalizedArtworkId,
        objectKey: storageObjectKey,
      );
    }

    ensuredArtworkIds.add(normalizedArtworkId);
  }

  /// Best-effort removal of an uploaded object that the current cloud row
  /// does not reference. An object the row does reference is never removed.
  Future<void> _discardUnreferencedArtwork({
    required String userId,
    required String artworkId,
    required String objectKey,
  }) async {
    try {
      final current = await cloudSyncGateway.fetchCurrent(
        userId: userId,
        entityType: CloudDataEntity.artworkAsset,
        entityId: artworkId,
      );

      final record = current?.record;

      if (record is CloudArtworkAssetRecord &&
          record.storageObjectKey == objectKey) {
        return;
      }

      await cloudArtworkStorage.deleteObject(
        userId: userId,
        objectKey: objectKey,
      );
    } catch (_) {
      // An orphaned immutable object is harmless; the write outcome is
      // what the caller must observe.
    }
  }

  Future<void> _ensureOptionalArtwork(
    String? artworkId, {
    required String userId,
    required Set<String> ensuredArtworkIds,
  }) async {
    final normalizedArtworkId = artworkId?.trim();

    if (normalizedArtworkId == null || normalizedArtworkId.isEmpty) {
      return;
    }

    await _ensureArtwork(
      normalizedArtworkId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
    );
  }

  Future<void> _ensureArtist(
    String artistId, {
    required String userId,
    required Set<String> ensuredArtworkIds,
    required Set<String> ensuredArtistIds,
    SyncOutboxEntry? explicitEntry,
  }) async {
    final normalizedArtistId = artistId.trim();

    if (explicitEntry == null &&
        ensuredArtistIds.contains(normalizedArtistId)) {
      return;
    }

    final entity = await artistRepository.getById(normalizedArtistId);

    if (entity == null) {
      throw StateError('Artist $normalizedArtistId is missing for sync.');
    }

    await _ensureOptionalArtwork(
      entity.headerArtworkId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
    );

    await _ensureOptionalArtwork(
      entity.topArtistsArtworkId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
    );

    final metadataFieldStates = await metadataFieldStateRepository.getByEntity(
      entityType: MetadataEntityType.artist,
      entityId: normalizedArtistId,
    );

    final cloudArtist = CloudRecordMapper.artist(
      artist: entity,
      userId: userId,
      metadataFieldStates: metadataFieldStates,
    );

    final guardedPusher = pushArtistMutation;

    if (guardedPusher == null) {
      // Legacy behavior remains in effect until production wiring changes.
      await cloudSyncGateway.upsert(cloudArtist);
    } else if (explicitEntry != null) {
      // The coordinator commits both the cloud revision and acknowledgement.
      try {
        await guardedPusher(
          userId: userId,
          entry: explicitEntry,
          artist: cloudArtist,
        );
      } on OutboundArtistWriteConflict {
        await _recordConflict(
          entry: explicitEntry,
          expectedServerRevision: await cloudRevisionBaselineRepository
              ?.getRevision(
                userId: userId,
                entityType: CloudDataEntity.artist,
                entityId: normalizedArtistId,
              ),
          current: await cloudSyncGateway.fetchCurrent(
            userId: userId,
            entityType: CloudDataEntity.artist,
            entityId: normalizedArtistId,
          ),
        );
        rethrow;
      }
    } else {
      // A dependency cannot unconditionally overwrite an artist.
      final dependencyEnsurer = ensureArtistDependency;

      if (dependencyEnsurer != null) {
        try {
          await dependencyEnsurer(userId: userId, artist: cloudArtist);
        } on OutboundArtistWriteConflict catch (error) {
          // A baseline-less artist that already exists live in the cloud
          // satisfies the dependency. Nothing is adopted or overwritten.
          if (error.outcome != CloudConditionalWriteOutcome.conflict ||
              error.expectedServerRevision != null) {
            rethrow;
          }

          final current = await cloudSyncGateway.fetchCurrent(
            userId: userId,
            entityType: CloudDataEntity.artist,
            entityId: normalizedArtistId,
          );

          if (current == null ||
              current.record.userId != userId ||
              current.record.isDeleted) {
            rethrow;
          }
        }
      } else {
        // Compatibility path for existing guarded processor tests.
        final baselines = cloudRevisionBaselineRepository;

        if (baselines == null) {
          throw StateError('Missing cloud revision baseline repository.');
        }

        final revision = await baselines.getRevision(
          userId: userId,
          entityType: CloudDataEntity.artist,
          entityId: normalizedArtistId,
        );

        if (revision == null || revision < 1) {
          throw StateError(
            'Artist $normalizedArtistId has no reconciled cloud baseline. '
            'Dependency upload deferred.',
          );
        }
      }
    }

    ensuredArtistIds.add(normalizedArtistId);
  }

  Future<void> _ensureAlbum(
    String albumId, {
    required String userId,
    required Set<String> ensuredArtworkIds,
    required Set<String> ensuredArtistIds,
    required Set<String> ensuredAlbumIds,
    SyncOutboxEntry? explicitEntry,
  }) async {
    final normalizedAlbumId = albumId.trim();

    if (ensuredAlbumIds.contains(normalizedAlbumId)) {
      return;
    }

    final entity = await albumRepository.getById(normalizedAlbumId);

    if (entity == null) {
      throw StateError('Album $normalizedAlbumId is missing for sync.');
    }

    await _ensureArtist(
      entity.artistId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
      ensuredArtistIds: ensuredArtistIds,
    );

    final metadataFieldStates = await metadataFieldStateRepository.getByEntity(
      entityType: MetadataEntityType.album,
      entityId: normalizedAlbumId,
    );

    await _writeRecord(
      CloudRecordMapper.album(
        album: entity,
        userId: userId,
        metadataFieldStates: metadataFieldStates,
      ),
      entityType: CloudDataEntity.album,
      explicitEntry: explicitEntry,
    );

    ensuredAlbumIds.add(normalizedAlbumId);
  }

  Future<void> _ensureAlbumEdition(
    String albumEditionId, {
    required String userId,
    required Set<String> ensuredArtworkIds,
    required Set<String> ensuredArtistIds,
    required Set<String> ensuredAlbumIds,
    required Set<String> ensuredAlbumEditionIds,
    SyncOutboxEntry? explicitEntry,
  }) async {
    final normalizedEditionId = albumEditionId.trim();

    if (ensuredAlbumEditionIds.contains(normalizedEditionId)) {
      return;
    }

    final entity = await albumEditionRepository.getById(normalizedEditionId);

    if (entity == null) {
      throw StateError(
        'Album edition $normalizedEditionId is missing for sync.',
      );
    }

    await _ensureAlbum(
      entity.albumId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
      ensuredArtistIds: ensuredArtistIds,
      ensuredAlbumIds: ensuredAlbumIds,
    );

    await _ensureOptionalArtwork(
      entity.artworkId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
    );

    final metadataFieldStates = await metadataFieldStateRepository.getByEntity(
      entityType: MetadataEntityType.albumEdition,
      entityId: normalizedEditionId,
    );

    await _writeRecord(
      CloudRecordMapper.albumEdition(
        albumEdition: entity,
        userId: userId,
        metadataFieldStates: metadataFieldStates,
      ),
      entityType: CloudDataEntity.albumEdition,
      explicitEntry: explicitEntry,
    );

    ensuredAlbumEditionIds.add(normalizedEditionId);
  }

  Future<void> _ensureSong(
    String songId, {
    required String userId,
    required Set<String> ensuredArtworkIds,
    required Set<String> ensuredArtistIds,
    required Set<String> ensuredAlbumIds,
    required Set<String> ensuredAlbumEditionIds,
    required Set<String> ensuredSongIds,
    SyncOutboxEntry? explicitEntry,
  }) async {
    final normalizedSongId = songId.trim();

    if (ensuredSongIds.contains(normalizedSongId)) {
      return;
    }

    final entity = await songRepository.getById(normalizedSongId);

    if (entity == null) {
      throw StateError('Song $normalizedSongId is missing for sync.');
    }

    await _ensureArtist(
      entity.artistId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
      ensuredArtistIds: ensuredArtistIds,
    );

    await _ensureAlbum(
      entity.albumId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
      ensuredArtistIds: ensuredArtistIds,
      ensuredAlbumIds: ensuredAlbumIds,
    );

    await _ensureAlbumEdition(
      entity.albumEditionId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
      ensuredArtistIds: ensuredArtistIds,
      ensuredAlbumIds: ensuredAlbumIds,
      ensuredAlbumEditionIds: ensuredAlbumEditionIds,
    );

    await _ensureOptionalArtwork(
      entity.artworkId,
      userId: userId,
      ensuredArtworkIds: ensuredArtworkIds,
    );

    final metadataFieldStates = await metadataFieldStateRepository.getByEntity(
      entityType: MetadataEntityType.song,
      entityId: normalizedSongId,
    );

    final memberships = await albumEditionTrackRepository?.getBySongId(
      normalizedSongId,
    );

    // Every edition the song is listed on must be in the cloud first.
    for (final membership in memberships ?? const <AlbumEditionTrack>[]) {
      await _ensureAlbumEdition(
        membership.albumEditionId,
        userId: userId,
        ensuredArtworkIds: ensuredArtworkIds,
        ensuredArtistIds: ensuredArtistIds,
        ensuredAlbumIds: ensuredAlbumIds,
        ensuredAlbumEditionIds: ensuredAlbumEditionIds,
      );
    }

    final credits = await songArtistCreditRepository?.getBySongId(
      normalizedSongId,
    );

    await _writeRecord(
      CloudRecordMapper.song(
        song: entity,
        userId: userId,
        metadataFieldStates: metadataFieldStates,
        memberships: memberships,
        credits: credits,
      ),
      entityType: CloudDataEntity.song,
      explicitEntry: explicitEntry,
    );

    ensuredSongIds.add(normalizedSongId);
  }

  int _compareEntries(SyncOutboxEntry left, SyncOutboxEntry right) {
    final leftRank = _dependencyRank(left.entityType);
    final rightRank = _dependencyRank(right.entityType);

    final rankComparison = leftRank.compareTo(rightRank);
    if (rankComparison != 0) {
      return rankComparison;
    }

    final createdComparison = left.createdAt.compareTo(right.createdAt);
    if (createdComparison != 0) {
      return createdComparison;
    }

    return left.id.compareTo(right.id);
  }

  int _dependencyRank(CloudDataEntity entityType) {
    return switch (entityType) {
      CloudDataEntity.artworkAsset => 0,
      CloudDataEntity.artist => 1,
      CloudDataEntity.album => 2,
      CloudDataEntity.albumEdition => 3,
      CloudDataEntity.song => 4,
    };
  }
}
