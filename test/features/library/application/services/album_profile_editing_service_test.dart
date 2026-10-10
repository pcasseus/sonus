import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/services/album_profile_editing_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late AlbumProfileEditingService service;

  final originalTime = DateTime.utc(2026, 9, 14, 10);
  final mutationTime = DateTime.utc(2026, 9, 14, 11);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextOutboxId = 0;

    service = AlbumProfileEditingService(
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

  Future<({Album album, AlbumEdition edition})> createProfile({
    String albumTitle = 'Original Album',
    String editionTitle = 'Standard',
    AlbumEditionType editionType = AlbumEditionType.standard,
    bool isPrimary = true,
    DateTime? releaseDate,
    String? genre,
  }) async {
    final artist = EntityFactory.createArtist(
      name: 'Test Artist',
      now: originalTime,
    );

    final album = EntityFactory.createAlbum(
      artistId: artist.id,
      title: albumTitle,
      now: originalTime,
    );

    final edition = EntityFactory.createAlbumEdition(
      albumId: album.id,
      title: editionTitle,
      type: editionType,
      isPrimary: isPrimary,
      releaseDate: releaseDate,
      genre: genre,
      now: originalTime,
    );

    final db = await appDatabase.database;

    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(album);
    await AlbumEditionDao(db).insert(edition);

    return (album: album, edition: edition);
  }

  test('updates album and primary edition atomically', () async {
    final original = await createProfile(
      releaseDate: DateTime.utc(2024, 1, 5),
      genre: 'Pop',
    );

    final newReleaseDate = DateTime.utc(2025, 6, 20);

    final result = await service.updateProfile(
      userId: ' user_1 ',
      albumId: original.album.id,
      primaryEditionId: original.edition.id,
      title: '  Renamed Album  ',
      editionTitle: '  Deluxe Edition  ',
      editionType: AlbumEditionType.deluxe,
      releaseDate: newReleaseDate,
      genre: '  Alternative  ',
      now: mutationTime,
    );

    expect(result.changed, isTrue);
    expect(result.albumChanged, isTrue);
    expect(result.primaryEditionChanged, isTrue);

    expect(result.album.id, original.album.id);
    expect(result.album.artistId, original.album.artistId);
    expect(result.album.title, 'Renamed Album');
    expect(result.album.canonicalTitle, 'renamed album');
    expect(result.album.createdAt, originalTime);
    expect(result.album.updatedAt, mutationTime);

    expect(result.primaryEdition.id, original.edition.id);
    expect(result.primaryEdition.albumId, original.album.id);
    expect(result.primaryEdition.title, 'Deluxe Edition');
    expect(result.primaryEdition.type, AlbumEditionType.deluxe);
    expect(result.primaryEdition.isPrimary, isTrue);
    expect(result.primaryEdition.releaseDate, newReleaseDate);
    expect(result.primaryEdition.genre, 'Alternative');
    expect(result.primaryEdition.artworkId, original.edition.artworkId);
    expect(result.primaryEdition.createdAt, originalTime);
    expect(result.primaryEdition.updatedAt, mutationTime);

    final db = await appDatabase.database;

    final storedAlbum = await AlbumDao(db).findById(original.album.id);
    final storedEdition = await AlbumEditionDao(
      db,
    ).findById(original.edition.id);

    expect(storedAlbum, isNotNull);
    expect(storedAlbum!.title, 'Renamed Album');
    expect(storedAlbum.canonicalTitle, 'renamed album');
    expect(storedAlbum.artistId, original.album.artistId);
    expect(storedAlbum.createdAt, originalTime);
    expect(storedAlbum.updatedAt, mutationTime);

    expect(storedEdition, isNotNull);
    expect(storedEdition!.title, 'Deluxe Edition');
    expect(storedEdition.type, AlbumEditionType.deluxe);
    expect(storedEdition.isPrimary, isTrue);
    expect(storedEdition.releaseDate, newReleaseDate);
    expect(storedEdition.genre, 'Alternative');
    expect(storedEdition.artworkId, original.edition.artworkId);
    expect(storedEdition.createdAt, originalTime);
    expect(storedEdition.updatedAt, mutationTime);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(2));

    expect(
      pending.any(
        (entry) =>
            entry.entityType == CloudDataEntity.album &&
            entry.entityId == original.album.id &&
            entry.operation == SyncOutboxOperation.upsert,
      ),
      isTrue,
    );

    expect(
      pending.any(
        (entry) =>
            entry.entityType == CloudDataEntity.albumEdition &&
            entry.entityId == original.edition.id &&
            entry.operation == SyncOutboxOperation.upsert,
      ),
      isTrue,
    );
  });

  test('album-only edit updates only album and album outbox', () async {
    final original = await createProfile(
      releaseDate: DateTime.utc(2024, 1, 5),
      genre: 'Pop',
    );

    final result = await service.updateProfile(
      userId: 'user_1',
      albumId: original.album.id,
      primaryEditionId: original.edition.id,
      title: 'Changed Album',
      editionTitle: original.edition.title,
      editionType: original.edition.type,
      releaseDate: original.edition.releaseDate,
      genre: original.edition.genre,
      now: mutationTime,
    );

    expect(result.changed, isTrue);
    expect(result.albumChanged, isTrue);
    expect(result.primaryEditionChanged, isFalse);

    expect(result.album.updatedAt, mutationTime);
    expect(result.primaryEdition.updatedAt, originalTime);

    final db = await appDatabase.database;

    final storedEdition = await AlbumEditionDao(
      db,
    ).findById(original.edition.id);

    expect(storedEdition, isNotNull);
    expect(storedEdition!.updatedAt, originalTime);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.album);
    expect(pending.single.entityId, original.album.id);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test('edition-only edit updates only edition and edition outbox', () async {
    final original = await createProfile(
      releaseDate: DateTime.utc(2024, 1, 5),
      genre: 'Pop',
    );

    final result = await service.updateProfile(
      userId: 'user_1',
      albumId: original.album.id,
      primaryEditionId: original.edition.id,
      title: original.album.title,
      editionTitle: 'Expanded',
      editionType: AlbumEditionType.expanded,
      releaseDate: DateTime.utc(2024, 2, 1),
      genre: 'Rock',
      now: mutationTime,
    );

    expect(result.changed, isTrue);
    expect(result.albumChanged, isFalse);
    expect(result.primaryEditionChanged, isTrue);

    expect(result.album.updatedAt, originalTime);
    expect(result.primaryEdition.updatedAt, mutationTime);

    final db = await appDatabase.database;

    final storedAlbum = await AlbumDao(db).findById(original.album.id);

    expect(storedAlbum, isNotNull);
    expect(storedAlbum!.updatedAt, originalTime);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.albumEdition);
    expect(pending.single.entityId, original.edition.id);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test('canonicalizes album title independently from display title', () async {
    final original = await createProfile();

    final result = await service.updateProfile(
      userId: 'user_1',
      albumId: original.album.id,
      primaryEditionId: original.edition.id,
      title: '  The   Album  ',
      editionTitle: original.edition.title,
      editionType: original.edition.type,
      releaseDate: original.edition.releaseDate,
      genre: original.edition.genre,
      now: mutationTime,
    );

    expect(result.album.title, 'The   Album');
    expect(result.album.canonicalTitle, 'the album');

    final db = await appDatabase.database;
    final storedAlbum = await AlbumDao(db).findById(original.album.id);

    expect(storedAlbum, isNotNull);
    expect(storedAlbum!.title, 'The   Album');
    expect(storedAlbum.canonicalTitle, 'the album');
  });

  test('clears nullable primary-edition metadata', () async {
    final original = await createProfile(
      releaseDate: DateTime.utc(2024, 1, 5),
      genre: 'Pop',
    );

    final result = await service.updateProfile(
      userId: 'user_1',
      albumId: original.album.id,
      primaryEditionId: original.edition.id,
      title: original.album.title,
      editionTitle: original.edition.title,
      editionType: original.edition.type,
      releaseDate: null,
      genre: '   ',
      now: mutationTime,
    );

    expect(result.albumChanged, isFalse);
    expect(result.primaryEditionChanged, isTrue);
    expect(result.primaryEdition.releaseDate, isNull);
    expect(result.primaryEdition.genre, isNull);

    final db = await appDatabase.database;

    final storedEdition = await AlbumEditionDao(
      db,
    ).findById(original.edition.id);

    expect(storedEdition, isNotNull);
    expect(storedEdition!.releaseDate, isNull);
    expect(storedEdition.genre, isNull);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.albumEdition);
  });

  test('no-op update does not change timestamps or create outbox', () async {
    final original = await createProfile(
      releaseDate: DateTime.utc(2024, 1, 5),
      genre: 'Pop',
    );

    final result = await service.updateProfile(
      userId: 'user_1',
      albumId: original.album.id,
      primaryEditionId: original.edition.id,
      title: '  ${original.album.title}  ',
      editionTitle: '  ${original.edition.title}  ',
      editionType: original.edition.type,
      releaseDate: original.edition.releaseDate,
      genre: '  ${original.edition.genre}  ',
      now: mutationTime,
    );

    expect(result.changed, isFalse);
    expect(result.albumChanged, isFalse);
    expect(result.primaryEditionChanged, isFalse);
    expect(result.album.updatedAt, originalTime);
    expect(result.primaryEdition.updatedAt, originalTime);

    final db = await appDatabase.database;

    final storedAlbum = await AlbumDao(db).findById(original.album.id);
    final storedEdition = await AlbumEditionDao(
      db,
    ).findById(original.edition.id);

    expect(storedAlbum!.updatedAt, originalTime);
    expect(storedEdition!.updatedAt, originalTime);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('missing album fails without creating outbox entry', () async {
    final original = await createProfile();

    await expectLater(
      service.updateProfile(
        userId: 'user_1',
        albumId: 'album_missing',
        primaryEditionId: original.edition.id,
        title: 'Changed Album',
        editionTitle: original.edition.title,
        editionType: original.edition.type,
        releaseDate: original.edition.releaseDate,
        genre: original.edition.genre,
        now: mutationTime,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Album not found: album_missing',
        ),
      ),
    );

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('missing primary edition fails without changing album', () async {
    final original = await createProfile();

    await expectLater(
      service.updateProfile(
        userId: 'user_1',
        albumId: original.album.id,
        primaryEditionId: 'edition_missing',
        title: 'Changed Album',
        editionTitle: 'Deluxe',
        editionType: AlbumEditionType.deluxe,
        releaseDate: null,
        genre: null,
        now: mutationTime,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Album edition not found: edition_missing',
        ),
      ),
    );

    final db = await appDatabase.database;
    final storedAlbum = await AlbumDao(db).findById(original.album.id);

    expect(storedAlbum, isNotNull);
    expect(storedAlbum!.title, original.album.title);
    expect(storedAlbum.updatedAt, originalTime);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rejects edition belonging to another album', () async {
    final first = await createProfile(albumTitle: 'First Album');

    final artist = EntityFactory.createArtist(
      name: 'Second Artist',
      now: originalTime,
    );

    final secondAlbum = EntityFactory.createAlbum(
      artistId: artist.id,
      title: 'Second Album',
      now: originalTime,
    );

    final secondEdition = EntityFactory.createAlbumEdition(
      albumId: secondAlbum.id,
      title: 'Standard',
      isPrimary: true,
      now: originalTime,
    );

    final db = await appDatabase.database;

    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(secondAlbum);
    await AlbumEditionDao(db).insert(secondEdition);

    await expectLater(
      service.updateProfile(
        userId: 'user_1',
        albumId: first.album.id,
        primaryEditionId: secondEdition.id,
        title: 'Changed Album',
        editionTitle: secondEdition.title,
        editionType: secondEdition.type,
        releaseDate: secondEdition.releaseDate,
        genre: secondEdition.genre,
        now: mutationTime,
      ),
      throwsA(isA<StateError>()),
    );

    final storedFirst = await AlbumDao(db).findById(first.album.id);

    expect(storedFirst, isNotNull);
    expect(storedFirst!.title, first.album.title);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rejects non-primary edition', () async {
    final original = await createProfile(isPrimary: false);

    await expectLater(
      service.updateProfile(
        userId: 'user_1',
        albumId: original.album.id,
        primaryEditionId: original.edition.id,
        title: 'Changed Album',
        editionTitle: original.edition.title,
        editionType: original.edition.type,
        releaseDate: original.edition.releaseDate,
        genre: original.edition.genre,
        now: mutationTime,
      ),
      throwsA(isA<StateError>()),
    );

    final db = await appDatabase.database;

    final storedAlbum = await AlbumDao(db).findById(original.album.id);

    expect(storedAlbum, isNotNull);
    expect(storedAlbum!.title, original.album.title);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('signed-out album edit records unowned upsert', () async {
    final original = await createProfile();

    final result = await service.updateProfile(
      userId: null,
      albumId: original.album.id,
      primaryEditionId: original.edition.id,
      title: 'Changed Album',
      editionTitle: original.edition.title,
      editionType: original.edition.type,
      releaseDate: original.edition.releaseDate,
      genre: original.edition.genre,
      now: mutationTime,
    );

    expect(result.changed, isTrue);
    expect(result.albumChanged, isTrue);
    expect(result.primaryEditionChanged, isFalse);

    final db = await appDatabase.database;
    final stored = await AlbumDao(db).findById(original.album.id);

    expect(stored, isNotNull);
    expect(stored!.title, 'Changed Album');
    expect(stored.updatedAt, mutationTime);

    final pending = await LocalSyncDao(db).findUnownedPending();

    expect(pending, hasLength(1));
    expect(pending.single.userId, isNull);
    expect(pending.single.entityType, CloudDataEntity.album);
    expect(pending.single.entityId, original.album.id);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test('rejects blank album id before mutation', () async {
    final original = await createProfile();

    await expectLater(
      () => service.updateProfile(
        userId: 'user_1',
        albumId: '   ',
        primaryEditionId: original.edition.id,
        title: 'Changed Album',
        editionTitle: original.edition.title,
        editionType: original.edition.type,
        releaseDate: original.edition.releaseDate,
        genre: original.edition.genre,
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rejects blank primary edition id before mutation', () async {
    final original = await createProfile();

    await expectLater(
      () => service.updateProfile(
        userId: 'user_1',
        albumId: original.album.id,
        primaryEditionId: '   ',
        title: 'Changed Album',
        editionTitle: original.edition.title,
        editionType: original.edition.type,
        releaseDate: original.edition.releaseDate,
        genre: original.edition.genre,
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rejects blank album title without changing stored profile', () async {
    final original = await createProfile();

    await expectLater(
      () => service.updateProfile(
        userId: 'user_1',
        albumId: original.album.id,
        primaryEditionId: original.edition.id,
        title: '   ',
        editionTitle: original.edition.title,
        editionType: original.edition.type,
        releaseDate: original.edition.releaseDate,
        genre: original.edition.genre,
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;

    final storedAlbum = await AlbumDao(db).findById(original.album.id);
    final storedEdition = await AlbumEditionDao(
      db,
    ).findById(original.edition.id);

    expect(storedAlbum!.title, original.album.title);
    expect(storedEdition!.title, original.edition.title);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rejects blank edition title without changing stored profile', () async {
    final original = await createProfile();

    await expectLater(
      () => service.updateProfile(
        userId: 'user_1',
        albumId: original.album.id,
        primaryEditionId: original.edition.id,
        title: original.album.title,
        editionTitle: '   ',
        editionType: original.edition.type,
        releaseDate: original.edition.releaseDate,
        genre: original.edition.genre,
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;

    final storedAlbum = await AlbumDao(db).findById(original.album.id);
    final storedEdition = await AlbumEditionDao(
      db,
    ).findById(original.edition.id);

    expect(storedAlbum!.title, original.album.title);
    expect(storedEdition!.title, original.edition.title);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test(
    'rolls back both entity updates when second outbox write fails',
    () async {
      final original = await createProfile(
        releaseDate: DateTime.utc(2024, 1, 5),
        genre: 'Pop',
      );

      final collisionService = AlbumProfileEditingService(
        mutationRunner: SyncMutationTransactionRunner(
          appDatabase: appDatabase,
          generateId: () => 'fixed_outbox_id',
          now: () => mutationTime,
        ),
      );

      await expectLater(
        collisionService.updateProfile(
          userId: 'user_1',
          albumId: original.album.id,
          primaryEditionId: original.edition.id,
          title: 'Changed Album',
          editionTitle: 'Deluxe',
          editionType: AlbumEditionType.deluxe,
          releaseDate: DateTime.utc(2025, 1, 1),
          genre: 'Rock',
          now: mutationTime,
        ),
        throwsA(isA<DatabaseException>()),
      );

      final db = await appDatabase.database;

      final storedAlbum = await AlbumDao(db).findById(original.album.id);
      final storedEdition = await AlbumEditionDao(
        db,
      ).findById(original.edition.id);

      expect(storedAlbum, isNotNull);
      expect(storedAlbum!.title, original.album.title);
      expect(storedAlbum.canonicalTitle, original.album.canonicalTitle);
      expect(storedAlbum.updatedAt, originalTime);

      expect(storedEdition, isNotNull);
      expect(storedEdition!.title, original.edition.title);
      expect(storedEdition.type, original.edition.type);
      expect(storedEdition.releaseDate, original.edition.releaseDate);
      expect(storedEdition.genre, original.edition.genre);
      expect(storedEdition.updatedAt, originalTime);

      expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
    },
  );

  test('album-only edit records only album provenance', () async {
    final original = await createProfile();

    await service.updateProfile(
      userId: 'user_1',
      albumId: original.album.id,
      primaryEditionId: original.edition.id,
      title: 'Renamed Album',
      editionTitle: original.edition.title,
      editionType: original.edition.type,
      releaseDate: original.edition.releaseDate,
      genre: original.edition.genre,
      now: mutationTime,
    );

    final db = await appDatabase.database;

    final albumStates = await MetadataFieldStateDao(db).findByEntity(
      entityType: MetadataEntityType.album,
      entityId: original.album.id,
    );

    final editionStates = await MetadataFieldStateDao(db).findByEntity(
      entityType: MetadataEntityType.albumEdition,
      entityId: original.edition.id,
    );

    expect(albumStates, hasLength(1));
    expect(albumStates.single.fieldName, MetadataFields.albumTitle);
    expect(albumStates.single.authority, MetadataAuthority.manual);
    expect(albumStates.single.source, MetadataProvenanceSource.user);
    expect(albumStates.single.updatedAt, mutationTime);

    expect(editionStates, isEmpty);
  });

  test('edition-only edit records only edition provenance', () async {
    final original = await createProfile(
      releaseDate: DateTime.utc(2024, 1, 5),
      genre: 'Pop',
    );

    final newReleaseDate = DateTime.utc(2025, 6, 20);

    await service.updateProfile(
      userId: 'user_1',
      albumId: original.album.id,
      primaryEditionId: original.edition.id,
      title: original.album.title,
      editionTitle: 'Deluxe Edition',
      editionType: AlbumEditionType.deluxe,
      releaseDate: newReleaseDate,
      genre: 'Alternative',
      now: mutationTime,
    );

    final db = await appDatabase.database;

    final albumStates = await MetadataFieldStateDao(db).findByEntity(
      entityType: MetadataEntityType.album,
      entityId: original.album.id,
    );

    final editionStates = await MetadataFieldStateDao(db).findByEntity(
      entityType: MetadataEntityType.albumEdition,
      entityId: original.edition.id,
    );

    expect(albumStates, isEmpty);

    expect(editionStates.map((state) => state.fieldName).toSet(), {
      MetadataFields.editionTitle,
      MetadataFields.editionType,
      MetadataFields.editionReleaseDate,
      MetadataFields.editionGenre,
    });

    expect(
      editionStates.every(
        (state) => state.authority == MetadataAuthority.manual,
      ),
      isTrue,
    );

    expect(
      editionStates.every(
        (state) => state.source == MetadataProvenanceSource.user,
      ),
      isTrue,
    );
  });

  test('clearing nullable edition metadata records those fields', () async {
    final original = await createProfile(
      releaseDate: DateTime.utc(2024, 1, 5),
      genre: 'Pop',
    );

    await service.updateProfile(
      userId: 'user_1',
      albumId: original.album.id,
      primaryEditionId: original.edition.id,
      title: original.album.title,
      editionTitle: original.edition.title,
      editionType: original.edition.type,
      releaseDate: null,
      genre: null,
      now: mutationTime,
    );

    final db = await appDatabase.database;

    final states = await MetadataFieldStateDao(db).findByEntity(
      entityType: MetadataEntityType.albumEdition,
      entityId: original.edition.id,
    );

    expect(states.map((state) => state.fieldName).toSet(), {
      MetadataFields.editionReleaseDate,
      MetadataFields.editionGenre,
    });

    expect(
      states.every((state) => state.authority == MetadataAuthority.manual),
      isTrue,
    );

    expect(
      states.every((state) => state.source == MetadataProvenanceSource.user),
      isTrue,
    );
  });

  test('no-op album update records no metadata provenance', () async {
    final original = await createProfile(
      releaseDate: DateTime.utc(2024, 1, 5),
      genre: 'Pop',
    );

    final result = await service.updateProfile(
      userId: 'user_1',
      albumId: original.album.id,
      primaryEditionId: original.edition.id,
      title: original.album.title,
      editionTitle: original.edition.title,
      editionType: original.edition.type,
      releaseDate: original.edition.releaseDate,
      genre: original.edition.genre,
      now: mutationTime,
    );

    expect(result.changed, isFalse);

    final db = await appDatabase.database;

    expect(
      await MetadataFieldStateDao(db).findByEntity(
        entityType: MetadataEntityType.album,
        entityId: original.album.id,
      ),
      isEmpty,
    );

    expect(
      await MetadataFieldStateDao(db).findByEntity(
        entityType: MetadataEntityType.albumEdition,
        entityId: original.edition.id,
      ),
      isEmpty,
    );
  });
}
