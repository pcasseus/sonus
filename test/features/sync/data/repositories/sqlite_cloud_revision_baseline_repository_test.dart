import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/schema/sync_schema.dart';
import 'package:sonus_next/features/sync/data/daos/cloud_revision_baseline_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sqlite_cloud_revision_baseline_repository.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late SqliteCloudRevisionBaselineRepository repository;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SyncSchema.create(database);

    repository = SqliteCloudRevisionBaselineRepository(
      dao: CloudRevisionBaselineDao(database),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<int?> revision({
    String userId = 'user-1',
    CloudDataEntity entityType = CloudDataEntity.artist,
    String entityId = 'artist-1',
  }) {
    return repository.getRevision(
      userId: userId,
      entityType: entityType,
      entityId: entityId,
    );
  }

  Future<void> save(
    int serverRevision, {
    String userId = 'user-1',
    CloudDataEntity entityType = CloudDataEntity.artist,
    String entityId = 'artist-1',
  }) {
    return repository.saveObservedRevision(
      userId: userId,
      entityType: entityType,
      entityId: entityId,
      serverRevision: serverRevision,
    );
  }

  test('unknown cloud revision returns null', () async {
    expect(await revision(), isNull);
  });

  test('first observed revision is persisted', () async {
    await save(7);

    expect(await revision(), 7);
  });

  test('higher revisions advance the baseline', () async {
    await save(2);
    await save(5);
    await save(9);

    expect(await revision(), 9);
  });

  test('equal and older revisions never regress baseline', () async {
    await save(8);
    await save(8);
    await save(3);
    await save(1);

    expect(await revision(), 8);
  });

  test('account revisions remain isolated', () async {
    await save(4, userId: 'user-1');
    await save(12, userId: 'user-2');

    expect(await revision(userId: 'user-1'), 4);
    expect(await revision(userId: 'user-2'), 12);
    expect(await revision(userId: 'user-3'), isNull);
  });

  test('entity types and IDs remain isolated', () async {
    await save(2, entityType: CloudDataEntity.artist);
    await save(6, entityType: CloudDataEntity.album);
    await save(10, entityId: 'artist-2');

    expect(await revision(entityType: CloudDataEntity.artist), 2);
    expect(await revision(entityType: CloudDataEntity.album), 6);
    expect(await revision(entityId: 'artist-2'), 10);
  });

  test('rejects invalid server revisions', () async {
    await expectLater(save(0), throwsArgumentError);
    await expectLater(save(-1), throwsArgumentError);

    expect(await revision(), isNull);
  });

  test('rejects blank account and entity identifiers', () async {
    await expectLater(save(1, userId: '   '), throwsArgumentError);

    await expectLater(save(1, entityId: '   '), throwsArgumentError);

    await expectLater(revision(userId: '   '), throwsArgumentError);

    await expectLater(revision(entityId: '   '), throwsArgumentError);
  });

  test('revision survives creation of a new repository instance', () async {
    await save(15);

    final reopenedRepository = SqliteCloudRevisionBaselineRepository(
      dao: CloudRevisionBaselineDao(database),
    );

    expect(
      await reopenedRepository.getRevision(
        userId: 'user-1',
        entityType: CloudDataEntity.artist,
        entityId: 'artist-1',
      ),
      15,
    );
  });

  test('supports all five cloud entity types', () async {
    for (final entityType in CloudDataEntity.values) {
      await save(3, entityType: entityType, entityId: 'shared-id');

      expect(await revision(entityType: entityType, entityId: 'shared-id'), 3);
    }
  });
}
