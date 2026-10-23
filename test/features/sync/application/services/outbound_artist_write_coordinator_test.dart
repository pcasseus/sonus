import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/repositories/cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/application/services/cloud_artist_create_verifier.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
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

Future<CloudSyncItem?> unexpectedFetch({
  required String userId,
  required String artistId,
}) {
  throw StateError('Cloud artist fetch was not expected.');
}

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

  CloudArtistRecord artist({
    String userId = 'user-1',
    String name = 'Artist',
    DateTime? deletedAt,
    List<CloudMetadataFieldState>? metadataFieldStates = const [],
  }) {
    return CloudArtistRecord(
      id: 'artist-1',
      userId: userId,
      name: name,
      canonicalName: 'artist',
      createdAt: now,
      updatedAt: now,
      deletedAt: deletedAt,
      metadataFieldStates: metadataFieldStates,
    );
  }

  CloudSyncItem cloudRow(CloudArtistRecord record, int? revision) {
    return CloudSyncItem(
      record: record,
      serverUpdatedAt: now,
      serverRevision: revision,
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
    FetchCurrentCloudArtist fetch = unexpectedFetch,
  }) {
    return OutboundArtistWriteCoordinator(
      baselineRepository: baselines,
      createArtist: create,
      updateArtist: update,
      committer: committer,
      fetchCurrentArtist: fetch,
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
      fetch: ({required userId, required artistId}) async =>
          cloudRow(artist(name: 'Someone Else'), 12),
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
      fetchCurrentArtist: unexpectedFetch,
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
      fetchCurrentArtist: unexpectedFetch,
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
      fetchCurrentArtist: unexpectedFetch,
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
      fetchCurrentArtist: unexpectedFetch,
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
      fetchCurrentArtist: unexpectedFetch,
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

  group('legacy lost creation response', () {
    UpdateCloudArtist noUpdate() {
      return ({required artist, required expectedServerRevision}) async {
        throw StateError('Update must not run.');
      };
    }

    test('is adopted on retry once the fetched artist is verified', () async {
      final entry = await enqueue();
      CloudSyncItem? committedRow;
      var creates = 0;
      var fetches = 0;

      final service = coordinator(
        create: ({required artist}) async {
          creates++;

          if (committedRow == null) {
            // The server committed, but the response was lost.
            committedRow = cloudRow(artist, 1);
            throw StateError('Transport interrupted after cloud commit.');
          }

          return conflict(1);
        },
        update: noUpdate(),
        fetch: ({required userId, required artistId}) async {
          fetches++;
          expect(userId, 'user-1');
          expect(artistId, 'artist-1');
          return committedRow;
        },
      );

      await expectLater(
        service.push(userId: 'user-1', entry: entry, artist: artist()),
        throwsStateError,
      );

      expect(fetches, 0);
      expect(await revision(), isNull);
      expect(await pending(), hasLength(1));

      final retry = (await pending()).single;
      await service.push(userId: 'user-1', entry: retry, artist: artist());

      expect(creates, 2);
      expect(fetches, 1);
      expect(await revision(), 1);
      expect(await pending(), isEmpty);
    });

    test('identical artist at a later revision is adopted there', () async {
      final entry = await enqueue();

      final service = coordinator(
        create: ({required artist}) async => conflict(4),
        update: noUpdate(),
        fetch: ({required userId, required artistId}) async =>
            cloudRow(artist(), 4),
      );

      await service.push(userId: 'user-1', entry: entry, artist: artist());

      expect(await revision(), 4);
      expect(await pending(), isEmpty);
    });

    test('local edit during verification stays pending', () async {
      final entry = await enqueue();

      final service = coordinator(
        create: ({required artist}) async => conflict(1),
        update: noUpdate(),
        fetch: ({required userId, required artistId}) async {
          await runner.run<void>((context) async {
            await context.localSyncRepository.recordUpsert(
              userId: 'user-1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist-1',
            );
          });

          return cloudRow(artist(), 1);
        },
      );

      await service.push(userId: 'user-1', entry: entry, artist: artist());

      // The verified revision is kept so the newer edit uploads as an
      // update conditioned on it.
      expect(await revision(), 1);
      final remaining = await pending();
      expect(remaining, hasLength(1));
      expect(remaining.single.mutationRevision, 2);
    });

    test('concurrent cloud edit is a conflict, never adopted', () async {
      final entry = await enqueue();

      final service = coordinator(
        create: ({required artist}) async => conflict(2),
        update: noUpdate(),
        fetch: ({required userId, required artistId}) async =>
            cloudRow(artist(name: 'Renamed Elsewhere'), 2),
      );

      await expectLater(
        service.push(userId: 'user-1', entry: entry, artist: artist()),
        throwsA(
          isA<OutboundArtistWriteConflict>()
              .having((e) => e.expectedServerRevision, 'expected', isNull)
              .having((e) => e.observedServerRevision, 'observed', 2),
        ),
      );

      expect(await revision(), isNull);
      expect(await pending(), hasLength(1));
    });

    final rejected = <String, CloudSyncItem? Function()>{
      'a missing cloud row': () => null,
      'a tombstoned cloud row': () => cloudRow(artist(deletedAt: now), 2),
      'a row owned by another account': () =>
          cloudRow(artist(userId: 'user-2'), 1),
      'a row whose provenance was never synced': () =>
          cloudRow(artist(metadataFieldStates: null), 1),
      'no server revision': () => cloudRow(artist(), null),
    };

    for (final scenario in rejected.entries) {
      test('${scenario.key} is never adopted', () async {
        final entry = await enqueue();

        final service = coordinator(
          create: ({required artist}) async => conflict(1),
          update: noUpdate(),
          fetch: ({required userId, required artistId}) async =>
              scenario.value(),
        );

        await expectLater(
          service.push(userId: 'user-1', entry: entry, artist: artist()),
          throwsA(isA<OutboundArtistWriteConflict>()),
        );

        expect(await revision(), isNull);
        expect(await pending(), hasLength(1));
      });
    }

    test('a failed verification fetch keeps the mutation pending', () async {
      final entry = await enqueue();

      final service = coordinator(
        create: ({required artist}) async => conflict(1),
        update: noUpdate(),
        fetch: ({required userId, required artistId}) async {
          throw StateError('Network failure during verification.');
        },
      );

      await expectLater(
        service.push(userId: 'user-1', entry: entry, artist: artist()),
        throwsStateError,
      );

      expect(await revision(), isNull);
      expect(await pending(), hasLength(1));
    });

    test('receipt route conflicts are never verified by fetch', () async {
      final entry = await enqueue();

      final service = OutboundArtistWriteCoordinator(
        baselineRepository: baselines,
        committer: committer,
        fetchCurrentArtist: unexpectedFetch,
        createArtist: ({required artist}) async {
          throw StateError('Legacy creation must not run.');
        },
        updateArtist: noUpdate(),
        createArtistWithReceipt:
            ({
              required artist,
              required outboxId,
              required mutationRevision,
            }) async => conflict(1),
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

      await expectLater(
        service.push(userId: 'user-1', entry: entry, artist: artist()),
        throwsA(isA<OutboundArtistWriteConflict>()),
      );

      expect(await revision(), isNull);
      expect(await pending(), hasLength(1));
    });
  });
}
