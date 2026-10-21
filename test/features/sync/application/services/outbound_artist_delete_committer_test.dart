import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_delete_committer.dart';
import 'package:sonus_next/features/sync/data/daos/cloud_revision_baseline_dao.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SyncMutationTransactionRunner runner;
  late OutboundArtistDeleteCommitter committer;

  final now = DateTime.utc(2026, 10, 17, 12);

  setUp(() {
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

  Future<int?> baseline() async {
    final db = await appDatabase.database;

    return CloudRevisionBaselineDao(db).getRevision(
      userId: 'user-1',
      entityType: CloudDataEntity.artist,
      entityId: 'artist-1',
    );
  }

  test('applied deletion commits baseline and acknowledgement', () async {
    final entry = await enqueueDelete();

    await committer.commitApplied(
      userId: 'user-1',
      entry: entry,
      result: result('applied', 8),
    );

    expect(await baseline(), 8);
    expect(await pending(), isEmpty);
  });

  test('replayed deletion commits baseline and acknowledgement', () async {
    final entry = await enqueueDelete();

    await committer.commitApplied(
      userId: 'user-1',
      entry: entry,
      result: result('replayed', 8),
    );

    expect(await baseline(), 8);
    expect(await pending(), isEmpty);
  });

  test('newer upsert survives successful deletion acknowledgement', () async {
    final uploaded = await enqueueDelete();

    await runner.run<void>((context) async {
      await context.localSyncRepository.recordUpsert(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      );
    });

    await committer.commitApplied(
      userId: 'user-1',
      entry: uploaded,
      result: result('applied', 8),
    );

    final remaining = await pending();

    expect(await baseline(), 8);
    expect(remaining, hasLength(1));
    expect(remaining.single.id, uploaded.id);
    expect(remaining.single.mutationRevision, 2);
    expect(remaining.single.operation, SyncOutboxOperation.upsert);
  });

  test('newer deletion survives older deletion acknowledgement', () async {
    final uploaded = await enqueueDelete();

    await runner.run<void>((context) async {
      await context.localSyncRepository.recordDelete(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      );
    });

    await committer.commitApplied(
      userId: 'user-1',
      entry: uploaded,
      result: result('replayed', 8),
    );

    final remaining = await pending();

    expect(await baseline(), 8);
    expect(remaining, hasLength(1));
    expect(remaining.single.id, uploaded.id);
    expect(remaining.single.mutationRevision, 2);
    expect(remaining.single.operation, SyncOutboxOperation.delete);
  });

  test('conflict cannot acknowledge deletion or advance baseline', () async {
    final entry = await enqueueDelete();

    await expectLater(
      committer.commitApplied(
        userId: 'user-1',
        entry: entry,
        result: result('conflict', 12),
      ),
      throwsStateError,
    );

    expect(await baseline(), isNull);
    expect(await pending(), hasLength(1));
  });

  test('not found cannot acknowledge deletion', () async {
    final entry = await enqueueDelete();

    await expectLater(
      committer.commitApplied(
        userId: 'user-1',
        entry: entry,
        result: result('not_found', null),
      ),
      throwsStateError,
    );

    expect(await baseline(), isNull);
    expect(await pending(), hasLength(1));
  });

  test('wrong owner cannot acknowledge deletion', () async {
    final entry = await enqueueDelete();

    await expectLater(
      committer.commitApplied(
        userId: 'user-2',
        entry: entry,
        result: result('applied', 8),
      ),
      throwsStateError,
    );

    expect(await baseline(), isNull);
    expect(await pending(), hasLength(1));
  });

  test('upsert entry cannot be acknowledged as deletion', () async {
    final deletion = await enqueueDelete();

    final upsertEntry = SyncOutboxEntry(
      id: deletion.id,
      userId: deletion.userId,
      entityType: deletion.entityType,
      entityId: deletion.entityId,
      operation: SyncOutboxOperation.upsert,
      createdAt: deletion.createdAt,
      updatedAt: deletion.updatedAt,
      mutationRevision: deletion.mutationRevision,
    );

    await expectLater(
      committer.commitApplied(
        userId: 'user-1',
        entry: upsertEntry,
        result: result('applied', 8),
      ),
      throwsStateError,
    );

    expect(await baseline(), isNull);
    expect(await pending(), hasLength(1));
  });

  test('invalid verified revision cannot acknowledge deletion', () async {
    final entry = await enqueueDelete();

    expect(() => result('replayed', null), throwsStateError);

    expect(await baseline(), isNull);

    final remaining = await pending();

    expect(remaining, hasLength(1));
    expect(remaining.single.id, entry.id);
    expect(remaining.single.mutationRevision, entry.mutationRevision);
    expect(remaining.single.operation, SyncOutboxOperation.delete);
  });
}
