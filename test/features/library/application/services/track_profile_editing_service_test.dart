import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/local_sync_models.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late TrackProfileEditingService service;

  final originalTime = DateTime.utc(2026, 9, 14, 12);
  final mutationTime = DateTime.utc(2026, 9, 14, 13);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    var nextOutboxId = 0;

    service = TrackProfileEditingService(
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

  Future<Song> createSong({
    String title = 'Original Song',
    int trackNumber = 1,
    bool isSingle = false,
    List<String> featuredArtists = const ['Original Feature'],
    int durationSeconds = 245,
  }) async {
    final artist = EntityFactory.createArtist(
      name: 'Test Artist',
      now: originalTime,
    );

    final album = EntityFactory.createAlbum(
      artistId: artist.id,
      title: 'Test Album',
      now: originalTime,
    );

    final edition = EntityFactory.createAlbumEdition(
      albumId: album.id,
      title: 'Standard',
      isPrimary: true,
      now: originalTime,
    );

    final song = EntityFactory.createSong(
      artistId: artist.id,
      albumId: album.id,
      albumEditionId: edition.id,
      title: title,
      trackNumber: trackNumber,
      durationSeconds: durationSeconds,
      isSingle: isSingle,
      featuredArtists: featuredArtists,
      now: originalTime,
    );

    final db = await appDatabase.database;

    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(album);
    await AlbumEditionDao(db).insert(edition);
    await SongDao(db).insert(song);
    await AlbumEditionTrackDao(db).insert(
      AlbumEditionTrack(
        albumEditionId: edition.id,
        songId: song.id,
        discNumber: song.discNumber,
        trackNumber: song.trackNumber,
        sortPosition: 7,
        createdAt: originalTime,
        updatedAt: originalTime,
      ),
    );

    return song;
  }

  test('updates track metadata and records cloud upsert atomically', () async {
    final original = await createSong();

    final result = await service.updateTrack(
      userId: ' user_1 ',
      songId: original.id,
      title: '  Renamed Song  ',
      trackNumber: 4,
      discNumber: 1,
      featuredArtists: const ['  Feature One  ', '', 'Feature Two'],
      isSingle: true,
      now: mutationTime,
    );

    expect(result.changed, isTrue);

    final updated = result.song;

    expect(updated.id, original.id);
    expect(updated.artistId, original.artistId);
    expect(updated.albumId, original.albumId);
    expect(updated.albumEditionId, original.albumEditionId);

    expect(updated.title, 'Renamed Song');
    expect(updated.canonicalTitle, 'renamed song');
    expect(updated.trackNumber, 4);
    expect(updated.isSingle, isTrue);
    expect(updated.featuredArtists, ['Feature One', 'Feature Two']);

    expect(updated.durationSeconds, original.durationSeconds);
    expect(updated.artworkId, original.artworkId);
    expect(updated.createdAt, originalTime);
    expect(updated.updatedAt, mutationTime);

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.id, original.id);
    expect(stored.artistId, original.artistId);
    expect(stored.albumId, original.albumId);
    expect(stored.albumEditionId, original.albumEditionId);
    expect(stored.title, 'Renamed Song');
    expect(stored.canonicalTitle, 'renamed song');
    expect(stored.trackNumber, 4);
    expect(stored.isSingle, isTrue);
    expect(stored.featuredArtists, ['Feature One', 'Feature Two']);
    expect(stored.durationSeconds, original.durationSeconds);
    expect(stored.createdAt, originalTime);
    expect(stored.updatedAt, mutationTime);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.song);
    expect(pending.single.entityId, original.id);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test('updates disc number and records the mutation', () async {
    final original = await createSong();

    final result = await service.updateTrack(
      userId: 'user_1',
      songId: original.id,
      title: original.title,
      trackNumber: original.trackNumber,
      discNumber: 2,
      featuredArtists: original.featuredArtists,
      isSingle: original.isSingle,
      now: mutationTime,
    );

    expect(result.changed, isTrue);
    expect(result.song.discNumber, 2);

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.discNumber, 2);
    expect(stored.updatedAt, mutationTime);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.song);
    expect(pending.single.entityId, original.id);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });
  test('canonicalizes song title independently from display title', () async {
    final original = await createSong();

    final result = await service.updateTrack(
      userId: 'user_1',
      songId: original.id,
      title: '  The   Song  ',
      trackNumber: original.trackNumber,
      discNumber: 1,
      featuredArtists: original.featuredArtists,
      isSingle: original.isSingle,
      now: mutationTime,
    );

    expect(result.changed, isTrue);
    expect(result.song.title, 'The   Song');
    expect(result.song.canonicalTitle, 'the song');

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.title, 'The   Song');
    expect(stored.canonicalTitle, 'the song');
  });

  test('normalizes featured artist whitespace and removes blanks', () async {
    final original = await createSong(featuredArtists: const []);

    final result = await service.updateTrack(
      userId: 'user_1',
      songId: original.id,
      title: original.title,
      trackNumber: original.trackNumber,
      discNumber: 1,
      featuredArtists: const [' Guest One ', '   ', 'Guest Two'],
      isSingle: original.isSingle,
      now: mutationTime,
    );

    expect(result.changed, isTrue);
    expect(result.song.featuredArtists, ['Guest One', 'Guest Two']);
  });

  test('no-op update does not change timestamp or create outbox', () async {
    final original = await createSong(
      featuredArtists: const ['Feature One', 'Feature Two'],
    );

    final result = await service.updateTrack(
      userId: 'user_1',
      songId: original.id,
      title: '  ${original.title}  ',
      trackNumber: original.trackNumber,
      discNumber: 1,
      featuredArtists: const [' Feature One ', ' Feature Two '],
      isSingle: original.isSingle,
      now: mutationTime,
    );

    expect(result.changed, isFalse);
    expect(result.song.id, original.id);
    expect(result.song.updatedAt, originalTime);

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.updatedAt, originalTime);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, isEmpty);
  });

  test('missing song fails without creating outbox entry', () async {
    await expectLater(
      service.updateTrack(
        userId: 'user_1',
        songId: 'song_missing',
        title: 'Changed Song',
        trackNumber: 1,
        discNumber: 1,
        featuredArtists: const [],
        isSingle: false,
        now: mutationTime,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Song not found: song_missing',
        ),
      ),
    );

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('signed-out track edit records unowned upsert', () async {
    final original = await createSong();

    final result = await service.updateTrack(
      userId: null,
      songId: original.id,
      title: 'Changed Song',
      trackNumber: 1,
      discNumber: 1,
      featuredArtists: const [],
      isSingle: false,
      now: mutationTime,
    );

    expect(result.changed, isTrue);
    expect(result.song.title, 'Changed Song');

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.title, 'Changed Song');
    expect(stored.updatedAt, mutationTime);

    final pending = await LocalSyncDao(db).findUnownedPending();

    expect(pending, hasLength(1));
    expect(pending.single.userId, isNull);
    expect(pending.single.entityType, CloudDataEntity.song);
    expect(pending.single.entityId, original.id);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test('rejects blank song id before mutation', () async {
    await expectLater(
      () => service.updateTrack(
        userId: 'user_1',
        songId: '   ',
        title: 'Changed Song',
        trackNumber: 1,
        discNumber: 1,
        featuredArtists: const [],
        isSingle: false,
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rejects blank song title without changing stored song', () async {
    final original = await createSong();

    await expectLater(
      () => service.updateTrack(
        userId: 'user_1',
        songId: original.id,
        title: '   ',
        trackNumber: original.trackNumber,
        discNumber: 1,
        featuredArtists: original.featuredArtists,
        isSingle: original.isSingle,
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.title, original.title);
    expect(stored.canonicalTitle, original.canonicalTitle);
    expect(stored.updatedAt, originalTime);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rejects negative track number without changing stored song', () async {
    final original = await createSong();

    await expectLater(
      () => service.updateTrack(
        userId: 'user_1',
        songId: original.id,
        title: original.title,
        trackNumber: -1,
        discNumber: 1,
        featuredArtists: original.featuredArtists,
        isSingle: original.isSingle,
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.trackNumber, original.trackNumber);
    expect(stored.updatedAt, originalTime);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });

  test('rejects negative disc number without changing stored song', () async {
    final original = await createSong();

    await expectLater(
      () => service.updateTrack(
        userId: 'user_1',
        songId: original.id,
        title: original.title,
        trackNumber: original.trackNumber,
        discNumber: -1,
        featuredArtists: original.featuredArtists,
        isSingle: original.isSingle,
        now: mutationTime,
      ),
      throwsA(isA<ArgumentError>()),
    );

    final db = await appDatabase.database;
    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.discNumber, original.discNumber);
    expect(stored.updatedAt, originalTime);
    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });
  test('repeated edits retain permanent song identity', () async {
    final original = await createSong();

    await service.updateTrack(
      userId: 'user_1',
      songId: original.id,
      title: 'First Edit',
      trackNumber: 2,
      discNumber: 1,
      featuredArtists: const [],
      isSingle: false,
      now: mutationTime,
    );

    final secondMutationTime = mutationTime.add(const Duration(minutes: 1));

    final result = await service.updateTrack(
      userId: 'user_1',
      songId: original.id,
      title: 'Second Edit',
      trackNumber: 3,
      discNumber: 1,
      featuredArtists: const ['Feature'],
      isSingle: true,
      now: secondMutationTime,
    );

    expect(result.song.id, original.id);
    expect(result.song.artistId, original.artistId);
    expect(result.song.albumId, original.albumId);
    expect(result.song.albumEditionId, original.albumEditionId);
    expect(result.song.updatedAt, secondMutationTime);

    final db = await appDatabase.database;
    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.song);
    expect(pending.single.entityId, original.id);
  });

  test('rolls back song edit when outbox mutation fails', () async {
    final firstSong = await createSong(title: 'First Song');
    final secondSong = await createSong(title: 'Second Song');

    final collisionService = TrackProfileEditingService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'fixed_outbox_id',
        now: () => mutationTime,
      ),
    );

    await collisionService.updateTrack(
      userId: 'user_1',
      songId: firstSong.id,
      title: 'First Song Edited',
      trackNumber: firstSong.trackNumber,
      discNumber: 1,
      featuredArtists: firstSong.featuredArtists,
      isSingle: firstSong.isSingle,
      now: mutationTime,
    );

    await expectLater(
      collisionService.updateTrack(
        userId: 'user_1',
        songId: secondSong.id,
        title: 'Second Song Edited',
        trackNumber: secondSong.trackNumber,
        discNumber: 1,
        featuredArtists: secondSong.featuredArtists,
        isSingle: secondSong.isSingle,
        now: mutationTime,
      ),
      throwsA(isA<DatabaseException>()),
    );

    final db = await appDatabase.database;

    final storedFirst = await SongDao(db).findById(firstSong.id);
    final storedSecond = await SongDao(db).findById(secondSong.id);

    expect(storedFirst, isNotNull);
    expect(storedFirst!.title, 'First Song Edited');

    expect(storedSecond, isNotNull);
    expect(storedSecond!.title, 'Second Song');
    expect(storedSecond.updatedAt, originalTime);
    final rolledBackMemberships = await AlbumEditionTrackDao(
      db,
    ).findBySongId(secondSong.id);

    expect(rolledBackMemberships, hasLength(1));
    expect(rolledBackMemberships.single.trackNumber, secondSong.trackNumber);
    expect(rolledBackMemberships.single.discNumber, secondSong.discNumber);
    expect(rolledBackMemberships.single.sortPosition, 7);
    expect(rolledBackMemberships.single.updatedAt, originalTime);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityId, firstSong.id);
  });

  test(
    'track number edit updates membership and preserves sort position',
    () async {
      final original = await createSong(trackNumber: 1);

      await service.updateTrack(
        userId: 'user_1',
        songId: original.id,
        title: original.title,
        trackNumber: 9,
        discNumber: 2,
        featuredArtists: original.featuredArtists,
        isSingle: original.isSingle,
        now: mutationTime,
      );

      final db = await appDatabase.database;
      final memberships = await AlbumEditionTrackDao(
        db,
      ).findBySongId(original.id);

      expect(memberships, hasLength(1));
      expect(memberships.single.albumEditionId, original.albumEditionId);
      expect(memberships.single.discNumber, 2);
      expect(memberships.single.trackNumber, 9);
      expect(memberships.single.sortPosition, 7);
      expect(
        memberships.single.numberingAuthority,
        AlbumEditionTrackAuthority.manual,
      );
      expect(
        memberships.single.orderingAuthority,
        AlbumEditionTrackAuthority.inferred,
      );
      expect(memberships.single.createdAt, originalTime);
      expect(memberships.single.updatedAt, mutationTime);
    },
  );

  test('metadata-only edit leaves edition membership unchanged', () async {
    final original = await createSong();

    await service.updateTrack(
      userId: 'user_1',
      songId: original.id,
      title: 'Metadata Only Edit',
      trackNumber: original.trackNumber,
      discNumber: original.discNumber,
      featuredArtists: original.featuredArtists,
      isSingle: original.isSingle,
      now: mutationTime,
    );

    final db = await appDatabase.database;
    final memberships = await AlbumEditionTrackDao(
      db,
    ).findBySongId(original.id);

    expect(memberships, hasLength(1));
    expect(memberships.single.albumEditionId, original.albumEditionId);
    expect(memberships.single.discNumber, original.discNumber);
    expect(memberships.single.trackNumber, original.trackNumber);
    expect(memberships.single.sortPosition, 7);
    expect(
      memberships.single.numberingAuthority,
      AlbumEditionTrackAuthority.inferred,
    );
    expect(
      memberships.single.orderingAuthority,
      AlbumEditionTrackAuthority.inferred,
    );
    expect(memberships.single.updatedAt, originalTime);
  });
  test(
    'same-album edition reassignment preserves existing edition membership',
    () async {
      final original = await createSong();

      final db = await appDatabase.database;

      final deluxeEdition = EntityFactory.createAlbumEdition(
        albumId: original.albumId,
        title: 'Deluxe',
        isPrimary: false,
        now: originalTime,
      );

      await AlbumEditionDao(db).insert(deluxeEdition);

      final result = await service.updateTrack(
        userId: 'user_1',
        songId: original.id,
        title: original.title,
        trackNumber: 12,
        discNumber: 2,
        featuredArtists: original.featuredArtists,
        isSingle: original.isSingle,
        albumEditionId: deluxeEdition.id,
        now: mutationTime,
      );

      expect(result.changed, isTrue);
      expect(result.song.id, original.id);
      expect(result.song.albumId, original.albumId);
      expect(result.song.albumEditionId, deluxeEdition.id);

      final memberships = await AlbumEditionTrackDao(
        db,
      ).findBySongId(original.id);

      expect(memberships, hasLength(2));

      final standardMembership = memberships.singleWhere(
        (membership) => membership.albumEditionId == original.albumEditionId,
      );

      expect(standardMembership.discNumber, original.discNumber);
      expect(standardMembership.trackNumber, original.trackNumber);
      expect(standardMembership.sortPosition, 7);
      expect(standardMembership.createdAt, originalTime);
      expect(standardMembership.updatedAt, originalTime);

      final deluxeMembership = memberships.singleWhere(
        (membership) => membership.albumEditionId == deluxeEdition.id,
      );

      expect(deluxeMembership.discNumber, 2);
      expect(deluxeMembership.trackNumber, 12);
      expect(deluxeMembership.sortPosition, 0);
      expect(
        deluxeMembership.numberingAuthority,
        AlbumEditionTrackAuthority.manual,
      );
      expect(
        deluxeMembership.orderingAuthority,
        AlbumEditionTrackAuthority.inferred,
      );
      expect(deluxeMembership.createdAt, mutationTime);
      expect(deluxeMembership.updatedAt, mutationTime);
    },
  );
  test('reassigns song artist album and edition atomically', () async {
    final original = await createSong();

    final targetArtist = EntityFactory.createArtist(
      name: 'Keke Palmer',
      now: originalTime,
    );

    final targetAlbum = EntityFactory.createAlbum(
      artistId: targetArtist.id,
      title: 'Rags',
      now: originalTime,
    );

    final targetEdition = EntityFactory.createAlbumEdition(
      albumId: targetAlbum.id,
      title: 'Standard',
      isPrimary: true,
      now: originalTime,
    );

    final db = await appDatabase.database;

    await ArtistDao(db).insert(targetArtist);
    await AlbumDao(db).insert(targetAlbum);
    await AlbumEditionDao(db).insert(targetEdition);

    final result = await service.updateTrack(
      userId: 'user_1',
      songId: original.id,
      title: original.title,
      trackNumber: original.trackNumber,
      discNumber: 1,
      featuredArtists: original.featuredArtists,
      isSingle: original.isSingle,
      artistId: targetArtist.id,
      albumId: targetAlbum.id,
      albumEditionId: targetEdition.id,
      now: mutationTime,
    );

    expect(result.changed, isTrue);
    expect(result.song.id, original.id);
    expect(result.song.artistId, targetArtist.id);
    expect(result.song.albumId, targetAlbum.id);
    expect(result.song.albumEditionId, targetEdition.id);

    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.artistId, targetArtist.id);
    expect(stored.albumId, targetAlbum.id);
    expect(stored.albumEditionId, targetEdition.id);
    final oldMemberships = await AlbumEditionTrackDao(
      db,
    ).findByEditionId(original.albumEditionId);

    expect(
      oldMemberships.where((membership) => membership.songId == original.id),
      isEmpty,
    );

    final targetMemberships = await AlbumEditionTrackDao(
      db,
    ).findByEditionId(targetEdition.id);

    final movedMembership = targetMemberships.singleWhere(
      (membership) => membership.songId == original.id,
    );

    expect(movedMembership.discNumber, 1);
    expect(movedMembership.trackNumber, original.trackNumber);
    expect(movedMembership.sortPosition, 0);
    expect(movedMembership.createdAt, mutationTime);
    expect(movedMembership.updatedAt, mutationTime);

    final pending = await LocalSyncDao(db).findPending('user_1');

    expect(pending, hasLength(1));
    expect(pending.single.entityType, CloudDataEntity.song);
    expect(pending.single.entityId, original.id);
    expect(pending.single.operation, SyncOutboxOperation.upsert);
  });

  test('rejects edition that belongs to a different album', () async {
    final original = await createSong();

    final artist = EntityFactory.createArtist(
      name: 'Other Artist',
      now: originalTime,
    );

    final targetAlbum = EntityFactory.createAlbum(
      artistId: artist.id,
      title: 'Target Album',
      now: originalTime,
    );

    final otherAlbum = EntityFactory.createAlbum(
      artistId: artist.id,
      title: 'Other Album',
      now: originalTime,
    );

    final wrongEdition = EntityFactory.createAlbumEdition(
      albumId: otherAlbum.id,
      title: 'Standard',
      isPrimary: true,
      now: originalTime,
    );

    final db = await appDatabase.database;

    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(targetAlbum);
    await AlbumDao(db).insert(otherAlbum);
    await AlbumEditionDao(db).insert(wrongEdition);

    await expectLater(
      service.updateTrack(
        userId: 'user_1',
        songId: original.id,
        title: original.title,
        trackNumber: original.trackNumber,
        discNumber: 1,
        featuredArtists: original.featuredArtists,
        isSingle: original.isSingle,
        artistId: artist.id,
        albumId: targetAlbum.id,
        albumEditionId: wrongEdition.id,
        now: mutationTime,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('does not belong to album'),
        ),
      ),
    );

    final stored = await SongDao(db).findById(original.id);

    expect(stored, isNotNull);
    expect(stored!.artistId, original.artistId);
    expect(stored.albumId, original.albumId);
    expect(stored.albumEditionId, original.albumEditionId);

    expect(await LocalSyncDao(db).findPending('user_1'), isEmpty);
  });
}
