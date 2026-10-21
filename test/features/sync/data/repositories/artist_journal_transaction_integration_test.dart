import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/artist_write_journal_entry.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  final timestamp = DateTime.utc(2026, 10, 18, 12);

  ArtistWriteJournalEntry journalEntry() {
    return ArtistWriteJournalEntry(
      userId: 'user_1',
      artistId: 'artist_1',
      outboxId: 'outbox_1',
      mutationRevision: 1,
      operation: ArtistWriteJournalOperation.update,
      expectedServerRevision: 7,
      requestJson:
          '{"p_artist_id":"artist_1","p_expected_revision":7,'
          '"p_outbox_id":"outbox_1","p_mutation_revision":1}',
      createdAt: timestamp,
    );
  }

  SyncMutationTransactionRunner runner(AppDatabase database) {
    return SyncMutationTransactionRunner(
      appDatabase: database,
      generateId: () => 'outbox_1',
      now: () => timestamp,
    );
  }

  test('journal preparation rolls back with its SQLite transaction', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    final original = journalEntry();

    try {
      await expectLater(
        mutations.run<void>((context) async {
          final journal = context.artistWriteJournalRepository!;
          await journal.prepare(original);

          await context.localSyncRepository.recordUpsert(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
          );

          throw StateError('Simulated crash before transaction commit.');
        }),
        throwsStateError,
      );

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

  test('journal and outbox preparation commit together', () async {
    final database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final mutations = runner(database);
    final original = journalEntry();

    try {
      await mutations.run<void>((context) async {
        await context.localSyncRepository.recordUpsert(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist_1',
        );
        await context.artistWriteJournalRepository!.prepare(original);
      });

      await mutations.run<void>((context) async {
        final pending = await context.localSyncRepository.getPending('user_1');
        final journal = await context.artistWriteJournalRepository!
            .findUnresolvedForUser('user_1');

        expect(pending, hasLength(1));
        expect(pending.single.id, 'outbox_1');
        expect(pending.single.mutationRevision, 1);
        expect(journal, hasLength(1));
        expect(journal.single.sameSnapshot(original), isTrue);
      });
    } finally {
      await database.close();
    }
  });

  test(
    'verified completion commits revision outbox and journal atomically',
    () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final mutations = runner(database);
      final original = journalEntry();

      try {
        await mutations.run<void>((context) async {
          await context.localSyncRepository.recordUpsert(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
          );

          await context.artistWriteJournalRepository!.prepare(original);

          await context.cloudRevisionBaselineRepository!.saveObservedRevision(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
            serverRevision: 7,
          );
        });

        await mutations.run<void>((context) async {
          await context.cloudRevisionBaselineRepository!.saveObservedRevision(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
            serverRevision: 8,
          );

          await context.localSyncRepository.markProcessed(
            userId: 'user_1',
            outboxEntryId: 'outbox_1',
            expectedRevision: 1,
            expectedOperation: SyncOutboxOperation.upsert,
          );

          final removed = await context.artistWriteJournalRepository!
              .removeVerified(original);
          expect(removed, 1);
        });

        await mutations.run<void>((context) async {
          expect(
            await context.cloudRevisionBaselineRepository!.getRevision(
              userId: 'user_1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist_1',
            ),
            8,
          );

          expect(
            await context.localSyncRepository.getPending('user_1'),
            isEmpty,
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
    },
  );

  test(
    'failed completion rolls back revision acknowledgement and removal',
    () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final mutations = runner(database);
      final original = journalEntry();

      try {
        await mutations.run<void>((context) async {
          await context.localSyncRepository.recordUpsert(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
          );

          await context.artistWriteJournalRepository!.prepare(original);

          await context.cloudRevisionBaselineRepository!.saveObservedRevision(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
            serverRevision: 7,
          );
        });

        await expectLater(
          mutations.run<void>((context) async {
            await context.cloudRevisionBaselineRepository!.saveObservedRevision(
              userId: 'user_1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist_1',
              serverRevision: 8,
            );

            await context.localSyncRepository.markProcessed(
              userId: 'user_1',
              outboxEntryId: 'outbox_1',
              expectedRevision: 1,
              expectedOperation: SyncOutboxOperation.upsert,
            );

            expect(
              await context.artistWriteJournalRepository!.removeVerified(
                original,
              ),
              1,
            );

            throw StateError('Simulated crash before completion commit.');
          }),
          throwsStateError,
        );

        await mutations.run<void>((context) async {
          expect(
            await context.cloudRevisionBaselineRepository!.getRevision(
              userId: 'user_1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist_1',
            ),
            7,
          );

          final pending = await context.localSyncRepository.getPending(
            'user_1',
          );
          expect(pending, hasLength(1));
          expect(pending.single.id, 'outbox_1');

          final unresolved = await context.artistWriteJournalRepository!
              .findUnresolvedForUser('user_1');
          expect(unresolved, hasLength(1));
          expect(unresolved.single.sameSnapshot(original), isTrue);
        });
      } finally {
        await database.close();
      }
    },
  );

  test(
    'newer local edit survives verified earlier receipt completion',
    () async {
      final database = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final mutations = runner(database);
      final original = journalEntry();

      try {
        await mutations.run<void>((context) async {
          await context.localSyncRepository.recordUpsert(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
          );

          await context.artistWriteJournalRepository!.prepare(original);
        });

        await mutations.run<void>((context) async {
          await context.localSyncRepository.recordUpsert(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
          );
        });

        await mutations.run<void>((context) async {
          await context.cloudRevisionBaselineRepository!.saveObservedRevision(
            userId: 'user_1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist_1',
            serverRevision: 8,
          );

          await context.localSyncRepository.markProcessed(
            userId: 'user_1',
            outboxEntryId: 'outbox_1',
            expectedRevision: 1,
            expectedOperation: SyncOutboxOperation.upsert,
          );

          expect(
            await context.artistWriteJournalRepository!.removeVerified(
              original,
            ),
            1,
          );
        });

        await mutations.run<void>((context) async {
          final pending = await context.localSyncRepository.getPending(
            'user_1',
          );

          expect(pending, hasLength(1));
          expect(pending.single.mutationRevision, 2);
          expect(pending.single.operation, SyncOutboxOperation.upsert);

          expect(
            await context.cloudRevisionBaselineRepository!.getRevision(
              userId: 'user_1',
              entityType: CloudDataEntity.artist,
              entityId: 'artist_1',
            ),
            8,
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
    },
  );
}
