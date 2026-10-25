import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/library/application/services/track_profile_editing_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/metadata_field_state_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_field_state.dart';
import 'package:sonus_next/features/library/domain/metadata/metadata_fields.dart';
import 'package:sonus_next/features/sync/data/daos/local_sync_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

// SN-48J J2: saving a track never changes its edition memberships unless the
// user explicitly moves it. In-memory databases only; fictional fixtures.
//
// Before the fix the edit dialogs sent the album's primary edition with
// every save, which the service applied as "add to this edition": a
// Deluxe-only track became a Standard track too.
void main() {
  sqfliteFfiInit();

  final t0 = DateTime.utc(2026, 9, 14, 12);
  final t1 = DateTime.utc(2026, 9, 14, 13);

  late AppDatabase appDatabase;
  late TrackProfileEditingService service;
  late _Library library;

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    var next = 0;
    service = TrackProfileEditingService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'outbox_${++next}',
        now: () => t1,
      ),
    );
    library = await _Library.seed(appDatabase, t0);
  });

  tearDown(() => appDatabase.close());

  Future<List<AlbumEditionTrack>> memberships(String songId) async =>
      AlbumEditionTrackDao(await appDatabase.database).findBySongId(songId);

  AlbumEditionTrack listing(List<AlbumEditionTrack> all, String editionId) =>
      all.singleWhere((m) => m.albumEditionId == editionId);

  Future<Song> stored(String songId) async =>
      (await SongDao(await appDatabase.database).findById(songId))!;

  Future<TrackProfileEditResult> save(
    Song song, {
    String? title,
    int? trackNumber,
    int? discNumber,
    List<String>? featuredArtists,
    bool? isSingle,
    String? albumId,
    String? albumEditionId,
    String? placementEditionId,
  }) {
    return service.updateTrack(
      userId: 'user_1',
      songId: song.id,
      title: title ?? song.title,
      trackNumber: trackNumber ?? song.trackNumber,
      discNumber: discNumber ?? song.discNumber,
      featuredArtists: featuredArtists ?? song.featuredArtists,
      isSingle: isSingle ?? song.isSingle,
      albumId: albumId,
      albumEditionId: albumEditionId,
      placementEditionId: placementEditionId,
      now: t1,
    );
  }

  group('A/B: ordinary saves keep edition memberships', () {
    test(
      'saving the title of a Deluxe-only track keeps it Deluxe-only',
      () async {
        final song = library.deluxeOnly;
        final before = await memberships(song.id);

        final result = await save(
          song,
          title: 'Bonus (renamed)',
          trackNumber: 12,
          placementEditionId: library.deluxe,
        );

        expect(result.changed, isTrue);
        expect(result.song.title, 'Bonus (renamed)');
        expect(result.song.albumEditionId, library.deluxe);
        expect(await memberships(song.id), before);
      },
    );

    test(
      'credits, single flag and version saves leave memberships alone',
      () async {
        final song = library.shared;
        final before = await memberships(song.id);

        await save(
          song,
          featuredArtists: const ['A Guest'],
          isSingle: true,
          placementEditionId: library.standard,
        );

        expect(await memberships(song.id), before);
        expect((await stored(song.id)).albumEditionId, library.standard);
      },
    );

    test('an ordinary save records no edition provenance', () async {
      await save(
        library.deluxeOnly,
        title: 'Bonus (renamed)',
        trackNumber: 12,
        placementEditionId: library.deluxe,
      );

      final states = await MetadataFieldStateDao(await appDatabase.database)
          .findByEntity(
            entityType: MetadataEntityType.song,
            entityId: library.deluxeOnly.id,
          );
      expect(
        states.map((state) => state.fieldName),
        isNot(contains(MetadataFields.songAlbumEdition)),
      );
    });
  });

  group('C: shared Standard and Deluxe tracks', () {
    test('a metadata save keeps both memberships unchanged', () async {
      final song = library.shared;
      final before = await memberships(song.id);

      await save(
        song,
        title: 'Shared (renamed)',
        placementEditionId: library.deluxe,
      );

      expect(await memberships(song.id), before);
    });

    test(
      'a placement edit from Deluxe changes only the Deluxe listing',
      () async {
        final song = library.shared;

        final result = await save(
          song,
          trackNumber: 9,
          placementEditionId: library.deluxe,
        );

        final after = await memberships(song.id);
        final deluxe = listing(after, library.deluxe);
        final standard = listing(after, library.standard);

        expect(result.changed, isTrue);
        expect(deluxe.trackNumber, 9);
        expect(deluxe.numberingAuthority, AlbumEditionTrackAuthority.manual);
        expect(deluxe.sortPosition, 5);
        expect(deluxe.orderingAuthority, AlbumEditionTrackAuthority.manual);
        // The song's own numbers follow its compatibility listing (Standard).
        expect(standard.trackNumber, 3);
        expect(standard.sortPosition, 2);
        expect((await stored(song.id)).trackNumber, 3);
        expect((await stored(song.id)).albumEditionId, library.standard);
      },
    );

    test('a Deluxe-only placement edit records no song mutation', () async {
      await save(
        library.shared,
        trackNumber: 9,
        placementEditionId: library.deluxe,
      );

      final outbox = await LocalSyncDao(
        await appDatabase.database,
      ).findPending('user_1');
      // Listings are local; the song itself did not change.
      expect(outbox, isEmpty);
    });

    test(
      'a placement edit from Standard changes Standard and the song',
      () async {
        final song = library.shared;

        await save(song, trackNumber: 7, placementEditionId: library.standard);

        final after = await memberships(song.id);
        expect(listing(after, library.standard).trackNumber, 7);
        expect(listing(after, library.deluxe).trackNumber, 4);
        expect((await stored(song.id)).trackNumber, 7);
      },
    );

    test('a listing the song is not in is rejected without changes', () async {
      final song = library.deluxeOnly;
      final before = await memberships(song.id);

      await expectLater(
        save(song, title: 'X', placementEditionId: library.standard),
        throwsA(isA<StateError>()),
      );

      expect(await memberships(song.id), before);
      expect((await stored(song.id)).title, song.title);
    });
  });

  group('D: moving to another album', () {
    test('a shared track leaves every listing in the old album', () async {
      final song = library.shared;

      final result = await save(
        song,
        albumId: library.albumB,
        albumEditionId: library.bStandard,
      );

      final after = await memberships(song.id);
      expect(after.map((m) => m.albumEditionId), [library.bStandard]);
      expect(result.song.id, song.id);
      expect(result.song.albumId, library.albumB);
      expect(result.song.albumEditionId, library.bStandard);
    });

    test('the moved track is appended to the target listing', () async {
      final song = library.deluxeOnly;

      await save(
        song,
        albumId: library.albumB,
        albumEditionId: library.bStandard,
      );

      final target = listing(await memberships(song.id), library.bStandard);
      expect(target.sortPosition, 1, reason: 'after the existing B track');
      expect(target.orderingAuthority, AlbumEditionTrackAuthority.inferred);
    });

    test('the move records one song upsert with the new pointer', () async {
      await save(
        library.shared,
        albumId: library.albumB,
        albumEditionId: library.bStandard,
      );

      final outbox = await LocalSyncDao(
        await appDatabase.database,
      ).findPending('user_1');
      expect(outbox, hasLength(1));
      expect(outbox.single.entityType, CloudDataEntity.song);
      expect(outbox.single.entityId, library.shared.id);
    });
  });

  group('E: manual order and numbering', () {
    test(
      'an unrelated save keeps manual sort and numbering everywhere',
      () async {
        final before = await memberships(library.deluxeOnly.id);

        await save(
          library.deluxeOnly,
          title: 'Bonus (renamed)',
          trackNumber: 12,
          placementEditionId: library.deluxe,
        );

        final after = listing(
          await memberships(library.deluxeOnly.id),
          library.deluxe,
        );
        final original = listing(before, library.deluxe);
        expect(after.sortPosition, original.sortPosition);
        expect(after.orderingAuthority, AlbumEditionTrackAuthority.manual);
        expect(after.numberingAuthority, AlbumEditionTrackAuthority.manual);
      },
    );
  });

  group('F: failure rolls back completely', () {
    test(
      'a failed save leaves memberships, pointer and song unchanged',
      () async {
        // A duplicate outbox id makes the second save fail at its last step.
        final failing = TrackProfileEditingService(
          mutationRunner: SyncMutationTransactionRunner(
            appDatabase: appDatabase,
            generateId: () => 'fixed_outbox_id',
            now: () => t1,
          ),
        );
        await failing.updateTrack(
          userId: 'user_1',
          songId: library.trackB.id,
          title: 'Occupies the outbox id',
          trackNumber: library.trackB.trackNumber,
          discNumber: 1,
          featuredArtists: const [],
          isSingle: false,
          now: t1,
        );

        final song = library.shared;
        final before = await memberships(song.id);

        await expectLater(
          failing.updateTrack(
            userId: 'user_1',
            songId: song.id,
            title: 'Moved',
            trackNumber: 1,
            discNumber: 1,
            featuredArtists: const [],
            isSingle: false,
            albumId: library.albumB,
            albumEditionId: library.bStandard,
            now: t1,
          ),
          throwsA(isA<DatabaseException>()),
        );

        expect(await memberships(song.id), before);
        final after = await stored(song.id);
        expect(after.albumId, library.albumA);
        expect(after.albumEditionId, library.standard);
        expect(after.title, song.title);
      },
    );
  });

  group('H: sync', () {
    test(
      'an ordinary save syncs the unchanged compatibility pointer',
      () async {
        await save(
          library.deluxeOnly,
          title: 'Bonus (renamed)',
          trackNumber: 12,
          placementEditionId: library.deluxe,
        );

        final outbox = await LocalSyncDao(
          await appDatabase.database,
        ).findPending('user_1');
        expect(outbox.single.entityId, library.deluxeOnly.id);
        // The synced song row still points at Deluxe, so receiving devices add
        // no Standard listing.
        expect(
          (await stored(library.deluxeOnly.id)).albumEditionId,
          library.deluxe,
        );
      },
    );
  });

  group('I: explicit add-to-edition still works', () {
    test(
      'a same-album edition operation adds the listing and keeps the old',
      () async {
        final song = library.deluxeOnly;

        final result = await save(song, albumEditionId: library.standard);

        final after = await memberships(song.id);
        expect(after.map((m) => m.albumEditionId).toSet(), {
          library.deluxe,
          library.standard,
        });
        expect(result.song.albumEditionId, library.standard);
      },
    );
  });
}

/// Album A has Standard (primary) and Deluxe; album B has one Standard.
class _Library {
  _Library({
    required this.albumA,
    required this.albumB,
    required this.standard,
    required this.deluxe,
    required this.bStandard,
    required this.deluxeOnly,
    required this.shared,
    required this.trackB,
  });

  final String albumA;
  final String albumB;
  final String standard;
  final String deluxe;
  final String bStandard;

  /// Only on Deluxe, with manual numbering and ordering.
  final Song deluxeOnly;

  /// On Standard (track 3, its compatibility listing) and Deluxe (track 4,
  /// manual ordering).
  final Song shared;

  /// Album B's existing track.
  final Song trackB;

  static Future<_Library> seed(AppDatabase appDatabase, DateTime t0) async {
    final db = await appDatabase.database;
    final artist = EntityFactory.createArtist(name: 'Fixture Artist', now: t0);
    final albumA = EntityFactory.createAlbum(
      artistId: artist.id,
      title: 'Album A',
      now: t0,
    );
    final albumB = EntityFactory.createAlbum(
      artistId: artist.id,
      title: 'Album B',
      now: t0,
    );
    final standard = EntityFactory.createAlbumEdition(
      albumId: albumA.id,
      title: 'Standard',
      isPrimary: true,
      now: t0,
    );
    final deluxe = EntityFactory.createAlbumEdition(
      albumId: albumA.id,
      title: 'Deluxe',
      isPrimary: false,
      now: t0,
    );
    final bStandard = EntityFactory.createAlbumEdition(
      albumId: albumB.id,
      title: 'Standard',
      isPrimary: true,
      now: t0,
    );
    Song song(String title, String albumId, String editionId, int track) =>
        EntityFactory.createSong(
          artistId: artist.id,
          albumId: albumId,
          albumEditionId: editionId,
          title: title,
          trackNumber: track,
          durationSeconds: 200,
          now: t0,
        );
    final deluxeOnly = song('Bonus', albumA.id, deluxe.id, 12);
    final shared = song('Shared', albumA.id, standard.id, 3);
    final trackB = song('B Track', albumB.id, bStandard.id, 1);

    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(albumA);
    await AlbumDao(db).insert(albumB);
    for (final edition in [standard, deluxe, bStandard]) {
      await AlbumEditionDao(db).insert(edition);
    }
    for (final s in [deluxeOnly, shared, trackB]) {
      await SongDao(db).insert(s);
    }

    final dao = AlbumEditionTrackDao(db);
    Future<void> list(
      String editionId,
      Song s,
      int track,
      int sort, {
      bool manualNumbers = false,
      bool manualOrder = false,
    }) => dao.insert(
      AlbumEditionTrack(
        albumEditionId: editionId,
        songId: s.id,
        discNumber: 1,
        trackNumber: track,
        sortPosition: sort,
        numberingAuthority: manualNumbers
            ? AlbumEditionTrackAuthority.manual
            : AlbumEditionTrackAuthority.inferred,
        orderingAuthority: manualOrder
            ? AlbumEditionTrackAuthority.manual
            : AlbumEditionTrackAuthority.inferred,
        createdAt: t0,
        updatedAt: t0,
      ),
    );
    await list(
      deluxe.id,
      deluxeOnly,
      12,
      11,
      manualNumbers: true,
      manualOrder: true,
    );
    await list(standard.id, shared, 3, 2);
    await list(deluxe.id, shared, 4, 5, manualOrder: true);
    await list(bStandard.id, trackB, 1, 0);

    return _Library(
      albumA: albumA.id,
      albumB: albumB.id,
      standard: standard.id,
      deluxe: deluxe.id,
      bStandard: bStandard.id,
      deluxeOnly: deluxeOnly,
      shared: shared,
      trackB: trackB,
    );
  }
}
