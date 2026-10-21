import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_dependency_ensurer.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_write_coordinator.dart';
import 'package:sonus_next/features/sync/data/daos/cloud_revision_baseline_dao.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SyncMutationTransactionRunner runner;
  late SqliteCloudRevisionBaselineRepository baselines;

  final now = DateTime.utc(2026, 10, 17, 18);

  setUp(() async {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    runner = SyncMutationTransactionRunner(
      appDatabase: database,
      generateId: () => 'dependency-mutation',
      now: () => now,
    );

    final db = await database.database;

    baselines = SqliteCloudRevisionBaselineRepository(
      dao: CloudRevisionBaselineDao(db),
    );
  });

  tearDown(() async {
    await database.close();
  });

  CloudArtistRecord artist({String userId = 'user-1'}) {
    return CloudArtistRecord(
      id: 'artist-1',
      userId: userId,
      name: 'Dependency Artist',
      canonicalName: 'dependency artist',
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<int?> revision() {
    return baselines.getRevision(
      userId: 'user-1',
      entityType: CloudDataEntity.artist,
      entityId: 'artist-1',
    );
  }

  test('creates absent dependency and records its baseline', () async {
    var calls = 0;

    final service = OutboundArtistDependencyEnsurer(
      baselineRepository: baselines,
      mutationRunner: runner,
      createArtist: ({required artist}) async {
        calls++;

        return const CloudConditionalWriteResult(
          outcome: CloudConditionalWriteOutcome.applied,
          serverRevision: 1,
        );
      },
    );

    await service.ensure(userId: 'user-1', artist: artist());

    expect(calls, 1);
    expect(await revision(), 1);
  });

  test('known baseline skips cloud creation', () async {
    await baselines.saveObservedRevision(
      userId: 'user-1',
      entityType: CloudDataEntity.artist,
      entityId: 'artist-1',
      serverRevision: 5,
    );

    var calls = 0;

    final service = OutboundArtistDependencyEnsurer(
      baselineRepository: baselines,
      mutationRunner: runner,
      createArtist: ({required artist}) async {
        calls++;
        throw StateError('Creation was not expected.');
      },
    );

    await service.ensure(userId: 'user-1', artist: artist());

    expect(calls, 0);
    expect(await revision(), 5);
  });

  test('cloud conflict preserves missing baseline', () async {
    final service = OutboundArtistDependencyEnsurer(
      baselineRepository: baselines,
      mutationRunner: runner,
      createArtist: ({required artist}) async {
        return const CloudConditionalWriteResult(
          outcome: CloudConditionalWriteOutcome.conflict,
          serverRevision: 9,
        );
      },
    );

    await expectLater(
      service.ensure(userId: 'user-1', artist: artist()),
      throwsA(isA<OutboundArtistWriteConflict>()),
    );

    expect(await revision(), isNull);
  });

  test('dependency creation never acknowledges local artist edit', () async {
    await runner.run<void>((context) async {
      await context.localSyncRepository.recordUpsert(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      );
    });

    final service = OutboundArtistDependencyEnsurer(
      baselineRepository: baselines,
      mutationRunner: runner,
      createArtist: ({required artist}) async {
        return const CloudConditionalWriteResult(
          outcome: CloudConditionalWriteOutcome.applied,
          serverRevision: 1,
        );
      },
    );

    await service.ensure(userId: 'user-1', artist: artist());

    final db = await database.database;
    final pending = await LocalSyncDao(db).findPending('user-1');

    expect(await revision(), 1);
    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.artist);
  });

  test('ownership mismatch prevents cloud access', () async {
    var calls = 0;

    final service = OutboundArtistDependencyEnsurer(
      baselineRepository: baselines,
      mutationRunner: runner,
      createArtist: ({required artist}) async {
        calls++;
        return const CloudConditionalWriteResult(
          outcome: CloudConditionalWriteOutcome.applied,
          serverRevision: 1,
        );
      },
    );

    await expectLater(
      service.ensure(
        userId: 'user-1',
        artist: artist(userId: 'user-2'),
      ),
      throwsStateError,
    );

    expect(calls, 0);
    expect(await revision(), isNull);
  });

  test('transport failure does not establish a baseline', () async {
    final service = OutboundArtistDependencyEnsurer(
      baselineRepository: baselines,
      mutationRunner: runner,
      createArtist: ({required artist}) async {
        throw StateError('Network failure');
      },
    );

    await expectLater(
      service.ensure(userId: 'user-1', artist: artist()),
      throwsStateError,
    );

    expect(await revision(), isNull);
  });
  test('lost dependency response can be reconciled on retry', () async {
    var cloudArtistExists = false;
    var calls = 0;

    final service = OutboundArtistDependencyEnsurer(
      baselineRepository: baselines,
      mutationRunner: runner,
      createArtist: ({required artist}) async {
        calls++;

        if (!cloudArtistExists) {
          cloudArtistExists = true;

          // The server committed, but the response was lost.
          throw StateError('Transport interrupted after cloud commit.');
        }

        // Retrying the insert finds the earlier cloud record.
        return const CloudConditionalWriteResult(
          outcome: CloudConditionalWriteOutcome.conflict,
          serverRevision: 1,
        );
      },
    );

    await expectLater(
      service.ensure(userId: 'user-1', artist: artist()),
      throwsStateError,
    );

    expect(cloudArtistExists, isTrue);
    expect(await revision(), isNull);

    // Required future behavior: safely reconcile our earlier create.
    // The current implementation is expected to fail this assertion.
    await service.ensure(userId: 'user-1', artist: artist());

    expect(calls, 2);
    expect(await revision(), 1);
  });
}
