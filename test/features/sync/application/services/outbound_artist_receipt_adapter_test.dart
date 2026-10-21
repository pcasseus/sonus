import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/services/artist_write_recovery_service.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_receipt_adapter.dart';
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
    name: 'Original Artist',
    canonicalName: 'original artist',
    createdAt: now.subtract(const Duration(days: 1)),
    updatedAt: now,
  );

  SyncMutationTransactionRunner runner(AppDatabase db) =>
      SyncMutationTransactionRunner(
        appDatabase: db,
        generateId: () => 'outbox_1',
        now: () => now,
      );

  Future<SyncOutboxEntry> enqueue(
    SyncMutationTransactionRunner mutations,
    SyncOutboxOperation operation,
  ) async {
    await mutations.run<void>((context) async {
      if (operation == SyncOutboxOperation.upsert) {
        await context.localSyncRepository.recordUpsert(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
        );
      } else {
        await context.localSyncRepository.recordDelete(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
        );
      }
    });

    return mutations.run<SyncOutboxEntry>((context) async {
      return (await context.localSyncRepository.getPending('user_1')).single;
    });
  }

  test('upsert prepares durable journal before calling RPC', () async {
    final db = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(db);
    var calls = 0;

    final recovery = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (function, parameters) async {
          calls++;
          expect(function, 'create_artist_with_receipt');
          expect(parameters['p_name'], 'Original Artist');

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

    try {
      final entry = await enqueue(mutations, SyncOutboxOperation.upsert);

      final adapter = OutboundArtistReceiptAdapter(recovery: recovery);

      await adapter.pushUpsert(
        userId: 'user_1',
        entry: entry,
        artist: artist(),
      );

      expect(calls, 1);

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
      await db.close();
    }
  });

  test('deletion uses journal and reconciles server revision', () async {
    final db = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(db);
    var calls = 0;

    final recovery = ArtistWriteRecoveryService(
      mutationRunner: mutations,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (function, parameters) async {
          calls++;
          expect(function, 'delete_artist_with_receipt');
          expect(parameters['p_expected_revision'], 7);

          await mutations.run<void>((context) async {
            expect(
              await context.artistWriteJournalRepository!.findUnresolvedForUser(
                'user_1',
              ),
              hasLength(1),
            );
          });

          return [
            {'outcome': 'replayed', 'server_revision': 8},
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
          serverRevision: 7,
        );
      });

      final entry = await enqueue(mutations, SyncOutboxOperation.delete);

      final adapter = OutboundArtistReceiptAdapter(recovery: recovery);

      await adapter.pushDelete(userId: 'user_1', entry: entry);

      expect(calls, 1);

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
          8,
        );
      });
    } finally {
      await db.close();
    }
  });
}
