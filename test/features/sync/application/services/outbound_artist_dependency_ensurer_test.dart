import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/services/cloud_artist_create_verifier.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/cloud_sync_reader.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_dependency_ensurer.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_write_coordinator.dart';
import 'package:sonus_next/features/sync/data/daos/cloud_revision_baseline_dao.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

Future<CloudSyncItem?> unexpectedFetch({
  required String userId,
  required String artistId,
}) {
  throw StateError('Cloud artist fetch was not expected.');
}

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

  CloudArtistRecord artist({
    String id = 'artist-1',
    String userId = 'user-1',
    String name = 'Dependency Artist',
    String canonicalName = 'dependency artist',
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? headerArtworkId,
    List<CloudMetadataFieldState>? metadataFieldStates,
  }) {
    return CloudArtistRecord(
      id: id,
      userId: userId,
      name: name,
      canonicalName: canonicalName,
      createdAt: now,
      updatedAt: updatedAt ?? now,
      deletedAt: deletedAt,
      headerArtworkId: headerArtworkId,
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

  CloudConditionalWriteResult conflict(int? revision) {
    return CloudConditionalWriteResult(
      outcome: CloudConditionalWriteOutcome.conflict,
      serverRevision: revision,
    );
  }

  Future<int?> revision() {
    return baselines.getRevision(
      userId: 'user-1',
      entityType: CloudDataEntity.artist,
      entityId: 'artist-1',
    );
  }

  OutboundArtistDependencyEnsurer ensurer({
    required CreateCloudArtist create,
    FetchCurrentCloudArtist fetch = unexpectedFetch,
  }) {
    return OutboundArtistDependencyEnsurer(
      baselineRepository: baselines,
      mutationRunner: runner,
      createArtist: create,
      fetchCurrentArtist: fetch,
    );
  }

  test('creates absent dependency and records its baseline', () async {
    var calls = 0;

    final service = ensurer(
      create: ({required artist}) async {
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

    final service = ensurer(
      create: ({required artist}) async {
        calls++;
        throw StateError('Creation was not expected.');
      },
    );

    await service.ensure(userId: 'user-1', artist: artist());

    expect(calls, 0);
    expect(await revision(), 5);
  });

  test('cloud conflict with no cloud row preserves missing baseline', () async {
    final service = ensurer(
      create: ({required artist}) async => conflict(9),
      fetch: ({required userId, required artistId}) async => null,
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

    final service = ensurer(
      create: ({required artist}) async {
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

    final service = ensurer(
      create: ({required artist}) async {
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
    final service = ensurer(
      create: ({required artist}) async {
        throw StateError('Network failure');
      },
    );

    await expectLater(
      service.ensure(userId: 'user-1', artist: artist()),
      throwsStateError,
    );

    expect(await revision(), isNull);
  });

  group('lost-response recovery', () {
    test(
      'lost dependency response is adopted on retry once verified',
      () async {
        CloudSyncItem? committedRow;
        var calls = 0;
        var fetches = 0;

        final service = ensurer(
          create: ({required artist}) async {
            calls++;

            if (committedRow == null) {
              // The server committed, but the response was lost.
              committedRow = cloudRow(artist, 1);
              throw StateError('Transport interrupted after cloud commit.');
            }

            // Retrying the insert finds the earlier cloud record.
            return conflict(1);
          },
          fetch: ({required userId, required artistId}) async {
            fetches++;
            expect(userId, 'user-1');
            expect(artistId, 'artist-1');
            return committedRow;
          },
        );

        await expectLater(
          service.ensure(userId: 'user-1', artist: artist()),
          throwsStateError,
        );

        expect(committedRow, isNotNull);
        expect(await revision(), isNull);
        expect(fetches, 0);

        // The conflict alone is not trusted; the fetched row is verified.
        await service.ensure(userId: 'user-1', artist: artist());

        expect(calls, 2);
        expect(fetches, 1);
        expect(await revision(), 1);
      },
    );

    test('identical artist at a later revision is adopted there', () async {
      final service = ensurer(
        create: ({required artist}) async => conflict(3),
        fetch: ({required userId, required artistId}) async =>
            cloudRow(artist(), 3),
      );

      await service.ensure(userId: 'user-1', artist: artist());

      expect(await revision(), 3);
    });

    test('adoption never acknowledges a pending local artist edit', () async {
      await runner.run<void>((context) async {
        await context.localSyncRepository.recordUpsert(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        );
      });

      final service = ensurer(
        create: ({required artist}) async => conflict(1),
        fetch: ({required userId, required artistId}) async =>
            cloudRow(artist(), 1),
      );

      await service.ensure(userId: 'user-1', artist: artist());

      final db = await database.database;

      expect(await revision(), 1);
      expect(await LocalSyncDao(db).findPending('user-1'), hasLength(1));
    });

    test('a concurrently recorded higher baseline is never lowered', () async {
      final service = ensurer(
        create: ({required artist}) async => conflict(1),
        fetch: ({required userId, required artistId}) async {
          // Another sync path reconciles a newer revision meanwhile.
          await baselines.saveObservedRevision(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist-1',
            serverRevision: 5,
          );

          return cloudRow(artist(), 1);
        },
      );

      await service.ensure(userId: 'user-1', artist: artist());

      expect(await revision(), 5);
    });

    final rejected = <String, CloudSyncItem? Function()>{
      'a missing cloud row': () => null,
      'a tombstoned cloud row': () => cloudRow(artist(deletedAt: now), 2),
      'a row owned by another account': () =>
          cloudRow(artist(userId: 'user-2'), 1),
      'a row with another id': () => cloudRow(artist(id: 'artist-2'), 1),
      'a concurrent cloud rename': () =>
          cloudRow(artist(name: 'Renamed Elsewhere'), 2),
      'a different canonical name': () =>
          cloudRow(artist(canonicalName: 'other'), 1),
      'an update time one microsecond apart': () => cloudRow(
        artist(updatedAt: now.add(const Duration(microseconds: 1))),
        1,
      ),
      'different header artwork': () =>
          cloudRow(artist(headerArtworkId: 'artwork-9'), 1),
      'different metadata provenance': () => cloudRow(
        artist(
          metadataFieldStates: [
            CloudMetadataFieldState(
              fieldName: 'name',
              authority: 'manual',
              source: 'user',
              updatedAt: now,
            ),
          ],
        ),
        1,
      ),
      'no server revision': () => cloudRow(artist(), null),
      'an invalid server revision': () => cloudRow(artist(), 0),
    };

    for (final scenario in rejected.entries) {
      test('${scenario.key} is never adopted', () async {
        var fetches = 0;

        final service = ensurer(
          create: ({required artist}) async => conflict(1),
          fetch: ({required userId, required artistId}) async {
            fetches++;
            return scenario.value();
          },
        );

        await expectLater(
          service.ensure(userId: 'user-1', artist: artist()),
          throwsA(
            isA<OutboundArtistWriteConflict>()
                .having((e) => e.expectedServerRevision, 'expected', isNull)
                .having(
                  (e) => e.outcome,
                  'outcome',
                  CloudConditionalWriteOutcome.conflict,
                ),
          ),
        );

        expect(fetches, 1);
        expect(await revision(), isNull);
      });
    }

    test('not found is rejected without trusting a fetch', () async {
      final service = ensurer(
        create: ({required artist}) async => const CloudConditionalWriteResult(
          outcome: CloudConditionalWriteOutcome.notFound,
          serverRevision: null,
        ),
      );

      await expectLater(
        service.ensure(userId: 'user-1', artist: artist()),
        throwsA(isA<OutboundArtistWriteConflict>()),
      );

      expect(await revision(), isNull);
    });

    test('a failed verification fetch establishes no baseline', () async {
      final service = ensurer(
        create: ({required artist}) async => conflict(1),
        fetch: ({required userId, required artistId}) async {
          throw StateError('Network failure during verification.');
        },
      );

      await expectLater(
        service.ensure(userId: 'user-1', artist: artist()),
        throwsStateError,
      );

      expect(await revision(), isNull);
    });
  });
}
