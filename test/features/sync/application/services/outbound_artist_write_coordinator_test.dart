import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/repositories/cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_write_committer.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_write_coordinator.dart';
import 'package:sonus_next/features/sync/data/gateways/supabase_artist_receipt_write_gateway.dart';
import 'package:sonus_next/features/sync/data/daos/cloud_revision_baseline_dao.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SyncMutationTransactionRunner runner;
  late CloudRevisionBaselineRepository baselines;
  late OutboundArtistWriteCommitter committer;

  final now = DateTime.utc(2026, 10, 17, 16);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    runner = SyncMutationTransactionRunner(
      appDatabase: appDatabase,
      generateId: () => 'artist-mutation-1',
      now: () => now,
    );

    final db = await appDatabase.database;

    baselines = SqliteCloudRevisionBaselineRepository(
      dao: CloudRevisionBaselineDao(db),
    );

    committer = OutboundArtistWriteCommitter(mutationRunner: runner);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  CloudArtistRecord artist({String userId = 'user-1'}) {
    return CloudArtistRecord(
      id: 'artist-1',
      userId: userId,
      name: 'Artist',
      canonicalName: 'artist',
      createdAt: now,
      updatedAt: now,
      metadataFieldStates: const [],
    );
  }

  CloudConditionalWriteResult applied(int revision) {
    return CloudConditionalWriteResult(
      outcome: CloudConditionalWriteOutcome.applied,
      serverRevision: revision,
    );
  }

  CloudConditionalWriteResult conflict(int revision) {
    return CloudConditionalWriteResult(
      outcome: CloudConditionalWriteOutcome.conflict,
      serverRevision: revision,
    );
  }

  const notFound = CloudConditionalWriteResult(
    outcome: CloudConditionalWriteOutcome.notFound,
    serverRevision: null,
  );

  Future<SyncOutboxEntry> enqueue() async {
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

  OutboundArtistWriteCoordinator coordinator({
    required CreateCloudArtist create,
    required UpdateCloudArtist update,
  }) {
    return OutboundArtistWriteCoordinator(
      baselineRepository: baselines,
      createArtist: create,
      updateArtist: update,
      committer: committer,
    );
  }

  test('missing baseline calls creation, then commits revision one', () async {
    final entry = await enqueue();
    var creates = 0;
    var updates = 0;

    final service = coordinator(
      create: ({required artist}) async {
        creates++;
        expect(artist.id, 'artist-1');
        return applied(1);
      },
      update: ({required artist, required expectedServerRevision}) async {
        updates++;
        throw StateError('Update must not run.');
      },
    );

    await service.push(userId: 'user-1', entry: entry, artist: artist());

    expect(creates, 1);
    expect(updates, 0);
    expect(await revision(), 1);
    expect(await pending(), isEmpty);
  });

  test('known baseline performs conditional update', () async {
    await saveRevision(7);
    final entry = await enqueue();
    var updates = 0;

    final service = coordinator(
      create: ({required artist}) async {
        throw StateError('Create must not run.');
      },
      update: ({required artist, required expectedServerRevision}) async {
        updates++;
        expect(expectedServerRevision, 7);
        return applied(8);
      },
    );

    await service.push(userId: 'user-1', entry: entry, artist: artist());

    expect(updates, 1);
    expect(await revision(), 8);
    expect(await pending(), isEmpty);
  });

  test('create conflict preserves pending work and missing baseline', () async {
    final entry = await enqueue();

    final service = coordinator(
      create: ({required artist}) async => conflict(12),
      update: ({required artist, required expectedServerRevision}) async {
        throw StateError('Unexpected update.');
      },
    );

    await expectLater(
      service.push(userId: 'user-1', entry: entry, artist: artist()),
      throwsA(
        isA<OutboundArtistWriteConflict>()
            .having((e) => e.expectedServerRevision, 'expected', isNull)
            .having((e) => e.observedServerRevision, 'observed', 12),
      ),
    );

    expect(await revision(), isNull);
    expect(await pending(), hasLength(1));
  });

  test('update conflict preserves the original baseline', () async {
    await saveRevision(7);
    final entry = await enqueue();

    final service = coordinator(
      create: ({required artist}) async {
        throw StateError('Unexpected create.');
      },
      update: ({required artist, required expectedServerRevision}) async {
        return conflict(11);
      },
    );

    await expectLater(
      service.push(userId: 'user-1', entry: entry, artist: artist()),
      throwsA(isA<OutboundArtistWriteConflict>()),
    );

    expect(await revision(), 7);
    expect(await pending(), hasLength(1));
  });

  test('not found does not acknowledge or invent a baseline', () async {
    final entry = await enqueue();

    final service = coordinator(
      create: ({required artist}) async => notFound,
      update: ({required artist, required expectedServerRevision}) async {
        throw StateError('Unexpected update.');
      },
    );

    await expectLater(
      service.push(userId: 'user-1', entry: entry, artist: artist()),
      throwsA(isA<OutboundArtistWriteConflict>()),
    );

    expect(await revision(), isNull);
    expect(await pending(), hasLength(1));
  });

  test('transport failure preserves pending and baseline', () async {
    await saveRevision(3);
    final entry = await enqueue();

    final service = coordinator(
      create: ({required artist}) async {
        throw StateError('Unexpected create.');
      },
      update: ({required artist, required expectedServerRevision}) async {
        throw StateError('Network unavailable');
      },
    );

    await expectLater(
      service.push(userId: 'user-1', entry: entry, artist: artist()),
      throwsStateError,
    );

    expect(await revision(), 3);
    expect(await pending(), hasLength(1));
  });

  test('new local mutation during upload remains pending', () async {
    await saveRevision(4);
    final entry = await enqueue();

    final started = Completer<void>();
    final release = Completer<void>();

    final service = coordinator(
      create: ({required artist}) async {
        throw StateError('Unexpected create.');
      },
      update: ({required artist, required expectedServerRevision}) async {
        started.complete();
        await release.future;
        return applied(5);
      },
    );

    final uploading = service.push(
      userId: 'user-1',
      entry: entry,
      artist: artist(),
    );

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

    expect(await revision(), 5);
    final remaining = await pending();
    expect(remaining, hasLength(1));
    expect(remaining.single.mutationRevision, 2);
  });

  test('rejects mismatched ownership before cloud access', () async {
    final entry = await enqueue();
    var calls = 0;

    final service = coordinator(
      create: ({required artist}) async {
        calls++;
        return applied(1);
      },
      update: ({required artist, required expectedServerRevision}) async {
        calls++;
        return applied(expectedServerRevision + 1);
      },
    );

    await expectLater(
      service.push(
        userId: 'user-1',
        entry: entry,
        artist: artist(userId: 'user-2'),
      ),
      throwsStateError,
    );

    expect(calls, 0);
    expect(await pending(), hasLength(1));
  });

  test('rejects invalid applied revision without acknowledging', () async {
    final entry = await enqueue();

    final service = coordinator(
      create: ({required artist}) async => applied(2),
      update: ({required artist, required expectedServerRevision}) async {
        throw StateError('Unexpected update.');
      },
    );

    await expectLater(
      service.push(userId: 'user-1', entry: entry, artist: artist()),
      throwsStateError,
    );

    expect(await revision(), isNull);
    expect(await pending(), hasLength(1));
  });

  test('creation replay commits verified server revision', () async {
    final entry = await enqueue();

    final service = coordinator(
      create: ({required artist}) async {
        return const CloudConditionalWriteResult(
          outcome: CloudConditionalWriteOutcome.replayed,
          serverRevision: 1,
        );
      },
      update: ({required artist, required expectedServerRevision}) async {
        throw StateError('Update must not run.');
      },
    );

    await service.push(userId: 'user-1', entry: entry, artist: artist());

    expect(await revision(), 1);
    expect(await pending(), isEmpty);
  });

  test('update replay preserves newer local mutation', () async {
    await saveRevision(4);
    final entry = await enqueue();

    final started = Completer<void>();
    final release = Completer<void>();

    final service = coordinator(
      create: ({required artist}) async {
        throw StateError('Create must not run.');
      },
      update: ({required artist, required expectedServerRevision}) async {
        expect(expectedServerRevision, 4);
        started.complete();
        await release.future;

        return const CloudConditionalWriteResult(
          outcome: CloudConditionalWriteOutcome.replayed,
          serverRevision: 5,
        );
      },
    );

    final uploading = service.push(
      userId: 'user-1',
      entry: entry,
      artist: artist(),
    );

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

    expect(await revision(), 5);

    final remaining = await pending();

    expect(remaining, hasLength(1));
    expect(remaining.single.id, entry.id);
    expect(remaining.single.mutationRevision, 2);
    expect(remaining.single.operation, SyncOutboxOperation.upsert);
  });

  test('receipt route forwards exact creation identity', () async {
    final entry = await enqueue();

    final service = OutboundArtistWriteCoordinator(
      baselineRepository: baselines,
      committer: committer,
      createArtist: ({required artist}) async {
        throw StateError('Legacy creation must not run.');
      },
      updateArtist: ({required artist, required expectedServerRevision}) async {
        throw StateError('Legacy update must not run.');
      },
      createArtistWithReceipt:
          ({
            required artist,
            required outboxId,
            required mutationRevision,
          }) async {
            expect(outboxId, entry.id);
            expect(mutationRevision, entry.mutationRevision);
            expect(artist.id, entry.entityId);

            return const CloudConditionalWriteResult(
              outcome: CloudConditionalWriteOutcome.replayed,
              serverRevision: 1,
            );
          },
      updateArtistWithReceipt:
          ({
            required artist,
            required expectedServerRevision,
            required outboxId,
            required mutationRevision,
          }) async {
            throw StateError('Update must not run.');
          },
    );

    await service.push(userId: 'user-1', entry: entry, artist: artist());

    expect(await revision(), 1);
    expect(await pending(), isEmpty);
  });

  test('receipt route forwards exact update identity', () async {
    await saveRevision(7);
    final entry = await enqueue();

    final service = OutboundArtistWriteCoordinator(
      baselineRepository: baselines,
      committer: committer,
      createArtist: ({required artist}) async {
        throw StateError('Legacy creation must not run.');
      },
      updateArtist: ({required artist, required expectedServerRevision}) async {
        throw StateError('Legacy update must not run.');
      },
      createArtistWithReceipt:
          ({
            required artist,
            required outboxId,
            required mutationRevision,
          }) async {
            throw StateError('Creation must not run.');
          },
      updateArtistWithReceipt:
          ({
            required artist,
            required expectedServerRevision,
            required outboxId,
            required mutationRevision,
          }) async {
            expect(expectedServerRevision, 7);
            expect(outboxId, entry.id);
            expect(mutationRevision, entry.mutationRevision);
            expect(artist.id, entry.entityId);

            return const CloudConditionalWriteResult(
              outcome: CloudConditionalWriteOutcome.replayed,
              serverRevision: 8,
            );
          },
    );

    await service.push(userId: 'user-1', entry: entry, artist: artist());

    expect(await revision(), 8);
    expect(await pending(), isEmpty);
  });

  test('partial receipt configuration fails before cloud access', () async {
    final entry = await enqueue();
    var calls = 0;

    final service = OutboundArtistWriteCoordinator(
      baselineRepository: baselines,
      committer: committer,
      createArtist: ({required artist}) async {
        calls++;
        return applied(1);
      },
      updateArtist: ({required artist, required expectedServerRevision}) async {
        calls++;
        return applied(expectedServerRevision + 1);
      },
      createArtistWithReceipt:
          ({
            required artist,
            required outboxId,
            required mutationRevision,
          }) async {
            calls++;
            return applied(1);
          },
    );

    await expectLater(
      service.push(userId: 'user-1', entry: entry, artist: artist()),
      throwsStateError,
    );

    expect(calls, 0);
    expect(await revision(), isNull);
    expect(await pending(), hasLength(1));
  });

  test('lost creation response recovers through receipt gateway', () async {
    final entry = await enqueue();

    var calls = 0;
    String? firstOutboxId;
    int? firstMutationRevision;

    final gateway = SupabaseArtistReceiptWriteGateway.forTesting((
      functionName,
      parameters,
    ) async {
      expect(functionName, SupabaseArtistReceiptWriteGateway.createRpcName);

      calls++;

      expect(parameters['p_artist_id'], entry.entityId);
      expect(parameters['p_outbox_id'], entry.id);
      expect(parameters['p_mutation_revision'], entry.mutationRevision);

      if (calls == 1) {
        firstOutboxId = parameters['p_outbox_id'] as String;
        firstMutationRevision = parameters['p_mutation_revision'] as int;

        // Simulate the server committing its insertion, followed
        // by a lost HTTP response.
        throw StateError('Simulated response lost after cloud commit');
      }

      expect(parameters['p_outbox_id'], firstOutboxId);
      expect(parameters['p_mutation_revision'], firstMutationRevision);

      return [
        {'outcome': 'replayed', 'server_revision': 1},
      ];
    });

    final service = OutboundArtistWriteCoordinator(
      baselineRepository: baselines,
      committer: committer,
      createArtist: ({required artist}) async {
        throw StateError('Legacy creation must not run.');
      },
      updateArtist: ({required artist, required expectedServerRevision}) async {
        throw StateError('Legacy update must not run.');
      },
      createArtistWithReceipt: gateway.createArtist,
      updateArtistWithReceipt: gateway.updateArtist,
    );

    await expectLater(
      service.push(userId: 'user-1', entry: entry, artist: artist()),
      throwsStateError,
    );

    expect(calls, 1);
    expect(await revision(), isNull);

    final afterFailure = await pending();
    expect(afterFailure, hasLength(1));
    expect(afterFailure.single.id, entry.id);
    expect(afterFailure.single.mutationRevision, entry.mutationRevision);

    // The exact pending mutation is retried.
    await service.push(
      userId: 'user-1',
      entry: afterFailure.single,
      artist: artist(),
    );

    expect(calls, 2);
    expect(await revision(), 1);
    expect(await pending(), isEmpty);
  });

  test('lost update response recovers through receipt gateway', () async {
    await saveRevision(7);
    final entry = await enqueue();

    var calls = 0;
    String? firstOutboxId;
    int? firstMutationRevision;
    int? firstExpectedRevision;

    final gateway = SupabaseArtistReceiptWriteGateway.forTesting((
      functionName,
      parameters,
    ) async {
      expect(functionName, SupabaseArtistReceiptWriteGateway.updateRpcName);

      calls++;

      expect(parameters['p_artist_id'], entry.entityId);
      expect(parameters['p_outbox_id'], entry.id);
      expect(parameters['p_mutation_revision'], entry.mutationRevision);
      expect(parameters['p_expected_revision'], 7);

      if (calls == 1) {
        firstOutboxId = parameters['p_outbox_id'] as String;
        firstMutationRevision = parameters['p_mutation_revision'] as int;
        firstExpectedRevision = parameters['p_expected_revision'] as int;

        // Simulates a successful remote update whose response
        // never reaches the app.
        throw StateError('Simulated update response lost');
      }

      expect(parameters['p_outbox_id'], firstOutboxId);
      expect(parameters['p_mutation_revision'], firstMutationRevision);
      expect(parameters['p_expected_revision'], firstExpectedRevision);

      return [
        {'outcome': 'replayed', 'server_revision': 8},
      ];
    });

    final service = OutboundArtistWriteCoordinator(
      baselineRepository: baselines,
      committer: committer,
      createArtist: ({required artist}) async {
        throw StateError('Legacy creation must not run.');
      },
      updateArtist: ({required artist, required expectedServerRevision}) async {
        throw StateError('Legacy update must not run.');
      },
      createArtistWithReceipt: gateway.createArtist,
      updateArtistWithReceipt: gateway.updateArtist,
    );

    await expectLater(
      service.push(userId: 'user-1', entry: entry, artist: artist()),
      throwsStateError,
    );

    expect(calls, 1);
    expect(await revision(), 7);

    final afterFailure = await pending();

    expect(afterFailure, hasLength(1));
    expect(afterFailure.single.id, entry.id);
    expect(afterFailure.single.mutationRevision, entry.mutationRevision);

    await service.push(
      userId: 'user-1',
      entry: afterFailure.single,
      artist: artist(),
    );

    expect(calls, 2);
    expect(await revision(), 8);
    expect(await pending(), isEmpty);
  });
}
