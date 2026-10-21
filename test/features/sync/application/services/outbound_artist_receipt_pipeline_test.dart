import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/services/artist_write_recovery_service.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_receipt_pipeline.dart';
import 'package:sonus_next/features/sync/data/gateways/artist_journal_replay_gateway.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  final now = DateTime.utc(2026, 10, 18, 12);

  CloudArtistRecord artist(String id) => CloudArtistRecord(
    id: id,
    userId: 'user_1',
    name: 'Artist $id',
    canonicalName: 'artist $id',
    createdAt: now.subtract(const Duration(days: 1)),
    updatedAt: now,
  );

  SyncMutationTransactionRunner runner(AppDatabase database) {
    var nextId = 0;

    return SyncMutationTransactionRunner(
      appDatabase: database,
      generateId: () => 'outbox_${++nextId}',
      now: () => now,
    );
  }

  Future<SyncOutboxEntry> enqueue(
    SyncMutationTransactionRunner mutations,
    String artistId, {
    SyncOutboxOperation operation = SyncOutboxOperation.upsert,
  }) async {
    await mutations.run<void>((context) async {
      if (operation == SyncOutboxOperation.upsert) {
        await context.localSyncRepository.recordUpsert(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: artistId,
        );
      } else {
        await context.localSyncRepository.recordDelete(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: artistId,
        );
      }
    });

    return mutations.run<SyncOutboxEntry>((context) async {
      final pending = await context.localSyncRepository.getPending('user_1');

      return pending.singleWhere((entry) => entry.entityId == artistId);
    });
  }

  test('pending artist upsert blocks dependency creation', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    var dependencyCalls = 0;
    var receiptCalls = 0;

    final recovery = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (_, _) async {
          receiptCalls++;
          return [
            {'outcome': 'applied', 'server_revision': 1},
          ];
        },
      ),
    );

    final pipeline = OutboundArtistReceiptPipeline(
      recovery: recovery,
      mutationRunner: mutations,
      ensureDependency: ({required userId, required artist}) async {
        dependencyCalls++;
      },
    );

    try {
      await enqueue(mutations, 'artist_1');

      await expectLater(
        pipeline.guardedDependency(
          userId: 'user_1',
          artist: artist('artist_1'),
        ),
        throwsStateError,
      );

      expect(dependencyCalls, 0);
      expect(receiptCalls, 0);

      await mutations.run<void>((context) async {
        expect(
          await context.localSyncRepository.getPending('user_1'),
          hasLength(1),
        );
      });
    } finally {
      await database.close();
    }
  });

  test('prepared unresolved receipt blocks dependency creation', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    var dependencyCalls = 0;
    var receiptCalls = 0;

    final recovery = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (_, _) async {
          receiptCalls++;
          return [
            {'outcome': 'replayed', 'server_revision': 1},
          ];
        },
      ),
    );

    final pipeline = OutboundArtistReceiptPipeline(
      recovery: recovery,
      mutationRunner: mutations,
      ensureDependency: ({required userId, required artist}) async {
        dependencyCalls++;
      },
    );

    try {
      final entry = await enqueue(mutations, 'artist_1');

      await recovery.prepareUpsert(
        userId: 'user_1',
        entry: entry,
        artist: artist('artist_1'),
      );

      await expectLater(
        pipeline.guardedDependency(
          userId: 'user_1',
          artist: artist('artist_1'),
        ),
        throwsStateError,
      );

      expect(dependencyCalls, 0);
      expect(receiptCalls, 0);

      await mutations.run<void>((context) async {
        expect(
          await context.artistWriteJournalRepository!.findUnresolvedForUser(
            'user_1',
          ),
          hasLength(1),
        );
      });
    } finally {
      await database.close();
    }
  });

  test('recovery clears old receipt before dependency proceeds', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    final events = <String>[];

    final recovery = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (function, parameters) async {
          events.add('receipt');

          expect(function, 'create_artist_with_receipt');
          expect(parameters['p_artist_id'], 'artist_1');

          return [
            {'outcome': 'replayed', 'server_revision': 1},
          ];
        },
      ),
    );

    final pipeline = OutboundArtistReceiptPipeline(
      recovery: recovery,
      mutationRunner: mutations,
      ensureDependency: ({required userId, required artist}) async {
        events.add('dependency');
      },
    );

    try {
      final entry = await enqueue(mutations, 'artist_1');

      await recovery.prepareUpsert(
        userId: 'user_1',
        entry: entry,
        artist: artist('artist_1'),
      );

      await pipeline.recover('user_1');

      await pipeline.guardedDependency(
        userId: 'user_1',
        artist: artist('artist_1'),
      );

      expect(events, ['receipt', 'dependency']);

      await mutations.run<void>((context) async {
        expect(await context.localSyncRepository.getPending('user_1'), isEmpty);

        expect(
          await context.artistWriteJournalRepository!.findUnresolvedForUser(
            'user_1',
          ),
          isEmpty,
        );

        expect(
          await context.cloudRevisionBaselineRepository!.getRevision(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
          ),
          1,
        );
      });
    } finally {
      await database.close();
    }
  });

  test('unrelated pending artist does not block dependency', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    final ensured = <String>[];

    final recovery = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (_, _) async {
          throw StateError('No receipt RPC expected.');
        },
      ),
    );

    final pipeline = OutboundArtistReceiptPipeline(
      recovery: recovery,
      mutationRunner: mutations,
      ensureDependency: ({required userId, required artist}) async {
        ensured.add(artist.id);
      },
    );

    try {
      await enqueue(mutations, 'artist_1');

      await pipeline.guardedDependency(
        userId: 'user_1',
        artist: artist('artist_2'),
      );

      expect(ensured, ['artist_2']);

      await mutations.run<void>((context) async {
        final pending = await context.localSyncRepository.getPending('user_1');

        expect(pending, hasLength(1));
        expect(pending.single.entityId, 'artist_1');
      });
    } finally {
      await database.close();
    }
  });

  test('explicit pipeline upsert reconciles journal and outbox', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    var rpcCalls = 0;

    final recovery = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (function, parameters) async {
          rpcCalls++;

          expect(function, 'create_artist_with_receipt');
          expect(parameters['p_artist_id'], 'artist_1');

          await mutations.run<void>((context) async {
            expect(
              await context.artistWriteJournalRepository!.findUnresolvedForUser(
                'user_1',
              ),
              hasLength(1),
            );
          });

          return [
            {'outcome': 'applied', 'server_revision': 1},
          ];
        },
      ),
    );

    final pipeline = OutboundArtistReceiptPipeline(
      recovery: recovery,
      mutationRunner: mutations,
      ensureDependency: ({required userId, required artist}) async {
        throw StateError('Unexpected dependency call.');
      },
    );

    try {
      final entry = await enqueue(mutations, 'artist_1');

      await pipeline.pushUpsert(
        userId: 'user_1',
        entry: entry,
        artist: artist('artist_1'),
      );

      expect(rpcCalls, 1);

      await mutations.run<void>((context) async {
        expect(await context.localSyncRepository.getPending('user_1'), isEmpty);

        expect(
          await context.artistWriteJournalRepository!.findUnresolvedForUser(
            'user_1',
          ),
          isEmpty,
        );

        expect(
          await context.cloudRevisionBaselineRepository!.getRevision(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
          ),
          1,
        );
      });
    } finally {
      await database.close();
    }
  });

  test('explicit pipeline deletion preserves guarded receipt path', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    var rpcCalls = 0;

    final recovery = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (function, parameters) async {
          rpcCalls++;

          expect(function, 'delete_artist_with_receipt');
          expect(parameters['p_expected_revision'], 4);

          return [
            {'outcome': 'applied', 'server_revision': 5},
          ];
        },
      ),
    );

    final pipeline = OutboundArtistReceiptPipeline(
      recovery: recovery,
      mutationRunner: mutations,
      ensureDependency: ({required userId, required artist}) async {
        throw StateError('Unexpected dependency call.');
      },
    );

    try {
      await mutations.run<void>((context) async {
        await context.cloudRevisionBaselineRepository!.saveObservedRevision(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
          serverRevision: 4,
        );
      });

      final entry = await enqueue(
        mutations,
        'artist_1',
        operation: SyncOutboxOperation.delete,
      );

      await pipeline.pushDelete(userId: 'user_1', entry: entry);

      expect(rpcCalls, 1);

      await mutations.run<void>((context) async {
        expect(await context.localSyncRepository.getPending('user_1'), isEmpty);

        expect(
          await context.artistWriteJournalRepository!.findUnresolvedForUser(
            'user_1',
          ),
          isEmpty,
        );

        expect(
          await context.cloudRevisionBaselineRepository!.getRevision(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
          ),
          5,
        );
      });
    } finally {
      await database.close();
    }
  });

  test('new artist edit during dependency request blocks completion', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);

    final requestStarted = Completer<void>();
    final releaseRequest = Completer<void>();
    var dependencyCalls = 0;
    var receiptCalls = 0;

    final recovery = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (_, _) async {
          receiptCalls++;
          throw StateError('Unexpected receipt submission.');
        },
      ),
    );

    final pipeline = OutboundArtistReceiptPipeline(
      recovery: recovery,
      mutationRunner: mutations,
      ensureDependency: ({required userId, required artist}) async {
        dependencyCalls++;
        requestStarted.complete();
        await releaseRequest.future;
      },
    );

    try {
      final request = pipeline.guardedDependency(
        userId: 'user_1',
        artist: artist('artist_1'),
      );

      await requestStarted.future;

      try {
        await enqueue(mutations, 'artist_1');

        await mutations.run<void>((context) async {
          final pending = await context.localSyncRepository.getPending(
            'user_1',
          );

          expect(pending, hasLength(1));
          expect(pending.single.entityId, 'artist_1');
        });
      } finally {
        releaseRequest.complete();
      }

      await expectLater(request, throwsStateError);

      expect(dependencyCalls, 1);
      expect(receiptCalls, 0);

      await mutations.run<void>((context) async {
        final pending = await context.localSyncRepository.getPending('user_1');

        expect(pending, hasLength(1));
        expect(pending.single.operation, SyncOutboxOperation.upsert);
        expect(pending.single.mutationRevision, 1);
      });
    } finally {
      if (!releaseRequest.isCompleted) {
        releaseRequest.complete();
      }
      await database.close();
    }
  });

  test('dependency without concurrent edits passes both checks', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    var dependencyCalls = 0;

    final recovery = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (_, _) async {
          throw StateError('Unexpected receipt submission.');
        },
      ),
    );

    final pipeline = OutboundArtistReceiptPipeline(
      recovery: recovery,
      mutationRunner: mutations,
      ensureDependency: ({required userId, required artist}) async {
        dependencyCalls++;
      },
    );

    try {
      await pipeline.guardedDependency(
        userId: 'user_1',
        artist: artist('artist_1'),
      );

      expect(dependencyCalls, 1);

      await mutations.run<void>((context) async {
        expect(await context.localSyncRepository.getPending('user_1'), isEmpty);
        expect(
          await context.artistWriteJournalRepository!.findUnresolvedForUser(
            'user_1',
          ),
          isEmpty,
        );
      });
    } finally {
      await database.close();
    }
  });

  test(
    'receipt prepared during dependency request blocks completion',
    () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final mutations = runner(database);
      final entered = Completer<void>();
      final release = Completer<void>();

      var dependencyCalls = 0;
      var receiptCalls = 0;

      final recovery = ArtistWriteRecoveryService(
        mutationRunner: mutations,
        now: () => now,
        replayGateway: ArtistJournalReplayGateway(
          invokeRpc: (_, _) async {
            receiptCalls++;
            throw StateError('Unexpected receipt submission.');
          },
        ),
      );

      final pipeline = OutboundArtistReceiptPipeline(
        recovery: recovery,
        mutationRunner: mutations,
        ensureDependency: ({required userId, required artist}) async {
          dependencyCalls++;
          entered.complete();
          await release.future;
        },
      );

      try {
        final request = pipeline.guardedDependency(
          userId: 'user_1',
          artist: artist('artist_1'),
        );

        await entered.future;

        try {
          final entry = await enqueue(mutations, 'artist_1');

          await recovery.prepareUpsert(
            userId: 'user_1',
            entry: entry,
            artist: artist('artist_1'),
          );
        } finally {
          release.complete();
        }

        await expectLater(request, throwsStateError);

        expect(dependencyCalls, 1);
        expect(receiptCalls, 0);

        await mutations.run<void>((context) async {
          expect(
            await context.localSyncRepository.getPending('user_1'),
            hasLength(1),
          );

          expect(
            await context.artistWriteJournalRepository!.findUnresolvedForUser(
              'user_1',
            ),
            hasLength(1),
          );
        });
      } finally {
        if (!release.isCompleted) {
          release.complete();
        }
        await database.close();
      }
    },
  );

  test('artist deletion during dependency request remains pending', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    final entered = Completer<void>();
    final release = Completer<void>();

    var dependencyCalls = 0;

    final recovery = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (_, _) async {
          throw StateError('Unexpected receipt submission.');
        },
      ),
    );

    final pipeline = OutboundArtistReceiptPipeline(
      recovery: recovery,
      mutationRunner: mutations,
      ensureDependency: ({required userId, required artist}) async {
        dependencyCalls++;
        entered.complete();
        await release.future;
      },
    );

    try {
      final request = pipeline.guardedDependency(
        userId: 'user_1',
        artist: artist('artist_1'),
      );

      await entered.future;

      try {
        await enqueue(
          mutations,
          'artist_1',
          operation: SyncOutboxOperation.delete,
        );
      } finally {
        release.complete();
      }

      await expectLater(request, throwsStateError);

      expect(dependencyCalls, 1);

      await mutations.run<void>((context) async {
        final pending = await context.localSyncRepository.getPending('user_1');

        expect(pending, hasLength(1));
        expect(pending.single.entityId, 'artist_1');
        expect(pending.single.operation, SyncOutboxOperation.delete);
      });
    } finally {
      if (!release.isCompleted) {
        release.complete();
      }
      await database.close();
    }
  });

  test(
    'failed dependency network request leaves unrelated work intact',
    () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final mutations = runner(database);

      var dependencyCalls = 0;

      final recovery = ArtistWriteRecoveryService(
        mutationRunner: mutations,
        now: () => now,
        replayGateway: ArtistJournalReplayGateway(
          invokeRpc: (_, _) async {
            throw StateError('Unexpected receipt submission.');
          },
        ),
      );

      final pipeline = OutboundArtistReceiptPipeline(
        recovery: recovery,
        mutationRunner: mutations,
        ensureDependency: ({required userId, required artist}) async {
          dependencyCalls++;
          throw StateError('Simulated dependency network failure.');
        },
      );

      try {
        await enqueue(mutations, 'artist_2');

        await expectLater(
          pipeline.guardedDependency(
            userId: 'user_1',
            artist: artist('artist_1'),
          ),
          throwsStateError,
        );

        expect(dependencyCalls, 1);

        await mutations.run<void>((context) async {
          final pending = await context.localSyncRepository.getPending(
            'user_1',
          );

          expect(pending, hasLength(1));
          expect(pending.single.entityId, 'artist_2');

          expect(
            await context.artistWriteJournalRepository!.findUnresolvedForUser(
              'user_1',
            ),
            isEmpty,
          );
        });
      } finally {
        await database.close();
      }
    },
  );
}
