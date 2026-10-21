import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/services/artist_dependency_recovery_service.dart';
import 'package:sonus_next/features/sync/application/services/artist_write_recovery_service.dart';
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
    'unresolved dependency blocks newer explicit receipt preparation',
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

      try {
        final dependencyRecovery = ArtistDependencyRecoveryService(
          mutationRunner: runner,
          generateRequestId: () => 'dependency-request-1',
          now: () => now,
          replayReceipt: (_) async {
            throw StateError('Dependency RPC must not execute in this test.');
          },
        );

        // First, durably prepare a dependency receipt without
        // sending it to the server.
        final dependency = await dependencyRecovery.prepare(
          userId: 'user-1',
          artist: artist(),
        );

        expect(dependency, isNotNull);

        // Then an explicit artist edit arrives.
        await runner.run<void>((context) async {
          await context.localSyncRepository.recordUpsert(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist-1',
          );
        });

        final pending = await runner.run(
          (context) => context.localSyncRepository.getPending('user-1'),
        );

        expect(pending, hasLength(1));

        var explicitNetworkCalls = 0;

        final explicitRecovery = ArtistWriteRecoveryService(
          mutationRunner: runner,
          now: () => now,
          replayGateway: ArtistJournalReplayGateway(
            invokeRpc: (_, _) async {
              explicitNetworkCalls++;
              throw StateError('Explicit RPC must not execute.');
            },
          ),
        );

        // The explicit writer must not prepare a second
        // create receipt until the older dependency is resolved.
        await expectLater(
          explicitRecovery.prepareUpsert(
            userId: 'user-1',
            entry: pending.single,
            artist: artist(),
          ),
          throwsStateError,
        );

        await runner.run<void>((context) async {
          final dependencies = context.artistDependencyJournalRepository!;
          final explicitWrites = context.artistWriteJournalRepository!;

          final storedDependency = await dependencies.findUnresolved(
            userId: 'user-1',
            artistId: 'artist-1',
          );

          expect(storedDependency, isNotNull);
          expect(storedDependency!.sameSnapshot(dependency!), isTrue);

          // No competing explicit receipt should be created.
          expect(
            await explicitWrites.findUnresolved(
              userId: 'user-1',
              artistId: 'artist-1',
            ),
            isNull,
          );

          // The newer local edit must remain pending.
          expect(
            await context.localSyncRepository.getPending('user-1'),
            hasLength(1),
          );
        });

        expect(explicitNetworkCalls, 0);
      } finally {
        await database.close();
      }
    },
  );

  test(
    'dependency receipt completes before newer explicit update prepares',
    () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );

      final runner = SyncMutationTransactionRunner(
        appDatabase: database,
        generateId: () => 'explicit-outbox-2',
        now: () => now,
      );

      try {
        final dependencyRecovery = ArtistDependencyRecoveryService(
          mutationRunner: runner,
          generateRequestId: () => 'dependency-request-2',
          now: () => now,
          replayReceipt: (_) async {
            return const CloudConditionalWriteResult(
              outcome: CloudConditionalWriteOutcome.replayed,
              serverRevision: 1,
            );
          },
        );

        final dependency = await dependencyRecovery.prepare(
          userId: 'user-1',
          artist: artist(),
        );

        expect(dependency, isNotNull);

        // This edit must survive the older dependency's completion.
        await runner.run<void>((context) async {
          await context.localSyncRepository.recordUpsert(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist-1',
          );
        });

        await dependencyRecovery.submitPrepared(dependency!);

        final pending = await runner.run(
          (context) => context.localSyncRepository.getPending('user-1'),
        );

        expect(pending, hasLength(1));

        final explicitRecovery = ArtistWriteRecoveryService(
          mutationRunner: runner,
          now: () => now,
          replayGateway: ArtistJournalReplayGateway(
            invokeRpc: (_, _) async {
              throw StateError('No explicit RPC expected during preparation.');
            },
          ),
        );

        final explicit = await explicitRecovery.prepareUpsert(
          userId: 'user-1',
          entry: pending.single,
          artist: artist(),
        );

        // The server already has the dependency-created artist.
        // The explicit edit must therefore use conditional update.
        expect(explicit.expectedServerRevision, 1);
        expect(explicit.operation.name, 'update');
        expect(explicit.outboxId, pending.single.id);
        expect(explicit.mutationRevision, pending.single.mutationRevision);

        final envelope = jsonDecode(explicit.requestJson) as Map;
        final arguments = envelope['parameters'] as Map;

        expect(envelope['function_name'], 'update_artist_record_with_receipt');
        expect(arguments['p_expected_revision'], 1);
        expect(arguments['p_outbox_id'], pending.single.id);

        await runner.run<void>((context) async {
          expect(
            await context.cloudRevisionBaselineRepository!.getRevision(
              userId: 'user-1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist-1',
            ),
            1,
          );

          expect(
            await context.artistDependencyJournalRepository!.findUnresolved(
              userId: 'user-1',
              artistId: 'artist-1',
            ),
            isNull,
          );

          final storedExplicit = await context.artistWriteJournalRepository!
              .findUnresolved(userId: 'user-1', artistId: 'artist-1');

          expect(storedExplicit, isNotNull);
          expect(storedExplicit!.sameSnapshot(explicit), isTrue);

          // Explicit preparation must not acknowledge the outbox.
          expect(
            await context.localSyncRepository.getPending('user-1'),
            hasLength(1),
          );
        });
      } finally {
        await database.close();
      }
    },
  );
}
