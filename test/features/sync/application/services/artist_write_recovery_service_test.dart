import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/services/artist_write_recovery_service.dart';
import 'package:sonus_next/features/sync/data/gateways/artist_journal_replay_gateway.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  final now = DateTime.utc(2026, 10, 18, 12);

  CloudArtistRecord artist() => CloudArtistRecord(
    id: 'artist_1',
    userId: 'user_1',
    name: 'Original Name',
    canonicalName: 'original name',
    createdAt: now.subtract(const Duration(days: 2)),
    updatedAt: now,
  );

  SyncMutationTransactionRunner runner(AppDatabase database) =>
      SyncMutationTransactionRunner(
        appDatabase: database,
        generateId: () => 'outbox_1',
        now: () => now,
      );

  Future<SyncOutboxEntry> recordArtist(
    SyncMutationTransactionRunner mutations,
  ) async {
    await mutations.run<void>((context) async {
      await context.localSyncRepository.recordUpsert(
        userId: 'user_1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist_1',
      );
    });

    return mutations.run<SyncOutboxEntry>((context) async {
      final pending = await context.localSyncRepository.getPending('user_1');
      return pending.single;
    });
  }

  test('preparation persists before RPC and replay clears journal', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    var calls = 0;

    final service = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (name, params) async {
          calls++;
          expect(name, 'create_artist_with_receipt');
          expect(params['p_name'], 'Original Name');
          return [
            {'outcome': 'applied', 'server_revision': 1},
          ];
        },
      ),
    );

    try {
      final outbox = await recordArtist(mutations);

      final prepared = await service.prepareUpsert(
        userId: 'user_1',
        entry: outbox,
        artist: artist(),
      );

      expect(calls, 0);

      await mutations.run<void>((context) async {
        final journal = await context.artistWriteJournalRepository!
            .findUnresolvedForUser('user_1');
        expect(journal, hasLength(1));
        expect(journal.single.sameSnapshot(prepared), isTrue);
      });

      await service.submitPrepared(prepared);
      expect(calls, 1);

      await mutations.run<void>((context) async {
        expect(
          await context.artistWriteJournalRepository!.findUnresolvedForUser(
            'user_1',
          ),
          isEmpty,
        );
        expect(await context.localSyncRepository.getPending('user_1'), isEmpty);
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

  test('lost response retains exact request for later recovery', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    var attempts = 0;

    final service = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (name, params) async {
          attempts++;
          if (attempts == 1) {
            throw StateError('Network response lost.');
          }
          expect(name, 'create_artist_with_receipt');
          expect(params['p_name'], 'Original Name');
          return [
            {'outcome': 'replayed', 'server_revision': 1},
          ];
        },
      ),
    );

    try {
      final outbox = await recordArtist(mutations);
      final prepared = await service.prepareUpsert(
        userId: 'user_1',
        entry: outbox,
        artist: artist(),
      );

      await expectLater(service.submitPrepared(prepared), throwsStateError);

      await mutations.run<void>((context) async {
        expect(
          await context.artistWriteJournalRepository!.findUnresolvedForUser(
            'user_1',
          ),
          hasLength(1),
        );
      });

      await service.recoverUnresolved('user_1');
      expect(attempts, 2);

      await mutations.run<void>((context) async {
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

  test('newer local edit survives recovery of older receipt', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);

    final service = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (_, _) async => [
          {'outcome': 'replayed', 'server_revision': 1},
        ],
      ),
    );

    try {
      final outbox = await recordArtist(mutations);
      await service.prepareUpsert(
        userId: 'user_1',
        entry: outbox,
        artist: artist(),
      );

      await mutations.run<void>((context) async {
        await context.localSyncRepository.recordUpsert(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
        );
      });

      await service.recoverUnresolved('user_1');

      await mutations.run<void>((context) async {
        final pending = await context.localSyncRepository.getPending('user_1');
        expect(pending, hasLength(1));
        expect(pending.single.mutationRevision, 2);
        expect(
          await context.cloudRevisionBaselineRepository!.getRevision(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
          ),
          1,
        );
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

  test('conflict preserves unresolved request and outbox', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);

    final service = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (_, _) async => [
          {'outcome': 'conflict', 'server_revision': 7},
        ],
      ),
    );

    try {
      final outbox = await recordArtist(mutations);
      await service.prepareUpsert(
        userId: 'user_1',
        entry: outbox,
        artist: artist(),
      );

      await expectLater(service.recoverUnresolved('user_1'), throwsStateError);

      await mutations.run<void>((context) async {
        expect(
          await context.artistWriteJournalRepository!.findUnresolvedForUser(
            'user_1',
          ),
          hasLength(1),
        );
        expect(
          await context.localSyncRepository.getPending('user_1'),
          hasLength(1),
        );
      });
    } finally {
      await database.close();
    }
  });

  test('changed outbox revision cannot be prepared as fresh request', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);

    final service = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (_, _) async => [
          {'outcome': 'applied', 'server_revision': 1},
        ],
      ),
    );

    try {
      final old = await recordArtist(mutations);

      await mutations.run<void>((context) async {
        await context.localSyncRepository.recordUpsert(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
        );
      });

      await expectLater(
        service.prepareUpsert(userId: 'user_1', entry: old, artist: artist()),
        throwsStateError,
      );
    } finally {
      await database.close();
    }
  });

  test('concurrent replay shares one RPC submission', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    final started = Completer<void>();
    final release = Completer<void>();
    var rpcCalls = 0;

    final service = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (_, _) async {
          rpcCalls++;
          started.complete();
          await release.future;

          return [
            {'outcome': 'applied', 'server_revision': 1},
          ];
        },
      ),
    );

    try {
      final outbox = await recordArtist(mutations);

      final prepared = await service.prepareUpsert(
        userId: 'user_1',
        entry: outbox,
        artist: artist(),
      );

      final first = service.submitPrepared(prepared);
      final second = service.submitPrepared(prepared);

      await started.future;

      try {
        expect(rpcCalls, 1);
        expect(identical(first, second), isTrue);
      } finally {
        release.complete();
      }

      await Future.wait([first, second]);

      expect(rpcCalls, 1);

      await mutations.run<void>((context) async {
        expect(
          await context.artistWriteJournalRepository!.findUnresolvedForUser(
            'user_1',
          ),
          isEmpty,
        );

        expect(await context.localSyncRepository.getPending('user_1'), isEmpty);
      });
    } finally {
      await database.close();
    }
  });

  test('restoration survives reconciliation of older deletion', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);

    final service = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (function, parameters) async {
          expect(function, 'delete_artist_with_receipt');
          expect(parameters['p_expected_revision'], 1);

          return [
            {'outcome': 'replayed', 'server_revision': 2},
          ];
        },
      ),
    );

    try {
      await mutations.run<void>((context) async {
        await context.cloudRevisionBaselineRepository!.saveObservedRevision(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
          serverRevision: 1,
        );

        await context.localSyncRepository.recordDelete(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
        );
      });

      final deletion = await mutations.run<SyncOutboxEntry>((context) async {
        return (await context.localSyncRepository.getPending('user_1')).single;
      });

      final prepared = await service.prepareDelete(
        userId: 'user_1',
        entry: deletion,
      );

      // The artist is restored locally while its older deletion
      // is still waiting for cloud receipt reconciliation.
      await mutations.run<void>((context) async {
        await context.localSyncRepository.recordUpsert(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
        );
      });

      await service.submitPrepared(prepared);

      await mutations.run<void>((context) async {
        final pending = await context.localSyncRepository.getPending('user_1');

        expect(pending, hasLength(1));
        expect(pending.single.operation, SyncOutboxOperation.upsert);
        expect(pending.single.mutationRevision, 2);

        expect(
          await context.cloudRevisionBaselineRepository!.getRevision(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
          ),
          2,
        );

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
}
