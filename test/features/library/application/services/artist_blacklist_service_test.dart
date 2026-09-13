import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/services/artist_blacklist_service.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late ArtistBlacklistService service;

  final originalTime = DateTime.utc(2026, 9, 13, 12);
  final mutationTime = DateTime.utc(2026, 9, 13, 13);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextOutboxId = 0;

    service = ArtistBlacklistService(
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

  Future<String> createArtist() async {
    final artist = EntityFactory.createArtist(
      name: 'Blacklist Artist',
      now: originalTime,
    );

    final db = await appDatabase.database;
    await ArtistDao(db).insert(artist);

    return artist.id;
  }

  test('blacklists artist and records cloud upsert atomically', () async {
    final artistId = await createArtist();

    final result = await service.setBlacklisted(
      userId: ' user_1 ',
      artistId: artistId,
      isBlacklisted: true,
      now: mutationTime,
    );

    expect(result.id, artistId);
    expect(result.isBlacklisted, isTrue);
    expect(result.updatedAt, mutationTime);

    final db = await appDatabase.database;
    final stored = await ArtistDao(db).findById(artistId);

    expect(stored, isNotNull);
    expect(stored!.isBlacklisted, isTrue);
    expect(stored.updatedAt, mutationTime);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.artist);
    expect(pending.single.entityId, artistId);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test('unblacklists artist and keeps the same permanent identity', () async {
    final artistId = await createArtist();

    await service.setBlacklisted(
      userId: 'user_1',
      artistId: artistId,
      isBlacklisted: true,
      now: mutationTime,
    );

    final unblacklistTime = mutationTime.add(const Duration(minutes: 1));

    final result = await service.setBlacklisted(
      userId: 'user_1',
      artistId: artistId,
      isBlacklisted: false,
      now: unblacklistTime,
    );

    expect(result.id, artistId);
    expect(result.isBlacklisted, isFalse);
    expect(result.updatedAt, unblacklistTime);

    final db = await appDatabase.database;
    final stored = await ArtistDao(db).findById(artistId);

    expect(stored, isNotNull);
    expect(stored!.id, artistId);
    expect(stored.isBlacklisted, isFalse);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityId, artistId);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test('missing artist fails without creating an outbox entry', () async {
    await expectLater(
      service.setBlacklisted(
        userId: 'user_1',
        artistId: 'artist_missing',
        isBlacklisted: true,
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
    final artistId = await createArtist();

    await expectLater(
      () => service.setBlacklisted(
        userId: '   ',
        artistId: artistId,
        isBlacklisted: true,
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;
    final stored = await ArtistDao(db).findById(artistId);

    expect(stored, isNotNull);
    expect(stored!.isBlacklisted, isFalse);
    expect(await LocalSyncDao(db).findPending(''), isEmpty);
  });

  test('rejects blank artist id before mutation', () async {
    await expectLater(
      () => service.setBlacklisted(
        userId: 'user_1',
        artistId: '   ',
        isBlacklisted: true,
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });
}
