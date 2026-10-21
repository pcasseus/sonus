import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/application/services/artist_dependency_recovery_service.dart';
import 'package:sonus_next/features/sync/application/services/cloud_conditional_write_result.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/artist_dependency_journal_entry.dart';
import 'package:sonus_next/features/sync/domain/models/cloud_records.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  final now = DateTime.utc(2026, 10, 20, 12);

  CloudArtistRecord artist() => CloudArtistRecord(
    id: 'artist-1',
    userId: 'user-1',
    name: 'Dependency Artist',
    canonicalName: 'dependency artist',
    createdAt: now,
    updatedAt: now,
  );

  Future<void> withDatabase(
    Future<void> Function(AppDatabase app, SyncMutationTransactionRunner runner)
    action,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_dependency_recovery_',
    );

    final app = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/sonus.db',
    );

    try {
      await app.database;
      await action(app, SyncMutationTransactionRunner(appDatabase: app));
    } finally {
      await app.close();
      await directory.delete(recursive: true);
    }
  }

  ArtistDependencyRecoveryService service(
    SyncMutationTransactionRunner runner, {
    required Future<CloudConditionalWriteResult> Function(
      ArtistDependencyJournalEntry,
    )
    replay,
    String Function()? generateId,
  }) {
    return ArtistDependencyRecoveryService(
      mutationRunner: runner,
      replayReceipt: replay,
      generateRequestId: generateId ?? () => 'dependency-request-1',
      now: () => now,
    );
  }

  Future<int?> baseline(SyncMutationTransactionRunner runner) {
    return runner.run((context) {
      return context.cloudRevisionBaselineRepository!.getRevision(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      );
    });
  }

  Future<ArtistDependencyJournalEntry?> journal(
    SyncMutationTransactionRunner runner,
  ) {
    return runner.run((context) {
      return context.artistDependencyJournalRepository!.findUnresolved(
        userId: 'user-1',
        artistId: 'artist-1',
      );
    });
  }

  test('successful dependency creates baseline and retires journal', () async {
    await withDatabase((app, runner) async {
      var calls = 0;

      final recovery = service(
        runner,
        replay: (entry) async {
          calls++;
          final decoded = jsonDecode(entry.requestJson) as Map;
          final parameters = decoded['parameters'] as Map;

          expect(decoded['function_name'], 'create_artist_with_receipt');
          expect(parameters['p_artist_id'], 'artist-1');
          expect(parameters['p_outbox_id'], entry.requestId);
          expect(parameters['p_mutation_revision'], 1);

          return const CloudConditionalWriteResult(
            outcome: CloudConditionalWriteOutcome.applied,
            serverRevision: 1,
          );
        },
      );

      await recovery.ensure(userId: 'user-1', artist: artist());

      expect(calls, 1);
      expect(await baseline(runner), 1);
      expect(await journal(runner), isNull);

      await recovery.ensure(userId: 'user-1', artist: artist());
      expect(calls, 1);
    });
  });

  test('lost response recovers the identical snapshot after restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sonus_dependency_crash_',
    );
    final location = '${directory.path}/sonus.db';

    String? originalSnapshot;
    String? originalRequestId;

    final first = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: location,
    );

    try {
      final runner = SyncMutationTransactionRunner(appDatabase: first);

      final recovery = service(
        runner,
        replay: (entry) async {
          originalSnapshot = entry.requestJson;
          originalRequestId = entry.requestId;
          throw StateError('Transport failed after server commit.');
        },
      );

      await expectLater(
        recovery.ensure(userId: 'user-1', artist: artist()),
        throwsStateError,
      );

      expect(await baseline(runner), isNull);
      expect(await journal(runner), isNotNull);
    } finally {
      await first.close();
    }

    final second = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: location,
    );

    try {
      final runner = SyncMutationTransactionRunner(appDatabase: second);
      var calls = 0;

      final recovery = service(
        runner,
        generateId: () => throw StateError(
          'Restart must not generate a replacement request.',
        ),
        replay: (entry) async {
          calls++;
          expect(entry.requestId, originalRequestId);
          expect(entry.requestJson, originalSnapshot);

          return const CloudConditionalWriteResult(
            outcome: CloudConditionalWriteOutcome.replayed,
            serverRevision: 1,
          );
        },
      );

      await recovery.recoverUnresolved('user-1');

      expect(calls, 1);
      expect(await baseline(runner), 1);
      expect(await journal(runner), isNull);
    } finally {
      await second.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'unrelated cloud conflict preserves missing baseline and journal',
    () async {
      await withDatabase((app, runner) async {
        final recovery = service(
          runner,
          replay: (entry) async {
            return const CloudConditionalWriteResult(
              outcome: CloudConditionalWriteOutcome.conflict,
              serverRevision: 4,
            );
          },
        );

        await expectLater(
          recovery.ensure(userId: 'user-1', artist: artist()),
          throwsStateError,
        );

        expect(await baseline(runner), isNull);
        expect(await journal(runner), isNotNull);
      });
    },
  );

  test('invalid successful revision cannot finalize dependency', () async {
    await withDatabase((app, runner) async {
      final recovery = service(
        runner,
        replay: (entry) async {
          return const CloudConditionalWriteResult(
            outcome: CloudConditionalWriteOutcome.replayed,
            serverRevision: 2,
          );
        },
      );

      await expectLater(
        recovery.ensure(userId: 'user-1', artist: artist()),
        throwsStateError,
      );

      expect(await baseline(runner), isNull);
      expect(await journal(runner), isNotNull);
    });
  });

  test('newer local artist edit survives recovery finalization', () async {
    await withDatabase((app, runner) async {
      final recovery = service(
        runner,
        replay: (entry) async {
          return const CloudConditionalWriteResult(
            outcome: CloudConditionalWriteOutcome.replayed,
            serverRevision: 1,
          );
        },
      );

      final prepared = await recovery.prepare(
        userId: 'user-1',
        artist: artist(),
      );

      expect(prepared, isNotNull);

      // The edit arrives after dependency preparation.
      await runner.run<void>((context) async {
        await context.localSyncRepository.recordUpsert(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        );
      });

      await recovery.submitPrepared(prepared!);

      final pending = await runner.run(
        (context) => context.localSyncRepository.getPending('user-1'),
      );

      expect(await baseline(runner), 1);
      expect(await journal(runner), isNull);
      expect(
        pending.where(
          (entry) =>
              entry.entityType == CloudDataEntity.artist &&
              entry.entityId == 'artist-1',
        ),
        hasLength(1),
      );
    });
  });

  test('pending explicit edit blocks preparation before network', () async {
    await withDatabase((app, runner) async {
      await runner.run<void>((context) async {
        await context.localSyncRepository.recordUpsert(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
        );
      });

      var calls = 0;

      final recovery = service(
        runner,
        replay: (entry) async {
          calls++;
          return const CloudConditionalWriteResult(
            outcome: CloudConditionalWriteOutcome.applied,
            serverRevision: 1,
          );
        },
      );

      await expectLater(
        recovery.ensure(userId: 'user-1', artist: artist()),
        throwsStateError,
      );

      expect(calls, 0);
      expect(await journal(runner), isNull);
      expect(await baseline(runner), isNull);
    });
  });
}
