import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_write_committer.dart';
import 'package:sonus_next/features/sync/data/daos/cloud_revision_baseline_dao.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SyncMutationTransactionRunner runner;
  late OutboundArtistWriteCommitter committer;

  final now = DateTime.utc(2026, 10, 17, 12);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextId = 0;
    runner = SyncMutationTransactionRunner(
      appDatabase: appDatabase,
      generateId: () => 'mutation-${++nextId}',
      now: () => now,
    );

    committer = OutboundArtistWriteCommitter(mutationRunner: runner);
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

  Future<SyncOutboxEntry> enqueueArtist() async {
    await runner.run<void>((context) async {
      await context.localSyncRepository.recordUpsert(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      );
    });

    final db = await appDatabase.database;
    return (await LocalSyncDao(db).findPending('user-1')).single;
  }

  Future<int?> baseline() async {
    final db = await appDatabase.database;
    return CloudRevisionBaselineDao(db).getRevision(
      userId: 'user-1',
      entityType: CloudDataEntity.artist,
      entityId: 'artist-1',
    );
  }

  test('applied update commits baseline and acknowledgement', () async {
    final entry = await enqueueArtist();

    await committer.commitApplied(
      userId: 'user-1',
      entry: entry,
      result: result('applied', 8),
    );

    final db = await appDatabase.database;

    expect(await baseline(), 8);
    expect(await LocalSyncDao(db).findPending('user-1'), isEmpty);
  });

  test('newer edit survives while successful revision is saved', () async {
    final uploadedEntry = await enqueueArtist();

    await runner.run<void>((context) async {
      await context.localSyncRepository.recordUpsert(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      );
    });

    await committer.commitApplied(
      userId: 'user-1',
      entry: uploadedEntry,
      result: result('applied', 8),
    );

    final db = await appDatabase.database;
    final pending = await LocalSyncDao(db).findPending('user-1');

    expect(await baseline(), 8);
    expect(pending, hasLength(1));
    expect(pending.single.id, uploadedEntry.id);
    expect(pending.single.mutationRevision, 2);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test('conflict cannot advance baseline or remove mutation', () async {
    final entry = await enqueueArtist();

    await expectLater(
      committer.commitApplied(
        userId: 'user-1',
        entry: entry,
        result: result('conflict', 12),
      ),
      throwsStateError,
    );

    final db = await appDatabase.database;

    expect(await baseline(), isNull);
    expect(await LocalSyncDao(db).findPending('user-1'), hasLength(1));
  });

  test('not-found response cannot acknowledge a mutation', () async {
    final entry = await enqueueArtist();

    await expectLater(
      committer.commitApplied(
        userId: 'user-1',
        entry: entry,
        result: result('not_found', null),
      ),
      throwsStateError,
    );

    final db = await appDatabase.database;

    expect(await baseline(), isNull);
    expect(await LocalSyncDao(db).findPending('user-1'), hasLength(1));
  });

  test('rejects incorrect user without changing local state', () async {
    final entry = await enqueueArtist();

    await expectLater(
      committer.commitApplied(
        userId: 'user-2',
        entry: entry,
        result: result('applied', 8),
      ),
      throwsStateError,
    );

    final db = await appDatabase.database;

    expect(await baseline(), isNull);
    expect(await LocalSyncDao(db).findPending('user-1'), hasLength(1));
  });

  test('rejects deletion mutation as artist update', () async {
    final entry = await enqueueArtist();

    final deleteEntry = SyncOutboxEntry(
      id: entry.id,
      userId: entry.userId,
      entityType: entry.entityType,
      entityId: entry.entityId,
      operation: SyncOutboxOperation.delete,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
      mutationRevision: entry.mutationRevision,
    );

    await expectLater(
      committer.commitApplied(
        userId: 'user-1',
        entry: deleteEntry,
        result: result('applied', 8),
      ),
      throwsStateError,
    );

    expect(await baseline(), isNull);
  });
}
