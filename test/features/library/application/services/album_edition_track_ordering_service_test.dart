import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/services/album_edition_track_ordering_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late AlbumEditionTrackOrderingService service;

  final originalTime = DateTime.utc(2026, 10, 2, 12);
  final mutationTime = DateTime.utc(2026, 10, 2, 13);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextOutboxId = 0;

    service = AlbumEditionTrackOrderingService(
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

  Future<_Fixture> createFixture() async {
    final artist = EntityFactory.createArtist(
      name: 'Test Artist',
      now: originalTime,
    );

    final album = EntityFactory.createAlbum(
      artistId: artist.id,
      title: 'Test Album',
      now: originalTime,
    );

    final standardEdition = EntityFactory.createAlbumEdition(
      albumId: album.id,
      title: 'Standard',
      isPrimary: true,
      now: originalTime,
    );

    final deluxeEdition = EntityFactory.createAlbumEdition(
      albumId: album.id,
      title: 'Deluxe',
      type: AlbumEditionType.deluxe,
      isPrimary: false,
      now: originalTime,
    );

    final songA = EntityFactory.createSong(
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: standardEdition.id,
      title: 'Song A',
      trackNumber: 1,
      durationSeconds: 180,
      isSingle: false,
      now: originalTime,
    );

    final songB = EntityFactory.createSong(
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: standardEdition.id,
      title: 'Song B',
      trackNumber: 2,
      durationSeconds: 190,
      isSingle: false,
      now: originalTime,
    );

    final songC = EntityFactory.createSong(
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: standardEdition.id,
      title: 'Song C',
      trackNumber: 3,
      durationSeconds: 200,
      isSingle: false,
      now: originalTime,
    );

    final db = await appDatabase.database;

    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(album);

    await AlbumEditionDao(db).insert(standardEdition);
    await AlbumEditionDao(db).insert(deluxeEdition);

    for (final song in [songA, songB, songC]) {
      await SongDao(db).insert(song);
    }

    final membershipDao = AlbumEditionTrackDao(db);

    await membershipDao.insert(
      AlbumEditionTrack(
        albumEditionId: standardEdition.id,
        songId: songA.id,
        discNumber: 1,
        trackNumber: 1,
        sortPosition: 0,
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    await membershipDao.insert(
      AlbumEditionTrack(
        albumEditionId: standardEdition.id,
        songId: songB.id,
        discNumber: 1,
        trackNumber: 2,
        sortPosition: 1,
        numberingAuthority: AlbumEditionTrackAuthority.manual,
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    await membershipDao.insert(
      AlbumEditionTrack(
        albumEditionId: standardEdition.id,
        songId: songC.id,
        discNumber: 1,
        trackNumber: 3,
        sortPosition: 2,
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    // Song A also belongs to Deluxe with independent placement.
    await membershipDao.insert(
      AlbumEditionTrack(
        albumEditionId: deluxeEdition.id,
        songId: songA.id,
        discNumber: 2,
        trackNumber: 5,
        sortPosition: 7,
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    return _Fixture(
      standardEdition: standardEdition,
      deluxeEdition: deluxeEdition,
      songA: songA,
      songB: songB,
      songC: songC,
    );
  }

  test('reorders one edition and marks ordering authority manual', () async {
    final fixture = await createFixture();

    final result = await service.reorderEdition(
      albumEditionId: fixture.standardEdition.id,
      orderedSongIds: [fixture.songC.id, fixture.songA.id, fixture.songB.id],
      now: mutationTime,
    );

    expect(result.changed, isTrue);

    final db = await appDatabase.database;

    final standard = await AlbumEditionTrackDao(
      db,
    ).findByEditionId(fixture.standardEdition.id);

    expect(standard.map((membership) => membership.songId), [
      fixture.songC.id,
      fixture.songA.id,
      fixture.songB.id,
    ]);

    expect(standard.map((membership) => membership.sortPosition), [0, 1, 2]);

    for (final membership in standard) {
      expect(membership.orderingAuthority, AlbumEditionTrackAuthority.manual);
    }

    // Reordering must not alter numbering authority.
    final songBMembership = standard.singleWhere(
      (membership) => membership.songId == fixture.songB.id,
    );

    expect(
      songBMembership.numberingAuthority,
      AlbumEditionTrackAuthority.manual,
    );

    final songAMembership = standard.singleWhere(
      (membership) => membership.songId == fixture.songA.id,
    );

    expect(songAMembership.discNumber, 1);
    expect(songAMembership.trackNumber, 1);

    // Shared Deluxe placement remains isolated.
    final deluxe = await AlbumEditionTrackDao(
      db,
    ).findByEditionId(fixture.deluxeEdition.id);

    expect(deluxe, hasLength(1));
    expect(deluxe.single.songId, fixture.songA.id);
    expect(deluxe.single.discNumber, 2);
    expect(deluxe.single.trackNumber, 5);
    expect(deluxe.single.sortPosition, 7);
    expect(
      deluxe.single.orderingAuthority,
      AlbumEditionTrackAuthority.inferred,
    );

    // Membership-only reorder currently has no cloud entity/outbox.
    final pending = await LocalSyncDao(db).findPending('user_1');
    expect(pending, isEmpty);
  });

  test('rejects incomplete reorder without mutating membership', () async {
    final fixture = await createFixture();

    await expectLater(
      service.reorderEdition(
        albumEditionId: fixture.standardEdition.id,
        orderedSongIds: [fixture.songA.id, fixture.songB.id],
        now: mutationTime,
      ),
      throwsStateError,
    );

    final db = await appDatabase.database;
    final memberships = await AlbumEditionTrackDao(
      db,
    ).findByEditionId(fixture.standardEdition.id);

    expect(memberships.map((membership) => membership.songId), [
      fixture.songA.id,
      fixture.songB.id,
      fixture.songC.id,
    ]);

    expect(memberships.map((membership) => membership.sortPosition), [0, 1, 2]);

    for (final membership in memberships) {
      expect(membership.orderingAuthority, AlbumEditionTrackAuthority.inferred);
      expect(membership.updatedAt, originalTime);
    }
  });

  test(
    'explicit compatibility placement updates membership song and sync',
    () async {
      final fixture = await createFixture();

      final result = await service.updateTrackPlacement(
        userId: ' user_1 ',
        albumEditionId: fixture.standardEdition.id,
        songId: fixture.songA.id,
        discNumber: 2,
        trackNumber: 8,
        now: mutationTime,
      );

      expect(result.changed, isTrue);
      expect(result.compatibilitySongChanged, isTrue);
      expect(result.membership.discNumber, 2);
      expect(result.membership.trackNumber, 8);
      expect(result.membership.sortPosition, 0);
      expect(
        result.membership.numberingAuthority,
        AlbumEditionTrackAuthority.manual,
      );
      expect(
        result.membership.orderingAuthority,
        AlbumEditionTrackAuthority.inferred,
      );

      final db = await appDatabase.database;

      final storedSong = await SongDao(db).findById(fixture.songA.id);

      expect(storedSong, isNotNull);
      expect(storedSong!.discNumber, 2);
      expect(storedSong.trackNumber, 8);
      expect(storedSong.updatedAt, mutationTime);

      final pending = await LocalSyncDao(db).findPending('user_1');

      expect(pending, hasLength(1));
      expect(pending.single.entityType, CloudDataEntity.song);
      expect(pending.single.entityId, fixture.songA.id);
    },
  );

  test('non-compatibility placement stays edition-specific', () async {
    final fixture = await createFixture();

    final result = await service.updateTrackPlacement(
      userId: 'user_1',
      albumEditionId: fixture.deluxeEdition.id,
      songId: fixture.songA.id,
      discNumber: 3,
      trackNumber: 12,
      now: mutationTime,
    );

    expect(result.changed, isTrue);
    expect(result.compatibilitySongChanged, isFalse);
    expect(result.membership.discNumber, 3);
    expect(result.membership.trackNumber, 12);
    expect(result.membership.sortPosition, 7);
    expect(
      result.membership.numberingAuthority,
      AlbumEditionTrackAuthority.manual,
    );

    final db = await appDatabase.database;

    final storedSong = await SongDao(db).findById(fixture.songA.id);

    expect(storedSong, isNotNull);

    // Shared Song compatibility projection is still Standard.
    expect(storedSong!.albumEditionId, fixture.standardEdition.id);
    expect(storedSong.discNumber, fixture.songA.discNumber);
    expect(storedSong.trackNumber, fixture.songA.trackNumber);
    expect(storedSong.updatedAt, originalTime);

    final pending = await LocalSyncDao(db).findPending('user_1');
    expect(pending, isEmpty);
  });

  test(
    'explicit unchanged placement can lock numbering authority manual',
    () async {
      final fixture = await createFixture();

      final result = await service.updateTrackPlacement(
        userId: 'user_1',
        albumEditionId: fixture.standardEdition.id,
        songId: fixture.songC.id,
        discNumber: 1,
        trackNumber: 3,
        now: mutationTime,
      );

      expect(result.changed, isTrue);
      expect(result.compatibilitySongChanged, isFalse);
      expect(
        result.membership.numberingAuthority,
        AlbumEditionTrackAuthority.manual,
      );
      expect(result.membership.updatedAt, mutationTime);

      final db = await appDatabase.database;

      final storedSong = await SongDao(db).findById(fixture.songC.id);

      expect(storedSong, isNotNull);
      expect(storedSong!.updatedAt, originalTime);

      final pending = await LocalSyncDao(db).findPending('user_1');
      expect(pending, isEmpty);
    },
  );
}

class _Fixture {
  const _Fixture({
    required this.standardEdition,
    required this.deluxeEdition,
    required this.songA,
    required this.songB,
    required this.songC,
  });

  final AlbumEdition standardEdition;
  final AlbumEdition deluxeEdition;
  final Song songA;
  final Song songB;
  final Song songC;
}
