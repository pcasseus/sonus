import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_gateway.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/outbound_conflict_resolution_service.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/inbound_deferred_record.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/outbound_sync_conflict.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

// SN-47 A2 item 2: explicit, deterministic conflict resolution against
// real SQLite transactions.
void main() {
  sqfliteFfiInit();

  final now = DateTime.utc(2026, 10, 23, 12);

  late AppDatabase appDatabase;
  late SyncMutationTransactionRunner runner;
  late _CurrentRowGateway gateway;
  late OutboundConflictResolutionService service;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await appDatabase.database;

    var nextId = 0;
    runner = SyncMutationTransactionRunner(
      appDatabase: appDatabase,
      generateId: () => 'outbox_${nextId++}',
      now: () => now,
    );
    gateway = _CurrentRowGateway();
    service = OutboundConflictResolutionService(
      mutationRunner: runner,
      cloudSyncGateway: gateway,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  CloudArtistRecord cloudArtist({DateTime? deletedAt, String? header}) {
    return CloudArtistRecord(
      id: 'artist-1',
      userId: 'u1',
      name: 'Cloud Name',
      canonicalName: 'cloud name',
      headerArtworkId: header,
      createdAt: DateTime.utc(2026, 10, 1),
      updatedAt: DateTime.utc(2026, 10, 20),
      deletedAt: deletedAt,
    );
  }

  /// Local artist edit pending against stale baseline 3, cloud at 6.
  Future<SyncOutboxEntry> seedConflict({
    SyncOutboxOperation operation = SyncOutboxOperation.upsert,
  }) async {
    return runner.run((context) async {
      await context.artistRepository.create(
        Artist(
          id: 'artist-1',
          name: 'Local Name',
          canonicalName: 'local name',
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 22),
        ),
      );
      await context.cloudRevisionBaselineRepository!.saveObservedRevision(
        userId: 'u1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
        serverRevision: 3,
      );

      if (operation == SyncOutboxOperation.upsert) {
        await context.localSyncRepository.recordUpsert(
          userId: 'u1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        );
      } else {
        await context.localSyncRepository.recordDelete(
          userId: 'u1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        );
      }

      await context.inboundDeferredRecordRepository!.saveDeferred(
        InboundDeferredRecord(
          userId: 'u1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
          serverRevision: 6,
          serverUpdatedAt: now,
          reason: InboundDeferralReason.pendingLocalMutation,
          deferredAt: now,
        ),
      );

      final entry = (await context.localSyncRepository.getPending('u1')).single;

      await context.outboundConflictRepository!.record(
        OutboundSyncConflict(
          userId: 'u1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
          outboxId: entry.id,
          mutationRevision: entry.mutationRevision,
          operation: entry.operation,
          expectedServerRevision: 3,
          observedServerRevision: 6,
          observedState: OutboundConflictCloudState.live,
          detectedAt: now,
        ),
      );

      return entry;
    });
  }

  Future<
    ({
      Artist? artist,
      int? baseline,
      List<SyncOutboxEntry> pending,
      OutboundSyncConflict? conflict,
      InboundDeferredRecord? deferral,
    })
  >
  state() {
    return runner.run(
      (context) async => (
        artist: await context.artistRepository.getById('artist-1'),
        baseline: await context.cloudRevisionBaselineRepository!.getRevision(
          userId: 'u1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        ),
        pending: await context.localSyncRepository.getPending('u1'),
        conflict: await context.outboundConflictRepository!.get(
          userId: 'u1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        ),
        deferral: await context.inboundDeferredRecordRepository!.getDeferral(
          userId: 'u1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        ),
      ),
    );
  }

  group('keepLocal', () {
    test('targets the observed revision and keeps the edit pending', () async {
      await seedConflict();
      gateway.current = cloudArtist();
      gateway.revision = 6;

      await service.keepLocal(
        userId: 'u1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      );

      final result = await state();
      expect(result.artist?.name, 'Local Name');
      expect(result.baseline, 6);
      expect(result.pending, hasLength(1));
      expect(result.conflict, isNull);
      expect(result.deferral, isNull);
    });

    test('never revives a tombstoned cloud row', () async {
      await seedConflict();
      gateway.current = cloudArtist(deletedAt: now);
      gateway.revision = 6;

      await expectLater(
        service.keepLocal(
          userId: 'u1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        ),
        throwsStateError,
      );

      final result = await state();
      expect(result.baseline, 3);
      expect(result.conflict, isNotNull);
      expect(result.pending, hasLength(1));
    });

    test('a delete against a tombstone is acknowledged', () async {
      await seedConflict(operation: SyncOutboxOperation.delete);
      gateway.current = cloudArtist(deletedAt: now);
      gateway.revision = 6;

      await service.keepLocal(
        userId: 'u1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      );

      final result = await state();
      expect(result.baseline, 6);
      expect(result.pending, isEmpty);
      expect(result.conflict, isNull);
    });
  });

  group('keepCloud', () {
    test('applies the cloud revision and retires the local edit', () async {
      await seedConflict();
      gateway.current = cloudArtist();
      gateway.revision = 6;

      await service.keepCloud(
        userId: 'u1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      );

      final result = await state();
      expect(result.artist?.name, 'Cloud Name');
      expect(result.baseline, 6);
      expect(result.pending, isEmpty);
      expect(result.conflict, isNull);
      expect(result.deferral, isNull);
    });

    test('an unappliable cloud revision rolls back every change', () async {
      await seedConflict();
      gateway.current = cloudArtist(header: 'missing-artwork');
      gateway.revision = 6;

      await expectLater(
        service.keepCloud(
          userId: 'u1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        ),
        throwsStateError,
      );

      final result = await state();
      expect(result.artist?.name, 'Local Name');
      expect(result.baseline, 3);
      expect(result.pending, hasLength(1));
      expect(result.conflict, isNotNull);
      expect(result.deferral, isNotNull);
    });
  });

  test('a local edit made after the conflict blocks resolution', () async {
    await seedConflict();
    gateway.current = cloudArtist();
    gateway.revision = 6;

    // A newer local edit bumps the outbox mutation revision.
    await runner.run<void>((context) async {
      await context.localSyncRepository.recordUpsert(
        userId: 'u1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      );
    });

    for (final resolve in [service.keepCloud, service.keepLocal]) {
      await expectLater(
        resolve(
          userId: 'u1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        ),
        throwsStateError,
      );
    }

    final result = await state();
    expect(result.artist?.name, 'Local Name');
    expect(result.baseline, 3);
    expect(result.pending.single.mutationRevision, 2);
  });

  test('resolution requires a recorded conflict', () async {
    gateway.current = cloudArtist();
    gateway.revision = 6;

    await expectLater(
      service.keepCloud(
        userId: 'u1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      ),
      throwsStateError,
    );
  });
}

class _CurrentRowGateway implements CloudSyncGateway {
  CloudOwnedRecord? current;
  int revision = 1;

  @override
  Future<CloudSyncItem?> fetchCurrent({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
  }) async {
    final record = current;

    if (record == null || record.userId != userId || record.id != entityId) {
      return null;
    }

    return CloudSyncItem(
      record: record,
      serverUpdatedAt: DateTime.utc(2026, 10, 23),
      serverRevision: revision,
    );
  }

  @override
  Future<CloudConditionalWriteResult> insertIfAbsent(CloudOwnedRecord record) =>
      throw StateError('Resolution never writes to the cloud.');

  @override
  Future<CloudConditionalWriteResult> updateIfRevision(
    CloudOwnedRecord record, {
    required int expectedServerRevision,
  }) => throw StateError('Resolution never writes to the cloud.');

  @override
  Future<CloudConditionalWriteResult> markDeletedIfRevision({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
    required int expectedServerRevision,
  }) => throw StateError('Resolution never writes to the cloud.');

  @override
  Future<void> upsert(CloudOwnedRecord record) =>
      throw StateError('Resolution never writes to the cloud.');

  @override
  Future<void> markDeleted({
    required String userId,
    required CloudDataEntity entityType,
    required String entityId,
    required DateTime deletedAt,
  }) => throw StateError('Resolution never writes to the cloud.');
}
