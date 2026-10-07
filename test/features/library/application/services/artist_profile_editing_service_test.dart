import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/services/artist_profile_editing_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_artist_credit_dao.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/library/domain/entities/album.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/artist.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/entities/song_artist_credit.dart';
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

  Future<Artist> createArtist({String name = 'Original Artist'}) async {
    final created = EntityFactory.createArtist(name: name, now: originalTime);

    final db = await appDatabase.database;
    await ArtistDao(db).insert(created);

    return created;
  }

  Future<Album> createAlbumForArtist(
    Artist artist, {
    String id = 'album-1',
  }) async {
    final album = Album(
      id: id,
      artistId: artist.id,
      title: 'Test Album',
      canonicalTitle: 'test album',
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final db = await appDatabase.database;
    await AlbumDao(db).insert(album);

    return album;
  }

  Future<AlbumEdition> createEditionForAlbum(
    Album album, {
    String id = 'edition-1',
  }) async {
    final edition = AlbumEdition(
      id: id,
      albumId: album.id,
      title: 'Standard',
      type: AlbumEditionType.standard,
      isPrimary: true,
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final db = await appDatabase.database;
    await AlbumEditionDao(db).insert(edition);

    return edition;
  }

  Future<Song> createSongForArtist(
    Artist artist, {
    String songId = 'song-1',
  }) async {
    final album = await createAlbumForArtist(artist);
    final edition = await createEditionForAlbum(album);

    final song = Song(
      id: songId,
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: 'Test Song',
      canonicalTitle: 'test song',
      trackNumber: 1,
      discNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      createdAt: originalTime,
      updatedAt: originalTime,
    );

    final db = await appDatabase.database;
    await SongDao(db).insert(song);

    return song;
  }

  test('removes orphan artist and records cloud delete atomically', () async {
    final original = await createArtist();

    await service.removeArtist(userId: ' user_1 ', artistId: original.id);

    final db = await appDatabase.database;

    expect(await ArtistDao(db).findById(original.id), isNull);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.artist);
    expect(pending.single.entityId, original.id);
    expect(pending.single.operation, SyncOutboxOperation.delete);
  });

  test('rejects removal when an album still references artist', () async {
    final original = await createArtist();
    await createAlbumForArtist(original);

    await expectLater(
      service.removeArtist(userId: 'user_1', artistId: original.id),
      throwsA(isA<ArtistStillReferencedException>()),
    );

    final db = await appDatabase.database;

    expect(await ArtistDao(db).findById(original.id), isNotNull);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rejects removal when a song still references artist', () async {
    final original = await createArtist();
    await createSongForArtist(original);

    await expectLater(
      service.removeArtist(userId: 'user_1', artistId: original.id),
      throwsA(isA<ArtistStillReferencedException>()),
    );

    final db = await appDatabase.database;

    expect(await ArtistDao(db).findById(original.id), isNotNull);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('missing artist removal fails without creating outbox entry', () async {
    await expectLater(
      service.removeArtist(userId: 'user_1', artistId: 'artist_missing'),
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

  test('signed-out artist removal records unowned delete', () async {
    final original = await createArtist();

    await service.removeArtist(userId: null, artistId: original.id);

    final db = await appDatabase.database;

    expect(await ArtistDao(db).findById(original.id), isNull);

    final pending = await LocalSyncDao(db).findUnownedPending();

    expect(pending, hasLength(1));
    expect(pending.single.userId, isNull);
    expect(pending.single.entityType, CloudDataEntity.artist);
    expect(pending.single.entityId, original.id);
    expect(pending.single.operation, SyncOutboxOperation.delete);
  });

  test('rejects blank artist id before artist removal mutation', () async {
    await expectLater(
      () => service.removeArtist(userId: 'user_1', artistId: '   '),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rolls back artist removal when outbox mutation fails', () async {
    final firstArtist = await createArtist(name: 'First Artist');
    final secondArtist = await createArtist(name: 'Second Artist');

    final collisionService = ArtistProfileEditingService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'fixed_delete_outbox_id',
        now: () => mutationTime,
      ),
    );

    await collisionService.removeArtist(
      userId: 'user_1',
      artistId: firstArtist.id,
    );

    await expectLater(
      collisionService.removeArtist(
        userId: 'user_1',
        artistId: secondArtist.id,
      ),
      throwsA(isA<DatabaseException>()),
    );

    final db = await appDatabase.database;

    expect(await ArtistDao(db).findById(firstArtist.id), isNull);
    expect(await ArtistDao(db).findById(secondArtist.id), isNotNull);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityId, firstArtist.id);
    expect(pending.single.operation, SyncOutboxOperation.delete);
  });

  test('renames artist and records cloud upsert atomically', () async {
    final original = await createArtist();

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

  test('signed-out artist rename records unowned upsert', () async {
    final original = await createArtist();

    final result = await service.renameArtist(
      userId: null,
      artistId: original.id,
      name: 'Renamed Artist',
      now: mutationTime,
    );

    expect(result.id, original.id);
    expect(result.name, 'Renamed Artist');
    expect(result.updatedAt, mutationTime);

    final db = await appDatabase.database;
    final stored = await ArtistDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.name, 'Renamed Artist');
    expect(stored.updatedAt, mutationTime);

    final pending = await LocalSyncDao(db).findUnownedPending();

    expect(pending, hasLength(1));
    expect(pending.single.userId, isNull);
    expect(pending.single.entityType, CloudDataEntity.artist);
    expect(pending.single.entityId, original.id);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
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

  test(
    'artist rename records name provenance as manual user metadata',
    () async {
      final original = await createArtist();

      await service.renameArtist(
        userId: 'user_1',
        artistId: original.id,
        name: 'Renamed Artist',
        now: mutationTime,
      );

      final db = await appDatabase.database;
      final states = await MetadataFieldStateDao(db).findByEntity(
        entityType: MetadataEntityType.artist,
        entityId: original.id,
      );

      expect(states, hasLength(1));

      final state = states.single;

      expect(state.fieldName, MetadataFields.artistName);
      expect(state.authority, MetadataAuthority.manual);
      expect(state.source, MetadataProvenanceSource.user);
      expect(state.updatedAt, mutationTime);
    },
  );

  test('unchanged artist rename is a true no-op', () async {
    final original = await createArtist();

    final result = await service.renameArtist(
      userId: 'user_1',
      artistId: original.id,
      name: '  Original Artist  ',
      now: mutationTime,
    );

    expect(result.id, original.id);
    expect(result.name, original.name);
    expect(result.updatedAt, original.updatedAt);

    final db = await appDatabase.database;
    final stored = await ArtistDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.updatedAt, originalTime);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);

    expect(
      await MetadataFieldStateDao(db).findByEntity(
        entityType: MetadataEntityType.artist,
        entityId: original.id,
      ),
      isEmpty,
    );
  });

  test(
    'rejects rename when another artist already owns canonical identity',
    () async {
      final original = await createArtist(name: 'Original Artist');
      final existing = await createArtist(name: 'The Weeknd');

      await expectLater(
        () => service.renameArtist(
          userId: 'user_1',
          artistId: original.id,
          name: '  THE   WEEKND  ',
          now: mutationTime,
        ),
        throwsA(
          isA<ArtistNameCollisionException>()
              .having((error) => error.artistId, 'artistId', original.id)
              .having(
                (error) => error.conflictingArtistId,
                'conflictingArtistId',
                existing.id,
              )
              .having((error) => error.name, 'name', 'THE   WEEKND'),
        ),
      );

      final db = await appDatabase.database;
      final storedOriginal = await ArtistDao(db).findById(original.id);
      final storedExisting = await ArtistDao(db).findById(existing.id);

      expect(storedOriginal, isNotNull);
      expect(storedOriginal!.name, original.name);
      expect(storedOriginal.canonicalName, original.canonicalName);
      expect(storedOriginal.updatedAt, original.updatedAt);

      expect(storedExisting, isNotNull);
      expect(storedExisting!.name, existing.name);
      expect(storedExisting.canonicalName, existing.canonicalName);

      expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);

      expect(
        await MetadataFieldStateDao(db).findByEntity(
          entityType: MetadataEntityType.artist,
          entityId: original.id,
        ),
        isEmpty,
      );
    },
  );

  test(
    'rejects removal when structured credit still references artist',
    () async {
      final primaryArtist = await createArtist(name: 'Primary Artist');
      final creditedArtist = await createArtist(name: 'Featured Artist');

      final album = await createAlbumForArtist(primaryArtist);
      final edition = await createEditionForAlbum(album);

      final song = Song(
        id: 'structured-credit-song',
        artistId: primaryArtist.id,
        albumId: album.id,
        albumEditionId: edition.id,
        title: 'Collaboration',
        canonicalTitle: 'collaboration',
        trackNumber: 1,
        discNumber: 1,
        durationSeconds: 180,
        isSingle: false,
        createdAt: originalTime,
        updatedAt: originalTime,
      );

      final db = await appDatabase.database;
      await SongDao(db).insert(song);

      await SongArtistCreditDao(db).insert(
        SongArtistCredit(
          id: 'structured-credit-1',
          songId: song.id,
          artistId: creditedArtist.id,
          creditedName: creditedArtist.name,
          canonicalCreditedName: creditedArtist.canonicalName,
          role: SongArtistCreditRole.featured,
          position: 1,
          createdAt: originalTime,
          updatedAt: originalTime,
        ),
      );

      await expectLater(
        service.removeArtist(userId: 'user_1', artistId: creditedArtist.id),
        throwsA(isA<ArtistStillReferencedException>()),
      );

      expect(await ArtistDao(db).findById(creditedArtist.id), isNotNull);
      expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
    },
  );
  test('removing artist deletes its metadata provenance', () async {
    final original = await createArtist();

    final db = await appDatabase.database;

    await MetadataFieldStateDao(db).upsert(
      MetadataFieldState(
        entityType: MetadataEntityType.artist,
        entityId: original.id,
        fieldName: MetadataFields.artistName,
        authority: MetadataAuthority.manual,
        source: MetadataProvenanceSource.user,
        updatedAt: originalTime,
      ),
    );

    await service.removeArtist(userId: 'user_1', artistId: original.id);

    expect(
      await MetadataFieldStateDao(db).findByEntity(
        entityType: MetadataEntityType.artist,
        entityId: original.id,
      ),
      isEmpty,
    );
  });
}
