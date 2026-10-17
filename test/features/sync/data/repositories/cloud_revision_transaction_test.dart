import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late SyncMutationTransactionRunner runner;

  setUp(() async {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    await database.database;

    runner = SyncMutationTransactionRunner(appDatabase: database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> writeBaselineAndCursor() {
    return runner.run<void>((context) async {
      final baselines = context.cloudRevisionBaselineRepository!;

      await baselines.saveObservedRevision(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
        serverRevision: 8,
      );

      await context.localSyncRepository.saveCursor(
        SyncCursor(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          lastServerUpdatedAt: DateTime.utc(2026, 10, 16, 12),
          lastServerId: 'artist-1',
          updatedAt: DateTime.utc(2026, 10, 16, 12),
        ),
      );
    });
  }

  Future<(int?, SyncCursor?)> readPersistedState() {
    return runner.run((context) async {
      final revision = await context.cloudRevisionBaselineRepository!
          .getRevision(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist-1',
          );

      final cursor = await context.localSyncRepository.getCursor(
        'user-1',
        CloudDataEntity.artist,
      );

      return (revision, cursor);
    });
  }

  test('successful transaction persists baseline and cursor', () async {
    await writeBaselineAndCursor();

    final (revision, cursor) = await readPersistedState();

    expect(revision, 8);
    expect(cursor, isNotNull);
    expect(cursor?.lastServerId, 'artist-1');
    expect(cursor?.lastServerUpdatedAt, DateTime.utc(2026, 10, 16, 12));
  });

  test('failed transaction rolls back baseline and cursor', () async {
    await expectLater(
      runner.run<void>((context) async {
        await context.cloudRevisionBaselineRepository!.saveObservedRevision(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
          serverRevision: 8,
        );

        await context.localSyncRepository.saveCursor(
          SyncCursor(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            lastServerUpdatedAt: DateTime.utc(2026, 10, 16, 12),
            lastServerId: 'artist-1',
            updatedAt: DateTime.utc(2026, 10, 16, 12),
          ),
        );

        throw StateError('Simulated failure before commit.');
      }),
      throwsStateError,
    );

    final (revision, cursor) = await readPersistedState();

    expect(revision, isNull);
    expect(cursor, isNull);
  });
  test('failed transaction rolls back artist, baseline, and cursor', () async {
    await expectLater(
      runner.run<void>((context) async {
        await context.artistRepository.create(
          Artist(
            id: 'artist-1',
            name: 'Uncommitted Artist',
            canonicalName: 'uncommitted artist',
            createdAt: DateTime.utc(2026, 10, 16),
            updatedAt: DateTime.utc(2026, 10, 16),
          ),
        );

        await context.cloudRevisionBaselineRepository!.saveObservedRevision(
          userId: 'user-1',
          entityType: CloudDataEntity.artist,
          entityId: 'artist-1',
          serverRevision: 8,
        );

        await context.localSyncRepository.saveCursor(
          SyncCursor(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            lastServerUpdatedAt: DateTime.utc(2026, 10, 16, 12),
            lastServerId: 'artist-1',
            updatedAt: DateTime.utc(2026, 10, 16, 12),
          ),
        );

        throw StateError('Simulated reconciliation failure.');
      }),
      throwsStateError,
    );

    await runner.run<void>((context) async {
      final artist = await context.artistRepository.getById('artist-1');

      final revision = await context.cloudRevisionBaselineRepository!
          .getRevision(
            userId: 'user-1',
            entityType: CloudDataEntity.artist,
            entityId: 'artist-1',
          );

      final cursor = await context.localSyncRepository.getCursor(
        'user-1',
        CloudDataEntity.artist,
      );

      expect(artist, isNull);
      expect(revision, isNull);
      expect(cursor, isNull);
    });
  });
}
