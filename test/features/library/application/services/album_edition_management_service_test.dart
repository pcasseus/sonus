import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/library/application/models/release_display_title.dart';
import 'package:sonus_next/features/library/application/services/album_edition_management_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/sync/data/daos/cloud_revision_baseline_dao.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';
import 'package:sonus_next/features/sync/domain/models/sync_data_contract.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late AlbumEditionManagementService editions;
  final now = DateTime.utc(2026, 10, 25, 12);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    var outbox = 0;
    editions = AlbumEditionManagementService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'outbox_${++outbox}',
        now: () => now,
      ),
    );
  });

  tearDown(() => appDatabase.close());

  /// Imports a three-track Standard album; returns (albumId, standardId,
  /// songIds by title).
  Future<(String, String, Map<String, String>)> standardAlbum() async {
    final importer = AtomicLibraryImporter(appDatabase: appDatabase);
    final ids = <String, String>{};

    for (final (n, title) in [(1, 'One'), (2, 'Two'), (3, 'Three')]) {
      final path = 'A/locket/$title.mp3';
      final result = await importer.import(
        candidate: ImportCandidate(
          filePath: path,
          normalizedPath: path.toLowerCase(),
          discoveredAt: now,
        ),
        metadata: AudioMetadata(
          title: title,
          artistName: 'Madison Beer',
          albumTitle: 'locket',
          durationSeconds: 180,
          trackNumber: n,
          discNumber: 1,
          isSingle: false,
          featuredArtists: const [],
        ),
        now: now,
      );
      ids[title] = result.songId!;
    }

    final db = await appDatabase.database;
    final song = await SongDao(db).findById(ids['One']!);
    return (song!.albumId, song.albumEditionId, ids);
  }

  Future<List<AlbumEdition>> editionsOf(String albumId) async {
    final db = await appDatabase.database;
    return AlbumEditionDao(db).findByAlbumId(albumId);
  }

  Future<List<String>> listedOn(String editionId) async {
    final db = await appDatabase.database;
    return [
      for (final m in await AlbumEditionTrackDao(db).findByEditionId(editionId))
        m.songId,
    ];
  }

  Matcher refused(AlbumEditionRefusal refusal) => throwsA(
    isA<AlbumEditionManagementException>().having(
      (e) => e.refusal,
      'refusal',
      refusal,
    ),
  );

  test('a new edition shares Standard tracks without copying songs', () async {
    final (album, standard, songs) = await standardAlbum();

    final deluxe = await editions.createEdition(
      albumId: album,
      title: 'locket (Deluxe)',
      type: AlbumEditionType.deluxe,
      now: now,
    );
    final added = await editions.assignTracks(
      editionId: deluxe.id,
      songIds: [songs['One']!, songs['Two']!, songs['One']!],
      now: now,
    );

    expect(deluxe.isPrimary, isFalse);
    expect(added, 2);
    expect(await listedOn(deluxe.id), [songs['One'], songs['Two']]);
    expect(await listedOn(standard), hasLength(3));
    final db = await appDatabase.database;
    expect(await SongDao(db).findAll(), hasLength(3));
  });

  group('SN-45: a new Deluxe starts with the Standard songs', () {
    test('every Standard song is listed, in order, as the same song', () async {
      final (album, standard, songs) = await standardAlbum();
      final db = await appDatabase.database;
      final songsBefore = await db.query(DatabaseTables.songs, orderBy: 'id');

      final deluxe = await editions.createEdition(
        albumId: album,
        title: 'locket (Deluxe)',
        type: AlbumEditionType.deluxe,
        includeSongsFrom: standard,
        now: now,
      );

      expect(await listedOn(deluxe.id), await listedOn(standard));
      expect(await listedOn(deluxe.id), [
        songs['One'],
        songs['Two'],
        songs['Three'],
      ]);
      // Same song records: nothing duplicated, nothing rewritten.
      expect(await db.query(DatabaseTables.songs, orderBy: 'id'), songsBefore);
      expect(deluxe.isPrimary, isFalse);
    });

    test('disc, track and sort positions carry over', () async {
      final (album, standard, _) = await standardAlbum();
      final db = await appDatabase.database;
      final dao = AlbumEditionTrackDao(db);

      final deluxe = await editions.createEdition(
        albumId: album,
        title: 'Deluxe',
        type: AlbumEditionType.deluxe,
        includeSongsFrom: standard,
        now: now,
      );

      final source = await dao.findByEditionId(standard);
      final copy = await dao.findByEditionId(deluxe.id);
      expect(
        [for (final m in copy) (m.discNumber, m.trackNumber, m.sortPosition)],
        [for (final m in source) (m.discNumber, m.trackNumber, m.sortPosition)],
      );
    });

    test('Deluxe-only songs can be added afterwards', () async {
      final (album, standard, songs) = await standardAlbum();
      final deluxe = await editions.createEdition(
        albumId: album,
        title: 'Deluxe',
        type: AlbumEditionType.deluxe,
        includeSongsFrom: standard,
        now: now,
      );

      // Moving "Three" off Standard makes it Deluxe-exclusive.
      await editions.removeTrack(
        editionId: standard,
        songId: songs['Three']!,
        now: now,
      );

      expect(await listedOn(standard), [songs['One'], songs['Two']]);
      expect(await listedOn(deluxe.id), hasLength(3));
    });

    test('listening history and playlists are untouched', () async {
      final (album, standard, songs) = await standardAlbum();
      final db = await appDatabase.database;
      await db.insert(DatabaseTables.playlists, {
        'id': 'p1',
        'name': 'Mine',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert(DatabaseTables.playlistItems, {
        'id': 'i1',
        'playlist_id': 'p1',
        'song_id': songs['Two'],
        'position': 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      Future<List<Object?>> snapshot() async => [
        await db.query(DatabaseTables.playlistItems),
        await db.query(DatabaseTables.playbackSessions),
        await db.query(DatabaseTables.qualifiedPlays),
      ];
      final before = await snapshot();

      await editions.createEdition(
        albumId: album,
        title: 'Deluxe',
        type: AlbumEditionType.deluxe,
        includeSongsFrom: standard,
        now: now,
      );

      expect(await snapshot(), before);
    });

    test(
      'an edition of another album is refused and nothing is created',
      () async {
        final (album, _, _) = await standardAlbum();
        final importer = AtomicLibraryImporter(appDatabase: appDatabase);
        final other = await importer.import(
          candidate: ImportCandidate(
            filePath: 'B/other/x.mp3',
            normalizedPath: 'b/other/x.mp3',
            discoveredAt: now,
          ),
          metadata: const AudioMetadata(
            title: 'X',
            artistName: 'Someone',
            albumTitle: 'Other',
            durationSeconds: 100,
            trackNumber: 1,
            discNumber: 1,
            isSingle: false,
            featuredArtists: [],
          ),
          now: now,
        );
        final db = await appDatabase.database;
        final foreign = (await SongDao(db).findById(other.songId!))!;

        await expectLater(
          editions.createEdition(
            albumId: album,
            title: 'Deluxe',
            type: AlbumEditionType.deluxe,
            includeSongsFrom: foreign.albumEditionId,
            now: now,
          ),
          refused(AlbumEditionRefusal.editionNotFound),
        );
        expect(await editionsOf(album), hasLength(1));
      },
    );

    test('without a source, a new edition starts empty as before', () async {
      final (album, _, _) = await standardAlbum();
      final extra = await editions.createEdition(
        albumId: album,
        title: 'Bonus',
        type: AlbumEditionType.other,
        now: now,
      );

      expect(await listedOn(extra.id), isEmpty);
    });
  });

  test('rename and retype; titles stay unique within the album', () async {
    final (album, standard, _) = await standardAlbum();
    final extra = await editions.createEdition(
      albumId: album,
      title: 'Bonus',
      type: AlbumEditionType.other,
      now: now,
    );

    final renamed = await editions.updateEdition(
      editionId: extra.id,
      title: 'locket (Expanded)',
      type: AlbumEditionType.expanded,
      now: now,
    );

    expect(renamed.title, 'locket (Expanded)');
    expect(renamed.type, AlbumEditionType.expanded);
    await expectLater(
      editions.updateEdition(editionId: standard, title: ' LOCKET (expanded) '),
      refused(AlbumEditionRefusal.duplicateTitle),
    );
    await expectLater(
      editions.createEdition(
        albumId: album,
        title: '   ',
        type: AlbumEditionType.other,
      ),
      refused(AlbumEditionRefusal.blankTitle),
    );
  });

  test('SN-50 reconciliation: an Other edition renamed in Release Studio '
      'persists through SQLite; the release title is unchanged', () async {
    final result = await AtomicLibraryImporter(appDatabase: appDatabase).import(
      candidate: ImportCandidate(
        filePath: 'S/skyline/Horizon.mp3',
        normalizedPath: 's/skyline/horizon.mp3',
        discoveredAt: now,
      ),
      metadata: const AudioMetadata(
        title: 'Horizon',
        artistName: 'Fictional Harbour',
        albumTitle: 'Skyline',
        durationSeconds: 200,
        trackNumber: 1,
        discNumber: 1,
        isSingle: false,
        featuredArtists: [],
      ),
      now: now,
    );
    final db = await appDatabase.database;
    final albumId = (await SongDao(db).findById(result.songId!))!.albumId;

    final other = await editions.createEdition(
      albumId: albumId,
      title: 'Skyline (Extras)',
      type: AlbumEditionType.other,
      now: now,
    );
    await editions.updateEdition(
      editionId: other.id,
      title: 'Skyline (Remixes)',
      now: now,
    );

    final stored = (await AlbumEditionDao(
      db,
    ).findByAlbumId(albumId)).singleWhere((e) => e.id == other.id);
    final album = (await AlbumDao(db).findById(albumId))!;

    expect(stored.title, 'Skyline (Remixes)');
    expect(stored.type, AlbumEditionType.other);
    expect(
      editionLabel(
        title: stored.title,
        type: stored.type,
        baseTitle: album.title,
      ),
      'Remixes',
    );
    expect(
      releaseDisplayTitle(baseTitle: album.title, editionTitle: stored.title),
      'Skyline (Remixes)',
    );
    expect(album.title, 'Skyline');
  });

  test("SN-45: a rename is the user's, kept through later lookups", () async {
    final (album, _, _) = await standardAlbum();
    final extra = await editions.createEdition(
      albumId: album,
      title: 'Bonus',
      type: AlbumEditionType.other,
      now: now,
    );

    await editions.updateEdition(
      editionId: extra.id,
      title: 'Deluxe',
      type: AlbumEditionType.deluxe,
      now: now,
    );

    final db = await appDatabase.database;
    final states = await db.query(
      DatabaseTables.metadataFieldStates,
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['albumEdition', extra.id],
    );
    expect({
      for (final row in states)
        if (row['authority'] == 'manual' && row['source'] == 'user')
          row['field_name'],
    }, containsAll(['title', 'type']));
  });

  test('exactly one primary edition after choosing a new one', () async {
    final (album, standard, _) = await standardAlbum();
    final deluxe = await editions.createEdition(
      albumId: album,
      title: 'locket (Deluxe)',
      type: AlbumEditionType.deluxe,
      now: now,
    );

    await editions.setPrimary(editionId: deluxe.id, now: now);

    final all = await editionsOf(album);
    expect(all.where((e) => e.isPrimary).map((e) => e.id), [deluxe.id]);
    expect(all.firstWhere((e) => e.id == standard).isPrimary, isFalse);
  });

  group('removing a track', () {
    test('keeps the song and its other listings', () async {
      final (album, standard, songs) = await standardAlbum();
      final deluxe = await editions.createEdition(
        albumId: album,
        title: 'locket (Deluxe)',
        type: AlbumEditionType.deluxe,
        now: now,
      );
      await editions.assignTracks(
        editionId: deluxe.id,
        songIds: [songs['One']!],
        now: now,
      );

      await editions.removeTrack(
        editionId: deluxe.id,
        songId: songs['One']!,
        now: now,
      );

      expect(await listedOn(deluxe.id), isEmpty);
      expect(await listedOn(standard), contains(songs['One']));
      final db = await appDatabase.database;
      expect(await SongDao(db).findById(songs['One']!), isNotNull);
    });

    test('from its home edition moves the home, keeping the song', () async {
      final (album, standard, songs) = await standardAlbum();
      final deluxe = await editions.createEdition(
        albumId: album,
        title: 'locket (Deluxe)',
        type: AlbumEditionType.deluxe,
        now: now,
      );
      await editions.assignTracks(
        editionId: deluxe.id,
        songIds: [songs['One']!],
        now: now,
      );

      await editions.removeTrack(
        editionId: standard,
        songId: songs['One']!,
        now: now,
      );

      final db = await appDatabase.database;
      expect(
        (await SongDao(db).findById(songs['One']!))!.albumEditionId,
        deluxe.id,
      );
    });

    test('never removes a song from its last edition', () async {
      final (_, standard, songs) = await standardAlbum();

      await expectLater(
        editions.removeTrack(editionId: standard, songId: songs['One']!),
        refused(AlbumEditionRefusal.lastEditionOfSong),
      );
      expect(await listedOn(standard), contains(songs['One']));
    });

    test('SN-50 A-Q26: Choose songs never orphans a song on its last '
        'edition', () async {
      final (_, standard, songs) = await standardAlbum();

      final result = await editions.updateTrackList(
        editionId: standard,
        remove: [songs['One']!, songs['Two']!],
        now: now,
      );

      expect(result.removed, 0);
      expect(result.keptAsLastListing, 2);
      expect(await listedOn(standard), [
        songs['One'],
        songs['Two'],
        songs['Three'],
      ]);
      final db = await appDatabase.database;
      expect(
        (await SongDao(db).findById(songs['One']!))!.albumEditionId,
        standard,
      );
    });

    test('SN-50 A-Q26: once on another edition, the last listing can '
        'go', () async {
      final (album, standard, songs) = await standardAlbum();
      final deluxe = await editions.createEdition(
        albumId: album,
        title: 'locket (Deluxe)',
        type: AlbumEditionType.deluxe,
        now: now,
      );

      await expectLater(
        editions.removeTrack(editionId: standard, songId: songs['One']!),
        refused(AlbumEditionRefusal.lastEditionOfSong),
      );
      await editions.updateTrackList(
        editionId: deluxe.id,
        add: [songs['One']!],
        now: now,
      );
      final result = await editions.updateTrackList(
        editionId: standard,
        remove: [songs['One']!],
        now: now,
      );

      expect(result.removed, 1);
      expect(result.keptAsLastListing, 0);
      expect(await listedOn(deluxe.id), [songs['One']]);
      final db = await appDatabase.database;
      expect(
        (await SongDao(db).findById(songs['One']!))!.albumEditionId,
        deluxe.id,
      );
    });
  });

  group('deleting an edition', () {
    test('works for an empty, non-primary edition', () async {
      final (album, _, _) = await standardAlbum();
      final extra = await editions.createEdition(
        albumId: album,
        title: 'Empty',
        type: AlbumEditionType.other,
        now: now,
      );

      await editions.deleteEdition(editionId: extra.id);

      expect(
        (await editionsOf(album)).map((e) => e.id),
        isNot(contains(extra.id)),
      );
    });

    test('SN-50 A-Q24: never the only edition, even primary with no '
        'replacement', () async {
      final (album, standard, _) = await standardAlbum();

      await expectLater(
        editions.deleteEdition(editionId: standard),
        refused(AlbumEditionRefusal.onlyEdition),
      );
      expect((await editionsOf(album)).single.id, standard);
    });

    /// A Deluxe built on Standard (every Standard song), plus [bonus]
    /// songs imported straight onto Deluxe as their home.
    Future<(String, String, AlbumEdition, Map<String, String>)> withDeluxe({
      List<String> bonus = const [],
    }) async {
      final (album, standard, songs) = await standardAlbum();
      final deluxe = await editions.createEdition(
        albumId: album,
        title: 'Harbor Lights (Deluxe)',
        type: AlbumEditionType.deluxe,
        includeSongsFrom: standard,
        now: now,
      );
      final db = await appDatabase.database;
      for (final (i, title) in bonus.indexed) {
        final id = 'song-bonus-$i';
        final template = (await db.query(
          DatabaseTables.songs,
          where: 'id = ?',
          whereArgs: [songs['One']],
        )).single;
        await db.insert(DatabaseTables.songs, {
          ...template,
          'id': id,
          'title': title,
          'canonical_title': title.toLowerCase(),
          'album_edition_id': deluxe.id,
          'track_number': 4 + i,
        });
        await db.insert(DatabaseTables.albumEditionTracks, {
          'album_edition_id': deluxe.id,
          'song_id': id,
          'disc_number': 1,
          'track_number': 4 + i,
          'sort_position': 3 + i,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
        songs[title] = id;
      }
      return (album, standard, deluxe, songs);
    }

    Future<String> homeOf(String songId) async {
      final db = await appDatabase.database;
      return (await SongDao(db).findById(songId))!.albumEditionId;
    }

    test('SN-50 A-Q15/A-Q25: songs only on the edition block it, with '
        'their count, and nothing changes', () async {
      final (album, _, deluxe, songs) = await withDeluxe(
        bonus: ['Bonus A', 'Bonus B'],
      );
      final listedBefore = await listedOn(deluxe.id);

      await expectLater(
        editions.deleteEdition(editionId: deluxe.id),
        throwsA(
          isA<AlbumEditionManagementException>()
              .having(
                (e) => e.refusal,
                'refusal',
                AlbumEditionRefusal.exclusiveSongs,
              )
              .having((e) => e.songCount, 'songCount', 2),
        ),
      );
      expect(await listedOn(deluxe.id), listedBefore);
      expect(await editionsOf(album), hasLength(2));
      expect(await homeOf(songs['Bonus A']!), deluxe.id);
    });

    test('SN-50 A5: a non-primary edition whose songs are all elsewhere '
        'goes, and songs it was home to move to the primary', () async {
      final (album, standard, deluxe, songs) = await withDeluxe();
      // One is homed on Deluxe but still listed on Standard.
      final db = await appDatabase.database;
      await db.update(
        DatabaseTables.songs,
        {'album_edition_id': deluxe.id},
        where: 'id = ?',
        whereArgs: [songs['One']],
      );
      final songsBefore = (await SongDao(db).findAll()).map((s) => s.id);

      await editions.deleteEdition(editionId: deluxe.id, now: now);

      expect((await editionsOf(album)).map((e) => e.id), [standard]);
      expect(await homeOf(songs['One']!), standard);
      expect(await listedOn(standard), hasLength(3));
      expect(
        (await SongDao(db).findAll()).map((s) => s.id),
        unorderedEquals(songsBefore),
      );
    });

    test('SN-50 A-Q23: the primary edition needs a replacement', () async {
      final (album, standard, deluxe, _) = await withDeluxe();

      await expectLater(
        editions.deleteEdition(editionId: standard),
        refused(AlbumEditionRefusal.primaryEdition),
      );
      await expectLater(
        editions.deleteEdition(
          editionId: standard,
          replacementPrimaryId: standard,
        ),
        refused(AlbumEditionRefusal.primaryEdition),
        reason: 'it cannot replace itself',
      );
      await expectLater(
        editions.deleteEdition(
          editionId: standard,
          replacementPrimaryId: 'edition-elsewhere',
        ),
        refused(AlbumEditionRefusal.primaryEdition),
      );
      final after = await editionsOf(album);
      expect(after, hasLength(2));
      expect(after.singleWhere((e) => e.isPrimary).id, standard);
      expect(deluxe.isPrimary, isFalse);
    });

    test('SN-50 A-Q23: with a replacement, the primary edition goes and '
        'its songs move home to the new primary in one step', () async {
      final (album, standard, deluxe, songs) = await withDeluxe(
        bonus: ['Bonus A'],
      );

      await editions.deleteEdition(
        editionId: standard,
        replacementPrimaryId: deluxe.id,
        now: now,
      );

      final after = await editionsOf(album);
      expect(after.single.id, deluxe.id);
      expect(after.single.isPrimary, isTrue);
      for (final title in ['One', 'Two', 'Three', 'Bonus A']) {
        expect(await homeOf(songs[title]!), deluxe.id, reason: title);
      }
      expect(await listedOn(deluxe.id), hasLength(4));
    });

    test('SN-50 A-Q26: a primary with songs only on it is refused even '
        'with a replacement, and stays primary', () async {
      final (album, standard, songs) = await standardAlbum();
      final extra = await editions.createEdition(
        albumId: album,
        title: 'Harbor Lights (Sped Up)',
        type: AlbumEditionType.other,
        now: now,
      );
      await editions.assignTracks(
        editionId: extra.id,
        songIds: [songs['One']!],
        now: now,
      );

      await expectLater(
        editions.deleteEdition(
          editionId: standard,
          replacementPrimaryId: extra.id,
        ),
        throwsA(
          isA<AlbumEditionManagementException>()
              .having(
                (e) => e.refusal,
                'refusal',
                AlbumEditionRefusal.exclusiveSongs,
              )
              .having((e) => e.songCount, 'songCount', 2),
        ),
      );
      expect(
        (await editionsOf(album)).singleWhere((e) => e.isPrimary).id,
        standard,
      );
    });

    test('SN-50 A-Q16: a primary edition already in the cloud is refused; '
        'deletes stay queued as before', () async {
      final (album, standard, deluxe, _) = await withDeluxe();
      final db = await appDatabase.database;
      await CloudRevisionBaselineDao(db).saveObservedRevision(
        userId: 'user-1',
        entityType: CloudDataEntity.albumEdition,
        entityId: standard,
        serverRevision: 3,
      );

      await expectLater(
        editions.deleteEdition(
          editionId: standard,
          replacementPrimaryId: deluxe.id,
          userId: 'user-1',
        ),
        refused(AlbumEditionRefusal.primaryInCloud),
      );
      expect(await editionsOf(album), hasLength(2));

      // A non-primary edition is deleted and queued exactly as before.
      await editions.deleteEdition(
        editionId: deluxe.id,
        userId: 'user-1',
        now: now,
      );
      final queued = await db.query(
        DatabaseTables.syncOutbox,
        where: 'user_id = ? AND entity_id = ?',
        whereArgs: ['user-1', deluxe.id],
      );
      expect(queued.single['operation'], 'delete');
    });

    test('SN-50 A-Q16: signed out, a primary edition another account on '
        'this device synced is refused', () async {
      final (album, standard, deluxe, _) = await withDeluxe();
      final db = await appDatabase.database;
      await CloudRevisionBaselineDao(db).saveObservedRevision(
        userId: 'user-1',
        entityType: CloudDataEntity.albumEdition,
        entityId: standard,
        serverRevision: 2,
      );

      for (final signedOut in [null, '', '  ']) {
        await expectLater(
          editions.deleteEdition(
            editionId: standard,
            replacementPrimaryId: deluxe.id,
            userId: signedOut,
          ),
          refused(AlbumEditionRefusal.primaryInCloud),
          reason: 'userId: "$signedOut"',
        );
      }
      final after = await editionsOf(album);
      expect(after, hasLength(2));
      expect(after.singleWhere((e) => e.isPrimary).id, standard);
    });

    test('SN-50 A-Q16: signed out, a primary edition no account synced is '
        'deleted as before', () async {
      final (album, standard, deluxe, _) = await withDeluxe();
      final db = await appDatabase.database;
      // A baseline for a different edition, and one for a song with the
      // same id, do not count.
      await CloudRevisionBaselineDao(db).saveObservedRevision(
        userId: 'user-1',
        entityType: CloudDataEntity.albumEdition,
        entityId: deluxe.id,
        serverRevision: 1,
      );
      await CloudRevisionBaselineDao(db).saveObservedRevision(
        userId: 'user-1',
        entityType: CloudDataEntity.song,
        entityId: standard,
        serverRevision: 1,
      );

      await editions.deleteEdition(
        editionId: standard,
        replacementPrimaryId: deluxe.id,
        now: now,
      );

      final after = await editionsOf(album);
      expect(after.single.id, deluxe.id);
      expect(after.single.isPrimary, isTrue);
    });
  });

  test('a failure part-way leaves nothing changed', () async {
    final (album, _, songs) = await standardAlbum();
    final deluxe = await editions.createEdition(
      albumId: album,
      title: 'locket (Deluxe)',
      type: AlbumEditionType.deluxe,
      now: now,
    );

    // The second id is not a song of this album, so the whole assignment
    // is refused, including the first song.
    await expectLater(
      editions.assignTracks(
        editionId: deluxe.id,
        songIds: [songs['One']!, 'song-elsewhere'],
      ),
      refused(AlbumEditionRefusal.songNotOnAlbum),
    );
    expect(await listedOn(deluxe.id), isEmpty);
  });

  test('edition changes are queued for sync', () async {
    final (album, _, _) = await standardAlbum();
    final db = await appDatabase.database;
    final before = (await db.query(DatabaseTables.syncOutbox)).length;

    await editions.createEdition(
      albumId: album,
      title: 'locket (Deluxe)',
      type: AlbumEditionType.deluxe,
      userId: 'user-1',
      now: now,
    );

    final rows = await db.query(DatabaseTables.syncOutbox);
    expect(rows.length, before + 1);
    expect(rows.last['entity_type'], 'albumEdition');
  });

  test(
    'every edition listing change queues the song for sync (SN-45)',
    () async {
      final (album, standard, songs) = await standardAlbum();
      final db = await appDatabase.database;

      Future<Set<String>> queuedSongs() async => {
        for (final row in await db.query(
          DatabaseTables.syncOutbox,
          where: 'entity_type = ? AND user_id = ?',
          whereArgs: ['song', 'user-1'],
        ))
          row['entity_id']! as String,
      };

      final deluxe = await editions.createEdition(
        albumId: album,
        title: 'Deluxe',
        type: AlbumEditionType.deluxe,
        includeSongsFrom: standard,
        userId: 'user-1',
        now: now,
      );
      expect(await queuedSongs(), songs.values.toSet(), reason: 'inherited');

      await db.delete(DatabaseTables.syncOutbox);
      final bonus = await editions.createEdition(
        albumId: album,
        title: 'Bonus',
        type: AlbumEditionType.other,
        userId: 'user-1',
        now: now,
      );
      await db.delete(DatabaseTables.syncOutbox);
      await editions.assignTracks(
        editionId: bonus.id,
        songIds: [songs['Two']!],
        userId: 'user-1',
        now: now,
      );
      expect(await queuedSongs(), {songs['Two']}, reason: 'assigned');

      await db.delete(DatabaseTables.syncOutbox);
      await editions.removeTrack(
        editionId: deluxe.id,
        songId: songs['One']!,
        userId: 'user-1',
        now: now,
      );
      expect(
        await queuedSongs(),
        songs.values.toSet(),
        reason: 'removed elsewhere; the songs after it were renumbered',
      );
    },
  );

  group('SN-50 Session A', () {
    /// Imports a made-up release, one song per (disc, track, title), all on
    /// its Standard edition. Returns (albumId, standardId, songIds).
    Future<(String, String, Map<String, String>)> release(
      List<(int, int, String)> tracks,
    ) async {
      final importer = AtomicLibraryImporter(appDatabase: appDatabase);
      final ids = <String, String>{};

      for (final (disc, n, title) in tracks) {
        final path = 'Vela Morrow/Paper Harbor/$disc-$n $title.mp3';
        final result = await importer.import(
          candidate: ImportCandidate(
            filePath: path,
            normalizedPath: path.toLowerCase(),
            discoveredAt: now,
          ),
          metadata: AudioMetadata(
            title: title,
            artistName: 'Vela Morrow',
            albumTitle: 'Paper Harbor',
            durationSeconds: 180,
            trackNumber: n,
            discNumber: disc,
            isSingle: false,
            featuredArtists: const [],
          ),
          now: now,
        );
        ids[title] = result.songId!;
      }

      final db = await appDatabase.database;
      final song = await SongDao(db).findById(ids.values.first);
      return (song!.albumId, song.albumEditionId, ids);
    }

    /// (disc, track) of each listing, in stored order by disc and track.
    Future<Map<String, (int, int)>> numbering(String editionId) async {
      final db = await appDatabase.database;
      return {
        for (final m in await AlbumEditionTrackDao(
          db,
        ).findByEditionId(editionId))
          m.songId: (m.discNumber, m.trackNumber),
      };
    }

    Future<void> markManual(String editionId, String songId) async {
      final db = await appDatabase.database;
      await db.update(
        DatabaseTables.albumEditionTracks,
        {'numbering_authority': 'manual'},
        where: 'album_edition_id = ? AND song_id = ?',
        whereArgs: [editionId, songId],
      );
    }

    final six = [
      for (final (n, title) in [
        (1, 'Lantern'),
        (2, 'Tidewater'),
        (3, 'Quiet Pier'),
        (4, 'Salt Lines'),
        (5, 'Gull Song'),
        (6, 'Last Ferry'),
      ])
        (1, n, title),
    ];

    test(
      'A3: removing the first songs numbers the rest from 1 (defect #9)',
      () async {
        final (album, standard, songs) = await release(six);
        final deluxe = await editions.createEdition(
          albumId: album,
          title: 'Paper Harbor (Deluxe)',
          type: AlbumEditionType.deluxe,
          includeSongsFrom: standard,
          now: now,
        );

        final result = await editions.updateTrackList(
          editionId: standard,
          remove: [songs['Lantern']!, songs['Tidewater']!],
          now: now,
        );

        expect(result.removed, 2);
        expect(result.renumbering.renumbered, 4);
        expect(result.renumbering.manualNumbersKept, 0);
        expect(await numbering(standard), {
          songs['Quiet Pier']: (1, 1),
          songs['Salt Lines']: (1, 2),
          songs['Gull Song']: (1, 3),
          songs['Last Ferry']: (1, 4),
        });
        // Deluxe keeps its own numbers.
        expect((await numbering(deluxe.id))[songs['Lantern']], (1, 1));
        expect((await numbering(deluxe.id))[songs['Last Ferry']], (1, 6));

        // The song's own copy follows its home (Standard) listing.
        final db = await appDatabase.database;
        final pier = (await SongDao(db).findById(songs['Quiet Pier']!))!;
        expect(pier.albumEditionId, standard);
        expect(pier.trackNumber, 1);
      },
    );

    test(
      'removing one track renumbers the edition it was removed from',
      () async {
        final (album, standard, songs) = await release(six);
        final deluxe = await editions.createEdition(
          albumId: album,
          title: 'Paper Harbor (Deluxe)',
          type: AlbumEditionType.deluxe,
          includeSongsFrom: standard,
          now: now,
        );

        await editions.removeTrack(
          editionId: deluxe.id,
          songId: songs['Salt Lines']!,
          now: now,
        );

        final deluxeNumbers = await numbering(deluxe.id);
        expect(deluxeNumbers[songs['Gull Song']], (1, 4));
        expect(deluxeNumbers[songs['Last Ferry']], (1, 5));
        expect((await numbering(standard))[songs['Last Ferry']], (1, 6));
      },
    );

    test('each disc counts from 1', () async {
      final (album, standard, songs) = await release([
        (1, 1, 'Lantern'),
        (1, 2, 'Tidewater'),
        (2, 1, 'Quiet Pier'),
        (2, 2, 'Salt Lines'),
        (2, 3, 'Gull Song'),
      ]);
      await editions.createEdition(
        albumId: album,
        title: 'Paper Harbor (Deluxe)',
        type: AlbumEditionType.deluxe,
        includeSongsFrom: standard,
        now: now,
      );

      await editions.updateTrackList(
        editionId: standard,
        remove: [songs['Tidewater']!, songs['Quiet Pier']!],
        now: now,
      );

      expect(await numbering(standard), {
        songs['Lantern']: (1, 1),
        songs['Salt Lines']: (2, 1),
        songs['Gull Song']: (2, 2),
      });
    });

    test('hand-set numbers are kept and reported, then changed only when '
        'approved', () async {
      final (album, standard, songs) = await release(six);
      await editions.createEdition(
        albumId: album,
        title: 'Paper Harbor (Deluxe)',
        type: AlbumEditionType.deluxe,
        includeSongsFrom: standard,
        now: now,
      );
      await markManual(standard, songs['Gull Song']!);

      final result = await editions.updateTrackList(
        editionId: standard,
        remove: [songs['Lantern']!],
        now: now,
      );

      expect(result.renumbering.manualNumbersKept, 1);
      expect(await numbering(standard), {
        songs['Tidewater']: (1, 1),
        songs['Quiet Pier']: (1, 2),
        songs['Salt Lines']: (1, 3),
        songs['Gull Song']: (1, 5),
        songs['Last Ferry']: (1, 5),
      });

      final approved = await editions.renumberEdition(
        editionId: standard,
        overwriteManual: true,
        now: now,
      );

      expect(approved.manualNumbersKept, 0);
      expect((await numbering(standard))[songs['Gull Song']], (1, 4));
      expect((await numbering(standard))[songs['Last Ferry']], (1, 5));
    });

    test(
      'a bonus song added to Standard is numbered after its songs',
      () async {
        final (album, standard, songs) = await release(six);
        final deluxe = await editions.createEdition(
          albumId: album,
          title: 'Paper Harbor (Deluxe)',
          type: AlbumEditionType.deluxe,
          includeSongsFrom: standard,
          now: now,
        );
        await editions.updateTrackList(
          editionId: standard,
          remove: [songs['Gull Song']!, songs['Last Ferry']!],
          now: now,
        );

        // Last Ferry is track 6 on Deluxe; on Standard it becomes 5.
        final added = await editions.assignTracks(
          editionId: standard,
          songIds: [songs['Last Ferry']!],
          now: now,
        );

        expect(added, 1);
        expect((await numbering(standard))[songs['Last Ferry']], (1, 5));
        expect((await numbering(deluxe.id))[songs['Last Ferry']], (1, 6));
      },
    );

    test('a repair listing never renumbers the edition', () async {
      final (album, standard, songs) = await release(six);
      final deluxe = await editions.createEdition(
        albumId: album,
        title: 'Paper Harbor (Deluxe)',
        type: AlbumEditionType.deluxe,
        now: now,
      );

      await editions.assignTracks(
        editionId: deluxe.id,
        songIds: [songs['Last Ferry']!],
        renumber: false,
        now: now,
      );

      expect(await numbering(deluxe.id), {songs['Last Ferry']: (1, 6)});
      expect((await numbering(standard))[songs['Last Ferry']], (1, 6));
    });

    test('Choose songs is one change: a last listing is kept, the rest '
        'apply', () async {
      final (album, standard, songs) = await release(six);
      final deluxe = await editions.createEdition(
        albumId: album,
        title: 'Paper Harbor (Deluxe)',
        type: AlbumEditionType.deluxe,
        now: now,
      );
      await editions.assignTracks(
        editionId: deluxe.id,
        songIds: [songs['Lantern']!],
        now: now,
      );

      final result = await editions.updateTrackList(
        editionId: standard,
        // Tidewater is only on Standard, so it stays.
        remove: [songs['Lantern']!, songs['Tidewater']!],
        now: now,
      );

      expect(result.removed, 1);
      expect(result.keptAsLastListing, 1);
      expect((await numbering(standard))[songs['Tidewater']], (1, 1));
    });

    test('renumbered songs are queued for sync', () async {
      final (album, standard, songs) = await release(six);
      await editions.createEdition(
        albumId: album,
        title: 'Paper Harbor (Deluxe)',
        type: AlbumEditionType.deluxe,
        includeSongsFrom: standard,
        now: now,
      );
      final db = await appDatabase.database;
      await db.delete(DatabaseTables.syncOutbox);

      await editions.updateTrackList(
        editionId: standard,
        remove: [songs['Salt Lines']!],
        userId: 'user-1',
        now: now,
      );

      final queued = {
        for (final row in await db.query(
          DatabaseTables.syncOutbox,
          where: 'entity_type = ?',
          whereArgs: ['song'],
        ))
          row['entity_id']! as String,
      };
      expect(queued, {
        songs['Salt Lines'],
        songs['Gull Song'],
        songs['Last Ferry'],
      });
    });

    test('A2: a new edition copies listings but never the date, cover or '
        'genre', () async {
      final (album, standard, songs) = await release(six);
      final db = await appDatabase.database;
      await db.insert(DatabaseTables.artworkAssets, {
        'id': 'art-1',
        'file_path': '/covers/paper-harbor.jpg',
        'normalized_path': '/covers/paper-harbor.jpg',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.update(
        DatabaseTables.albumEditions,
        {
          'release_date': DateTime.utc(2024, 4, 1).toIso8601String(),
          'release_date_precision': 'day',
          'genre': 'Dream Pop',
          'artwork_id': 'art-1',
        },
        where: 'id = ?',
        whereArgs: [standard],
      );

      final deluxe = await editions.createEdition(
        albumId: album,
        title: 'Deluxe',
        type: AlbumEditionType.deluxe,
        includeSongsFrom: standard,
        now: now,
      );

      final stored = (await editionsOf(
        album,
      )).firstWhere((e) => e.id == deluxe.id);
      expect(stored.releaseDate, isNull);
      expect(stored.releaseDatePrecision, isNull);
      expect(stored.artworkId, isNull);
      expect(stored.genre, isNull);
      expect(await listedOn(deluxe.id), await listedOn(standard));
    });
  });
}
