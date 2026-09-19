import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/services/artist_creation_service.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late ArtistCreationService service;

  final originalTime = DateTime.utc(2026, 9, 19, 12);
  final mutationTime = DateTime.utc(2026, 9, 19, 13);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextOutboxId = 0;

    service = ArtistCreationService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'outbox_${++nextOutboxId}',
        now: () => mutationTime,
      ),
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  Future<Artist> insertArtist(String name) async {
    final artist = EntityFactory.createArtist(name: name, now: originalTime);

    final db = await appDatabase.database;
    await ArtistDao(db).insert(artist);

    return artist;
  }

  test('creates new artist and records cloud upsert atomically', () async {
    final result = await service.createOrReuse(
      userId: ' user_1 ',
      name: '  Victoria Justice  ',
      now: mutationTime,
    );

    expect(result.name, 'Victoria Justice');
    expect(result.canonicalName, 'victoria justice');
    expect(result.createdAt, mutationTime);
    expect(result.updatedAt, mutationTime);

    final db = await appDatabase.database;
    final stored = await ArtistDao(db).findById(result.id);

    expect(stored, isNotNull);
    expect(stored!.id, result.id);
    expect(stored.name, 'Victoria Justice');
    expect(stored.canonicalName, 'victoria justice');

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.artist);
    expect(pending.single.entityId, result.id);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test(
    'reuses unique canonical match without creating duplicate or outbox',
    () async {
      final existing = await insertArtist('Victoria   Justice');

      final result = await service.createOrReuse(
        userId: 'user_1',
        name: '  victoria justice  ',
        now: mutationTime,
      );

      expect(result.id, existing.id);
      expect(result.name, existing.name);
      expect(result.createdAt, existing.createdAt);
      expect(result.updatedAt, existing.updatedAt);

      final db = await appDatabase.database;
      final artists = await ArtistDao(db).findAll();

      expect(artists, hasLength(1));
      expect(artists.single.id, existing.id);
      expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
    },
  );

  test(
    'rejects ambiguous canonical match without creating artist or outbox',
    () async {
      final first = await insertArtist('Victoria Justice');

      final second = EntityFactory.createArtist(
        name: 'Victoria   Justice',
        now: originalTime.add(const Duration(minutes: 1)),
      );

      final db = await appDatabase.database;
      await ArtistDao(db).insert(second);

      await expectLater(
        service.createOrReuse(
          userId: 'user_1',
          name: 'victoria justice',
          now: mutationTime,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('matches multiple existing artists'),
          ),
        ),
      );

      final artists = await ArtistDao(db).findAll();

      expect(artists, hasLength(2));
      expect(
        artists.map((artist) => artist.id),
        containsAll(<String>[first.id, second.id]),
      );
      expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
    },
  );

  test('rejects blank artist name before mutation', () async {
    await expectLater(
      () => service.createOrReuse(
        userId: 'user_1',
        name: '   ',
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;

    expect(await ArtistDao(db).findAll(), isEmpty);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rolls back new artist when outbox mutation fails', () async {
    final collisionService = ArtistCreationService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'fixed_outbox_id',
        now: () => mutationTime,
      ),
    );

    final first = await collisionService.createOrReuse(
      userId: 'user_1',
      name: 'First Artist',
      now: mutationTime,
    );

    await expectLater(
      collisionService.createOrReuse(
        userId: 'user_1',
        name: 'Second Artist',
        now: mutationTime.add(const Duration(minutes: 1)),
      ),
      throwsA(isA<DatabaseException>()),
    );

    final db = await appDatabase.database;
    final artists = await ArtistDao(db).findAll();

    expect(artists, hasLength(1));
    expect(artists.single.id, first.id);
    expect(artists.single.name, 'First Artist');

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.artist);
    expect(pending.single.entityId, first.id);
  });
}
