import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/services/artist_profile_editing_service.dart';
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
  late ArtistProfileEditingService service;

  final originalTime = DateTime.utc(2026, 9, 13, 12);
  final mutationTime = DateTime.utc(2026, 9, 13, 13);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextOutboxId = 0;

    service = ArtistProfileEditingService(
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

  Future<Artist> createArtist({
    String name = 'Original Artist',
    bool isBlacklisted = false,
  }) async {
    final created = EntityFactory.createArtist(
      name: name,
      now: originalTime,
    ).copyWith(isBlacklisted: isBlacklisted);

    final db = await appDatabase.database;
    await ArtistDao(db).insert(created);

    return created;
  }

  test('renames artist and records cloud upsert atomically', () async {
    final original = await createArtist(isBlacklisted: true);

    final result = await service.renameArtist(
      userId: ' user_1 ',
      artistId: original.id,
      name: '  Renamed Artist  ',
      now: mutationTime,
    );

    expect(result.id, original.id);
    expect(result.name, 'Renamed Artist');
    expect(result.canonicalName, 'renamed artist');
    expect(result.createdAt, originalTime);
    expect(result.updatedAt, mutationTime);

    expect(result.isBlacklisted, isTrue);
    expect(result.headerArtworkId, isNull);
    expect(result.topArtistsArtworkId, isNull);

    final db = await appDatabase.database;
    final stored = await ArtistDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.id, original.id);
    expect(stored.name, 'Renamed Artist');
    expect(stored.canonicalName, 'renamed artist');
    expect(stored.createdAt, originalTime);
    expect(stored.updatedAt, mutationTime);
    expect(stored.isBlacklisted, isTrue);
    expect(stored.headerArtworkId, isNull);
    expect(stored.topArtistsArtworkId, isNull);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.artist);
    expect(pending.single.entityId, original.id);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test(
    'canonicalizes renamed artist independently from display name',
    () async {
      final original = await createArtist();

      final result = await service.renameArtist(
        userId: 'user_1',
        artistId: original.id,
        name: '  The   Weeknd  ',
        now: mutationTime,
      );

      expect(result.name, 'The   Weeknd');
      expect(result.canonicalName, 'the weeknd');

      final db = await appDatabase.database;
      final stored = await ArtistDao(db).findById(original.id);

      expect(stored, isNotNull);
      expect(stored!.name, 'The   Weeknd');
      expect(stored.canonicalName, 'the weeknd');
    },
  );

  test(
    'repeated rename keeps permanent identity and coalesces outbox',
    () async {
      final original = await createArtist();

      await service.renameArtist(
        userId: 'user_1',
        artistId: original.id,
        name: 'First Rename',
        now: mutationTime,
      );

      final secondMutationTime = mutationTime.add(const Duration(minutes: 1));

      final result = await service.renameArtist(
        userId: 'user_1',
        artistId: original.id,
        name: 'Second Rename',
        now: secondMutationTime,
      );

      expect(result.id, original.id);
      expect(result.name, 'Second Rename');
      expect(result.updatedAt, secondMutationTime);

      final db = await appDatabase.database;
      final pending = await LocalSyncDao(db).findPending('user_1');

      expect(pending, hasLength(1));
      expect(pending.single.entityId, original.id);
      expect(pending.single.operation, SyncOutboxOperation.upsert);
    },
  );

  test('missing artist fails without creating an outbox entry', () async {
    await expectLater(
      service.renameArtist(
        userId: 'user_1',
        artistId: 'artist_missing',
        name: 'Renamed Artist',
        now: mutationTime,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Artist not found: artist_missing',
        ),
      ),
    );

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rejects blank user id before mutation', () async {
    final original = await createArtist();

    await expectLater(
      () => service.renameArtist(
        userId: '   ',
        artistId: original.id,
        name: 'Renamed Artist',
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;
    final stored = await ArtistDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.name, original.name);
    expect(stored.updatedAt, original.updatedAt);
    expect(await LocalSyncDao(db).findPending(''), isEmpty);
  });

  test('rejects blank artist id before mutation', () async {
    await expectLater(
      () => service.renameArtist(
        userId: 'user_1',
        artistId: '   ',
        name: 'Renamed Artist',
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rejects blank artist name without changing stored artist', () async {
    final original = await createArtist();

    await expectLater(
      () => service.renameArtist(
        userId: 'user_1',
        artistId: original.id,
        name: '   ',
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;
    final stored = await ArtistDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.name, original.name);
    expect(stored.canonicalName, original.canonicalName);
    expect(stored.updatedAt, original.updatedAt);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rolls back artist rename when outbox mutation fails', () async {
    final firstArtist = await createArtist(name: 'First Artist');
    final secondArtist = await createArtist(name: 'Second Artist');

    final collisionService = ArtistProfileEditingService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'fixed_outbox_id',
        now: () => mutationTime,
      ),
    );

    await collisionService.renameArtist(
      userId: 'user_1',
      artistId: firstArtist.id,
      name: 'First Artist Renamed',
      now: mutationTime,
    );

    await expectLater(
      collisionService.renameArtist(
        userId: 'user_1',
        artistId: secondArtist.id,
        name: 'Second Artist Renamed',
        now: mutationTime,
      ),
      throwsA(isA<DatabaseException>()),
    );

    final db = await appDatabase.database;

    final storedFirst = await ArtistDao(db).findById(firstArtist.id);
    final storedSecond = await ArtistDao(db).findById(secondArtist.id);

    expect(storedFirst, isNotNull);
    expect(storedFirst!.name, 'First Artist Renamed');

    expect(storedSecond, isNotNull);
    expect(storedSecond!.name, 'Second Artist');
    expect(storedSecond.updatedAt, originalTime);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityId, firstArtist.id);
  });
}
