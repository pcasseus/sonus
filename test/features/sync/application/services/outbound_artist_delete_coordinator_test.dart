import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/repositories/cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_delete_committer.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_delete_coordinator.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_write_coordinator.dart';
import 'package:sonus_next/features/sync/data/daos/cloud_revision_baseline_dao.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_artist_receipt_delete_gateway.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SyncMutationTransactionRunner runner;
  late CloudRevisionBaselineRepository baselines;
  late OutboundArtistDeleteCommitter committer;

  final now = DateTime.utc(2026, 10, 17, 12);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextId = 0;

    runner = SyncMutationTransactionRunner(
      appDatabase: appDatabase,
      generateId: () => 'delete-mutation-${++nextId}',
      now: () => now,
    );

    final db = await appDatabase.database;

    baselines = SqliteCloudRevisionBaselineRepository(
      dao: CloudRevisionBaselineDao(db),
    );

    committer = OutboundArtistDeleteCommitter(mutationRunner: runner);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  CloudConditionalWriteResult result(String outcome, int? revision) {
    return CloudConditionalWriteResult.fromRpcRow({
      'outcome': outcome,
      'server_revision': revision,
    });
  }

  Future<SyncOutboxEntry> enqueueDelete() async {
    await runner.run<void>((context) async {
      await context.localSyncRepository.recordDelete(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      );
    });

    final db = await appDatabase.database;
    return (await LocalSyncDao(db).findPending('user-1')).single;
  }

  Future<List<SyncOutboxEntry>> pending() async {
    final db = await appDatabase.database;
    return LocalSyncDao(db).findPending('user-1');
  }

  Future<int?> revision() {
    return baselines.getRevision(
      userId: 'user-1',
      entityType: CloudDataEntity.artist,
      entityId: 'artist-1',
    );
  }

  Future<void> saveRevision(int value) {
    return baselines.saveObservedRevision(
      userId: 'user-1',
      entityType: CloudDataEntity.artist,
      entityId: 'artist-1',
      serverRevision: value,
    );
  }

  OutboundArtistDeleteCoordinator coordinator(ReceiptDeleteCloudArtist delete) {
    return OutboundArtistDeleteCoordinator(
      baselineRepository: baselines,
      deleteArtistWithReceipt: delete,
      committer: committer,
    );
  }

  test('applied deletion commits revision and acknowledgement', () async {
    await saveRevision(7);
    final entry = await enqueueDelete();
    var calls = 0;

    final service = coordinator(({
      required artistId,
      required expectedServerRevision,
      required outboxId,
      required mutationRevision,
      required deletedAt,
    }) async {
      calls++;
      expect(artistId, entry.entityId);
      expect(expectedServerRevision, 7);
      expect(outboxId, entry.id);
      expect(mutationRevision, entry.mutationRevision);
      expect(deletedAt, entry.updatedAt);
      return result('applied', 8);
    });

    await service.push(userId: 'user-1', entry: entry);

    expect(calls, 1);
    expect(await revision(), 8);
    expect(await pending(), isEmpty);
  });

  test('replayed deletion commits revision and acknowledgement', () async {
    await saveRevision(7);
    final entry = await enqueueDelete();

    final service = coordinator(
      ({
        required artistId,
        required expectedServerRevision,
        required outboxId,
        required mutationRevision,
        required deletedAt,
      }) async => result('replayed', 8),
    );

    await service.push(userId: 'user-1', entry: entry);

    expect(await revision(), 8);
    expect(await pending(), isEmpty);
  });

  test('missing baseline prevents all cloud access', () async {
    final entry = await enqueueDelete();
    var calls = 0;

    final service = coordinator(({
      required artistId,
      required expectedServerRevision,
      required outboxId,
      required mutationRevision,
      required deletedAt,
    }) async {
      calls++;
      return result('applied', 2);
    });

    await expectLater(
      service.push(userId: 'user-1', entry: entry),
      throwsStateError,
    );

    expect(calls, 0);
    expect(await revision(), isNull);
    expect(await pending(), hasLength(1));
  });

  test('conflict preserves baseline and pending deletion', () async {
    await saveRevision(7);
    final entry = await enqueueDelete();

    final service = coordinator(
      ({
        required artistId,
        required expectedServerRevision,
        required outboxId,
        required mutationRevision,
        required deletedAt,
      }) async => result('conflict', 11),
    );

    await expectLater(
      service.push(userId: 'user-1', entry: entry),
      throwsA(
        isA<OutboundArtistWriteConflict>()
            .having((e) => e.expectedServerRevision, 'expected', 7)
            .having((e) => e.observedServerRevision, 'observed', 11),
      ),
    );

    expect(await revision(), 7);
    expect((await pending()).single.id, entry.id);
  });

  test('not found cannot acknowledge deletion', () async {
    await saveRevision(7);
    final entry = await enqueueDelete();

    final service = coordinator(
      ({
        required artistId,
        required expectedServerRevision,
        required outboxId,
        required mutationRevision,
        required deletedAt,
      }) async => result('not_found', null),
    );

    await expectLater(
      service.push(userId: 'user-1', entry: entry),
      throwsA(isA<OutboundArtistWriteConflict>()),
    );

    expect(await revision(), 7);
    expect(await pending(), hasLength(1));
  });

  test('ownership mismatch fails before cloud access', () async {
    await saveRevision(7);
    final entry = await enqueueDelete();
    var calls = 0;

    final service = coordinator(({
      required artistId,
      required expectedServerRevision,
      required outboxId,
      required mutationRevision,
      required deletedAt,
    }) async {
      calls++;
      return result('applied', 8);
    });

    await expectLater(
      service.push(userId: 'user-2', entry: entry),
      throwsStateError,
    );

    expect(calls, 0);
    expect(await revision(), 7);
    expect(await pending(), hasLength(1));
  });

  test('unexpected applied revision does not acknowledge', () async {
    await saveRevision(7);
    final entry = await enqueueDelete();

    final service = coordinator(
      ({
        required artistId,
        required expectedServerRevision,
        required outboxId,
        required mutationRevision,
        required deletedAt,
      }) async => result('applied', 9),
    );

    await expectLater(
      service.push(userId: 'user-1', entry: entry),
      throwsStateError,
    );

    expect(await revision(), 7);
    expect(await pending(), hasLength(1));
  });

  test('lost deletion response recovers through receipt gateway', () async {
    await saveRevision(7);
    final entry = await enqueueDelete();

    var calls = 0;

    final gateway = SupabaseArtistReceiptDeleteGateway.forTesting((
      functionName,
      parameters,
    ) async {
      expect(functionName, SupabaseArtistReceiptDeleteGateway.deleteRpcName);

      calls++;

      expect(parameters['p_artist_id'], entry.entityId);
      expect(parameters['p_expected_revision'], 7);
      expect(parameters['p_outbox_id'], entry.id);
      expect(parameters['p_mutation_revision'], entry.mutationRevision);
      expect(
        parameters['p_deleted_at'],
        entry.updatedAt.toUtc().toIso8601String(),
      );

      if (calls == 1) {
        // Simulate a committed deletion with a lost HTTP response.
        throw StateError('Simulated deletion response lost');
      }

      return [
        {'outcome': 'replayed', 'server_revision': 8},
      ];
    });

    final service = coordinator(gateway.deleteArtist);

    await expectLater(
      service.push(userId: 'user-1', entry: entry),
      throwsStateError,
    );

    expect(calls, 1);
    expect(await revision(), 7);

    final afterFailure = await pending();
    expect(afterFailure, hasLength(1));
    expect(afterFailure.single.id, entry.id);
    expect(afterFailure.single.mutationRevision, entry.mutationRevision);

    await service.push(userId: 'user-1', entry: afterFailure.single);

    expect(calls, 2);
    expect(await revision(), 8);
    expect(await pending(), isEmpty);
  });

  test('newer local upsert survives in-flight deletion', () async {
    await saveRevision(7);
    final entry = await enqueueDelete();

    final started = Completer<void>();
    final release = Completer<void>();

    final service = coordinator(({
      required artistId,
      required expectedServerRevision,
      required outboxId,
      required mutationRevision,
      required deletedAt,
    }) async {
      started.complete();
      await release.future;
      return result('applied', 8);
    });

    final uploading = service.push(userId: 'user-1', entry: entry);

    await started.future;

    try {
      await runner.run<void>((context) async {
        await context.localSyncRepository.recordUpsert(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        );
      });
    } finally {
      release.complete();
    }

    await uploading;

    expect(await revision(), 8);

    final remaining = await pending();

    expect(remaining, hasLength(1));
    expect(remaining.single.id, entry.id);
    expect(remaining.single.mutationRevision, 2);
    expect(remaining.single.operation, SyncOutboxOperation.upsert);
  });
}
