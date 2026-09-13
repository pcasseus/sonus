import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SyncMutationTransactionRunner runner;

  final now = DateTime.utc(2026, 9, 13, 12);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextId = 0;

    runner = SyncMutationTransactionRunner(
      appDatabase: appDatabase,
      generateId: () => 'outbox_${++nextId}',
      now: () => now,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('commits entity write and outbox write together', () async {
    final artist = EntityFactory.createArtist(name: 'Atomic Artist', now: now);

    await runner.run((context) async {
      await context.artistRepository.create(artist);

      await context.localSyncRepository.recordUpsert(
        userId: 'user_1',
        entityType: CloudDataEntity.artist,
        entityId: artist.id,
      );
    });

    final db = await appDatabase.database;

    expect(await ArtistDao(db).findById(artist.id), isNotNull);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.artist);
    expect(pending.single.entityId, artist.id);
  });

  test('rolls back entity write when transaction fails', () async {
    final artist = EntityFactory.createArtist(
      name: 'Rollback Artist',
      now: now,
    );

    await expectLater(
      runner.run<void>((context) async {
        await context.artistRepository.create(artist);

        await context.localSyncRepository.recordUpsert(
          userId: 'user_1',
          entityType: CloudDataEntity.artist,
          entityId: artist.id,
        );

        throw StateError('Forced failure');
      }),
      throwsStateError,
    );

    final db = await appDatabase.database;

    expect(await ArtistDao(db).findById(artist.id), isNull);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rolls back entity write when outbox write fails', () async {
    final artist = EntityFactory.createArtist(
      name: 'Outbox Failure Artist',
      now: now,
    );

    await expectLater(
      runner.run<void>((context) async {
        await context.artistRepository.create(artist);

        await context.localSyncRepository.recordUpsert(
          userId: '',
          entityType: CloudDataEntity.artist,
          entityId: artist.id,
        );

        throw StateError('Simulated outbox failure');
      }),
      throwsStateError,
    );

    final db = await appDatabase.database;

    expect(await ArtistDao(db).findById(artist.id), isNull);
    expect(await LocalSyncDao(db).findPending(''), isEmpty);
  });

  test('supports multiple cloud mutations in one transaction', () async {
    final artist = EntityFactory.createArtist(name: 'Multi Artist', now: now);

    final album = EntityFactory.createAlbum(
      artistId: artist.id,
      title: 'Multi Album',
      now: now,
    );

    await runner.run((context) async {
      await context.artistRepository.create(artist);
      await context.localSyncRepository.recordUpsert(
        userId: 'user_1',
        entityType: CloudDataEntity.artist,
        entityId: artist.id,
      );

      await context.albumRepository.create(album);
      await context.localSyncRepository.recordUpsert(
        userId: 'user_1',
        entityType: CloudDataEntity.album,
        entityId: album.id,
      );
    });

    final db = await appDatabase.database;
    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(2));
    expect(pending.map((entry) => entry.entityType).toSet(), {
      CloudDataEntity.artist,
      CloudDataEntity.album,
    });
  });
}
