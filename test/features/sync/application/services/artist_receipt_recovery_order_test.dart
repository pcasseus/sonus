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

  CloudArtistRecord artist(String id) => CloudArtistRecord(
    id: id,
    userId: 'user-1',
    name: 'Artist $id',
    canonicalName: 'artist $id',
    createdAt: now,
    updatedAt: now,
  );

  Future<void> exerciseRecovery({required bool failDependency}) async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextOutbox = 0;
    final events = <String>[];

    final runner = SyncMutationTransactionRunner(
      appDatabase: database,
      generateId: () => 'explicit-outbox-${++nextOutbox}',
      now: () => now,
    );

    final dependencyRecovery = ArtistDependencyRecoveryService(
      mutationRunner: runner,
      generateRequestId: () => 'dependency-request-1',
      now: () => now,
      replayReceipt: (entry) async {
        events.add('dependency');

        expect(entry.artistId, 'artist-1');

        if (failDependency) {
          throw StateError('Simulated unresolved dependency response.');
        }

        return const CloudConditionalWriteResult(
          outcome: CloudConditionalWriteOutcome.replayed,
          serverRevision: 1,
        );
      },
    );

    final explicitRecovery = ArtistWriteRecoveryService(
      mutationRunner: runner,
      now: () => now,
      replayGateway: ArtistJournalReplayGateway(
        invokeRpc: (functionName, parameters) async {
          events.add('explicit');

          expect(functionName, 'create_artist_with_receipt');
          expect(parameters['p_artist_id'], 'artist-2');

          return [
            {'outcome': 'applied', 'server_revision': 1},
          ];
        },
      ),
    );

    final pipeline = OutboundArtistReceiptPipeline(
      recovery: explicitRecovery,
      dependencyRecovery: dependencyRecovery,
      mutationRunner: runner,
      ensureDependency: ({required userId, required artist}) async {
        throw StateError('Unexpected new dependency request.');
      },
    );

    try {
      // Prepare dependency artist-1 first.
      final dependency = await dependencyRecovery.prepare(
        userId: 'user-1',
        artist: artist('artist-1'),
      );

      expect(dependency, isNotNull);

      // Prepare an independent explicit artist-2 receipt.
      await runner.run<void>((context) async {
        await context.localSyncRepository.recordUpsert(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-2',
        );
      });

      final pending = await runner.run(
        (context) => context.localSyncRepository.getPending('user-1'),
      );

      expect(pending, hasLength(1));

      await explicitRecovery.prepareUpsert(
        userId: 'user-1',
        entry: pending.single,
        artist: artist('artist-2'),
      );

      // Both requests must be durable before recovery begins.
      await runner.run<void>((context) async {
        expect(
          await context.artistDependencyJournalRepository!
              .findUnresolvedForUser('user-1'),
          hasLength(1),
        );

        expect(
          await context.artistWriteJournalRepository!.findUnresolvedForUser(
            'user-1',
          ),
          hasLength(1),
        );
      });

      if (failDependency) {
        await expectLater(pipeline.recover('user-1'), throwsStateError);

        expect(events, ['dependency']);
      } else {
        await pipeline.recover('user-1');

        expect(events, ['dependency', 'explicit']);
      }

      await runner.run<void>((context) async {
        final dependencies = await context.artistDependencyJournalRepository!
            .findUnresolvedForUser('user-1');

        final explicit = await context.artistWriteJournalRepository!
            .findUnresolvedForUser('user-1');

        final remaining = await context.localSyncRepository.getPending(
          'user-1',
        );

        final dependencyBaseline = await context
            .cloudRevisionBaselineRepository!
            .getRevision(
              userId: 'user-1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist-1',
            );

        final explicitBaseline = await context.cloudRevisionBaselineRepository!
            .getRevision(
              userId: 'user-1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist-2',
            );

        if (failDependency) {
          // Neither journal may be acknowledged on failure.
          expect(dependencies, hasLength(1));
          expect(explicit, hasLength(1));
          expect(remaining, hasLength(1));
          expect(dependencyBaseline, isNull);
          expect(explicitBaseline, isNull);
        } else {
          expect(dependencies, isEmpty);
          expect(explicit, isEmpty);
          expect(remaining, isEmpty);
          expect(dependencyBaseline, 1);
          expect(explicitBaseline, 1);
        }
      });
    } finally {
      await database.close();
    }
  }

  test('startup recovers dependency before explicit artist receipt', () async {
    await exerciseRecovery(failDependency: false);
  });

  test('dependency failure blocks explicit artist recovery', () async {
    await exerciseRecovery(failDependency: true);
  });
}
