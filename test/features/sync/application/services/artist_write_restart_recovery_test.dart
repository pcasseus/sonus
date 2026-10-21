import 'dart:io';

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

  SyncMutationTransactionRunner runner(AppDatabase db) =>
      SyncMutationTransactionRunner(
        appDatabase: db,
        generateId: () => 'outbox_1',
        now: () => now,
      );

  CloudArtistRecord artist() => CloudArtistRecord(
    id: 'artist_1',
    userId: 'user_1',
    name: 'Original Artist',
    canonicalName: 'original artist',
    createdAt: now.subtract(const Duration(days: 1)),
    updatedAt: now,
  );

  Future<SyncOutboxEntry> addArtist(
    SyncMutationTransactionRunner runner,
  ) async {
    return runner.run<SyncOutboxEntry>((context) async {
      await context.localSyncRepository.recordUpsert(
        userId: 'user_1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist_1',
      );

      final pending = await context.localSyncRepository.getPending('user_1');
      return pending.single;
    });
  }

  test('lost creation response recovers after SQLite restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_artist_restart_',
    );
    final path = '${directory.path}/sonus.db';

    final first = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path,
    );

    try {
      final mutations = runner(first);

      final service = ArtistWriteRecoveryService(
        mutationRunner: mutations,
        now: () => now,
        replayGateway: ArtistJournalReplayGateway(
          invokeRpc: (_, _) async {
            throw StateError('Connection lost after server write.');
          },
        ),
      );

      final entry = await addArtist(mutations);

      final prepared = await service.prepareUpsert(
        userId: 'user_1',
        entry: entry,
        artist: artist(),
      );

      await expectLater(service.submitPrepared(prepared), throwsStateError);
    } finally {
      await first.close();
    }

    final second = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path,
    );

    try {
      final mutations = runner(second);
      var calls = 0;

      final recovered = ArtistWriteRecoveryService(
        mutationRunner: mutations,
        now: () => now.add(const Duration(hours: 2)),
        replayGateway: ArtistJournalReplayGateway(
          invokeRpc: (function, params) async {
            calls++;
            expect(function, 'create_artist_with_receipt');
            expect(params['p_name'], 'Original Artist');
            expect(params['p_mutation_revision'], 1);
            return [
              {'outcome': 'replayed', 'server_revision': 1},
            ];
          },
        ),
      );

      await recovered.recoverUnresolved('user_1');
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
      await second.close();
      await directory.delete(recursive: true);
    }
  });

  test('newer edit survives restart and recovery of older write', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_artist_newer_edit_',
    );
    final path = '${directory.path}/sonus.db';

    final first = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path,
    );

    try {
      final mutations = runner(first);
      final entry = await addArtist(mutations);

      final service = ArtistWriteRecoveryService(
        mutationRunner: mutations,
        now: () => now,
        replayGateway: ArtistJournalReplayGateway(
          invokeRpc: (_, _) async {
            throw StateError('Simulated missing response.');
          },
        ),
      );

      final prepared = await service.prepareUpsert(
        userId: 'user_1',
        entry: entry,
        artist: artist(),
      );

      await expectLater(service.submitPrepared(prepared), throwsStateError);

      await mutations.run<void>((context) async {
        await context.localSyncRepository.recordUpsert(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
        );
      });
    } finally {
      await first.close();
    }

    final second = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path,
    );

    try {
      final mutations = runner(second);

      final service = ArtistWriteRecoveryService(
        mutationRunner: mutations,
        now: () => now,
        replayGateway: ArtistJournalReplayGateway(
          invokeRpc: (_, params) async {
            expect(params['p_name'], 'Original Artist');
            expect(params['p_mutation_revision'], 1);

            return [
              {'outcome': 'replayed', 'server_revision': 1},
            ];
          },
        ),
      );

      await service.recoverUnresolved('user_1');

      await mutations.run<void>((context) async {
        final pending = await context.localSyncRepository.getPending('user_1');

        expect(pending, hasLength(1));
        expect(pending.single.mutationRevision, 2);
        expect(pending.single.operation, SyncOutboxOperation.upsert);

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
      await second.close();
      await directory.delete(recursive: true);
    }
  });
}
