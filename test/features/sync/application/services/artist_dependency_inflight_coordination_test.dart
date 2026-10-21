import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/services/artist_dependency_recovery_service.dart';
import 'package:sonus_next/features/sync/application/services/artist_write_recovery_service.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/application/services/outbound_artist_receipt_pipeline.dart';
import 'package:sonus_next/features/sync/data/gateways/artist_journal_replay_gateway.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  final now = DateTime.utc(2026, 10, 20, 12);

  CloudArtistRecord artist() => CloudArtistRecord(
    id: 'artist-1',
    userId: 'user-1',
    name: 'Original Artist',
    canonicalName: 'original artist',
    createdAt: now,
    updatedAt: now,
  );

  test(
    'edit during receipt replay blocks dependent completion without losing edit',
    () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );

      final runner = SyncMutationTransactionRunner(
        appDatabase: database,
        generateId: () => 'explicit-outbox-1',
        now: () => now,
      );

      final rpcStarted = Completer<void>();
      final releaseRpc = Completer<void>();

      var dependencyCalls = 0;
      var explicitCalls = 0;

      final dependencyRecovery = ArtistDependencyRecoveryService(
        mutationRunner: runner,
        generateRequestId: () => 'dependency-request-1',
        now: () => now,
        replayReceipt: (entry) async {
          dependencyCalls++;

          // The request must already be committed to SQLite.
          await runner.run<void>((context) async {
            final stored = await context.artistDependencyJournalRepository!
                .findUnresolved(userId: 'user-1', artistId: 'artist-1');

            expect(stored, isNotNull);
            expect(stored!.sameSnapshot(entry), isTrue);
          });

          rpcStarted.complete();
          await releaseRpc.future;

          return const CloudConditionalWriteResult(
            outcome: CloudConditionalWriteOutcome.applied,
            serverRevision: 1,
          );
        },
      );

      final explicitRecovery = ArtistWriteRecoveryService(
        mutationRunner: runner,
        now: () => now,
        replayGateway: ArtistJournalReplayGateway(
          invokeRpc: (_, _) async {
            explicitCalls++;
            throw StateError('Unexpected explicit receipt submission.');
          },
        ),
      );

      final pipeline = OutboundArtistReceiptPipeline(
        recovery: explicitRecovery,
        mutationRunner: runner,
        ensureDependency: dependencyRecovery.ensure,
      );

      try {
        final request = pipeline.guardedDependency(
          userId: 'user-1',
          artist: artist(),
        );

        // Observe the dependency while its network response is pending.
        await rpcStarted.future;

        try {
          // A new explicit edit commits while the network call is in flight.
          await runner.run<void>((context) async {
            await context.localSyncRepository.recordUpsert(
              userId: 'user-1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist-1',
            );
          });
        } finally {
          releaseRpc.complete();
        }

        // The server created the artist, but the pipeline must not
        // permit a dependent upload to proceed past this guard.
        await expectLater(request, throwsStateError);

        expect(dependencyCalls, 1);
        expect(explicitCalls, 0);

        await runner.run<void>((context) async {
          final baseline = await context.cloudRevisionBaselineRepository!
              .getRevision(
                userId: 'user-1',
                entityType: CloudDataEntity.artist,
                entityId: 'artist-1',
              );

          // Verified dependency creation is not rolled back simply
          // because a newer edit arrived.
          expect(baseline, 1);

          final dependency = await context.artistDependencyJournalRepository!
              .findUnresolved(userId: 'user-1', artistId: 'artist-1');

          expect(dependency, isNull);

          // Crucially, dependency completion never acknowledges the edit.
          final pending = await context.localSyncRepository.getPending(
            'user-1',
          );

          expect(pending, hasLength(1));
          expect(pending.single.entityType, CloudDataEntity.artist);
          expect(pending.single.entityId, 'artist-1');
          expect(pending.single.mutationRevision, 1);

          expect(
            await context.artistWriteJournalRepository!.findUnresolved(
              userId: 'user-1',
              artistId: 'artist-1',
            ),
            isNull,
          );
        });
      } finally {
        if (!releaseRpc.isCompleted) {
          releaseRpc.complete();
        }
        await database.close();
      }
    },
  );
}
