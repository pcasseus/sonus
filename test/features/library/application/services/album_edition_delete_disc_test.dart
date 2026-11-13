// App Update 1.2, PATCH-02 and PATCH-03: deleting a disc and moving
// several songs between discs in Release Studio. Disposable file database;
// fictional songs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/album_edition_track_ordering_service.dart';
import 'package:sonus_next/features/library/application/services/edition_disc_layout.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_edition_disc_label_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_disc_label.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/recovery/application/services/backup_archive_verifier.dart';
import 'package:sonus_next/features/recovery/application/services/sqlite_restore_executor.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

import '../../../../support/recovery_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory root;
  late AppDatabase appDatabase;
  late AlbumEditionTrackOrderingService service;
  late AlbumEdition standard;
  late AlbumEdition deluxe;
  late Map<String, Song> songs;

  final created = DateTime.utc(2026, 11, 1);
  final now = DateTime.utc(2026, 11, 13, 9);

  // Standard: Disc 1 "Main" A B, Disc 2 "Bonus" C D, Disc 3 "Live" E F.
  // C is also on Deluxe.
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sonus_delete_disc_');
    appDatabase = fileAppDatabase(root, 'library.db');
    var outbox = 0;
    service = AlbumEditionTrackOrderingService(
      mutationRunner: SyncMutationTransactionRunner(
        appDatabase: appDatabase,
        generateId: () => 'outbox_${++outbox}',
        now: () => now,
      ),
    );

    final db = await appDatabase.database;
    final artist = EntityFactory.createArtist(name: 'Nova', now: created);
    final album = EntityFactory.createAlbum(
      artistId: artist.id,
      title: 'First Light',
      now: created,
    );
    standard = EntityFactory.createAlbumEdition(
      albumId: album.id,
      title: 'Standard',
      isPrimary: true,
      now: created,
    );
    deluxe = EntityFactory.createAlbumEdition(
      albumId: album.id,
      title: 'Deluxe',
      type: AlbumEditionType.deluxe,
      isPrimary: false,
      now: created,
    );
    await ArtistDao(db).insert(artist);
    await AlbumDao(db).insert(album);
    await AlbumEditionDao(db).insert(standard);
    await AlbumEditionDao(db).insert(deluxe);

    songs = {};
    const layout = [('A', 1), ('B', 1), ('C', 2), ('D', 2), ('E', 3), ('F', 3)];
    final numberOnDisc = <int, int>{};
    for (final (index, (title, disc)) in layout.indexed) {
      final number = numberOnDisc.update(disc, (n) => n + 1, ifAbsent: () => 1);
      final song = EntityFactory.createSong(
        artistId: artist.id,
        albumId: album.id,
        albumEditionId: standard.id,
        title: title,
        discNumber: disc,
        trackNumber: number,
        durationSeconds: 180,
        isSingle: false,
        now: created,
      );
      songs[title] = song;
      await SongDao(db).insert(song);
      await AlbumEditionTrackDao(db).insert(
        AlbumEditionTrack(
          albumEditionId: standard.id,
          songId: song.id,
          discNumber: disc,
          trackNumber: number,
          sortPosition: index,
          createdAt: created,
          updatedAt: created,
        ),
      );
    }
    await AlbumEditionTrackDao(db).insert(
      AlbumEditionTrack(
        albumEditionId: deluxe.id,
        songId: songs['C']!.id,
        discNumber: 1,
        trackNumber: 5,
        sortPosition: 4,
        createdAt: created,
        updatedAt: created,
      ),
    );
    final labels = SqliteAlbumEditionDiscLabelRepository(db);
    for (final (disc, name) in [(1, 'Main'), (2, 'Bonus'), (3, 'Live')]) {
      await labels.save(
        AlbumEditionDiscLabel(
          albumEditionId: standard.id,
          discNumber: disc,
          label: name,
          createdAt: created,
          updatedAt: created,
        ),
      );
    }
  });

  tearDown(() async {
    await appDatabase.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// Standard as shown: each song in order, on its disc.
  Future<List<EditionPlacement>> shown() async {
    final db = await appDatabase.database;
    final ids = {for (final e in songs.entries) e.value.id: e.key};
    return [
      for (final r in await db.query(
        DatabaseTables.albumEditionTracks,
        where: 'album_edition_id = ?',
        whereArgs: [standard.id],
        orderBy: 'sort_position',
      ))
        if (ids.containsKey(r['song_id']))
          EditionPlacement(
            songId: r['song_id']! as String,
            discNumber: r['disc_number']! as int,
          ),
    ];
  }

  /// Title, disc and number of each listing of [edition], in order.
  Future<List<(String, int, int)>> listing(AlbumEdition edition) async {
    final db = await appDatabase.database;
    final rows = await db.rawQuery(
      'SELECT s.title, t.disc_number, t.track_number '
      'FROM ${DatabaseTables.albumEditionTracks} t '
      'JOIN ${DatabaseTables.songs} s ON s.id = t.song_id '
      'WHERE t.album_edition_id = ? ORDER BY t.sort_position',
      [edition.id],
    );
    return [
      for (final r in rows)
        (
          r['title']! as String,
          r['disc_number']! as int,
          r['track_number']! as int,
        ),
    ];
  }

  Future<Map<int, String>> labels() async => {
    for (final l in await SqliteAlbumEditionDiscLabelRepository(
      await appDatabase.database,
    ).getByEditionId(standard.id))
      l.discNumber: l.label,
  };

  /// Every row of every table except those a disc change may write.
  Future<Map<String, List<Map<String, Object?>>>> untouchedTables() async {
    final db = await appDatabase.database;
    const written = {
      DatabaseTables.songs,
      DatabaseTables.albumEditionTracks,
      DatabaseTables.albumEditionDiscLabels,
      DatabaseTables.syncOutbox,
    };
    final tables = [
      for (final r in await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      ))
        r['name']! as String,
    ];
    return {
      for (final table in tables)
        if (!written.contains(table))
          table: await db.query(table, orderBy: 'rowid'),
    };
  }

  String id(String title) => songs[title]!.id;

  group('deleting a disc', () {
    test('moving its songs: they follow the destination disc in order, '
        'later discs move down one and keep their names', () async {
      final before = await untouchedTables();

      final result = await service.deleteDisc(
        albumEditionId: standard.id,
        discNumber: 2,
        placements: afterDeletingDisc(await shown(), 2, moveTo: 1),
        now: now,
      );

      expect(result.moved, 2);
      expect(result.removed, 0);
      expect(await listing(standard), [
        ('A', 1, 1),
        ('B', 1, 2),
        ('C', 1, 3),
        ('D', 1, 4),
        ('E', 2, 1),
        ('F', 2, 2),
      ]);
      expect(await labels(), {1: 'Main', 2: 'Live'});
      final db = await appDatabase.database;
      final e = (await SongDao(db).findById(id('E')))!;
      expect((e.discNumber, e.trackNumber), (2, 1));
      // Deluxe's own listing of C is untouched.
      expect(await listing(deluxe), [('C', 1, 5)]);
      expect(await untouchedTables(), before);
    });

    test('deleting an unnamed disc: a later name follows its disc', () async {
      final db = await appDatabase.database;
      await SqliteAlbumEditionDiscLabelRepository(
        db,
      ).delete(editionId: standard.id, discNumber: 2);

      await service.deleteDisc(
        albumEditionId: standard.id,
        discNumber: 2,
        placements: afterDeletingDisc(await shown(), 2, moveTo: 1),
      );

      // Same number of names as before, but Live is now Disc 2's.
      expect(await labels(), {1: 'Main', 2: 'Live'});
    });

    test('a moved name keeps the date it was first given', () async {
      await service.deleteDisc(
        albumEditionId: standard.id,
        discNumber: 1,
        placements: afterDeletingDisc(await shown(), 1, moveTo: 2),
        now: now,
      );

      final stored = await SqliteAlbumEditionDiscLabelRepository(
        await appDatabase.database,
      ).getByEditionId(standard.id);
      expect(
        {for (final l in stored) l.discNumber: l.label},
        {1: 'Bonus', 2: 'Live'},
      );
      expect(stored.every((l) => l.createdAt == created), isTrue);
      expect(await listing(standard), [
        ('C', 1, 1),
        ('D', 1, 2),
        ('A', 1, 3),
        ('B', 1, 4),
        ('E', 2, 1),
        ('F', 2, 2),
      ]);
    });

    test('removing its songs from the edition keeps the songs, their home '
        'moving to an edition that still lists them', () async {
      final db = await appDatabase.database;
      // D is on Deluxe too, so both songs of Disc 2 may leave Standard.
      await AlbumEditionTrackDao(db).insert(
        AlbumEditionTrack(
          albumEditionId: deluxe.id,
          songId: id('D'),
          discNumber: 1,
          trackNumber: 6,
          sortPosition: 5,
          createdAt: created,
          updatedAt: created,
        ),
      );
      final songIds = {
        for (final r in await db.query(DatabaseTables.songs)) r['id'],
      };
      final before = await untouchedTables();

      final result = await service.deleteDisc(
        albumEditionId: standard.id,
        discNumber: 2,
        placements: afterDeletingDisc(await shown(), 2),
        removeSongIds: {id('C'), id('D')},
        now: now,
      );

      expect(result.removed, 2);
      expect(await listing(standard), [
        ('A', 1, 1),
        ('B', 1, 2),
        ('E', 2, 1),
        ('F', 2, 2),
      ]);
      expect(await listing(deluxe), [('C', 1, 5), ('D', 1, 6)]);
      expect({
        for (final r in await db.query(DatabaseTables.songs)) r['id'],
      }, songIds);
      final c = (await SongDao(db).findById(id('C')))!;
      expect(c.albumEditionId, deluxe.id);
      expect((c.discNumber, c.trackNumber), (1, 5));
      expect(await labels(), {1: 'Main', 2: 'Live'});
      expect(await untouchedTables(), before);
    });

    test('songs on no other edition cannot leave it: refused, nothing '
        'changed', () async {
      final listingBefore = await listing(standard);
      final db = await appDatabase.database;
      final outbox = await db.query(DatabaseTables.syncOutbox);

      await expectLater(
        service.deleteDisc(
          albumEditionId: standard.id,
          discNumber: 2,
          placements: afterDeletingDisc(await shown(), 2),
          removeSongIds: {id('C'), id('D')},
        ),
        throwsA(
          isA<DiscDeletionException>()
              .having(
                (e) => e.refusal,
                'refusal',
                DiscDeletionRefusal.songsOnlyOnThisEdition,
              )
              .having((e) => e.songCount, 'songCount', 1),
        ),
      );

      expect(await listing(standard), listingBefore);
      expect(await labels(), {1: 'Main', 2: 'Bonus', 3: 'Live'});
      expect(await db.query(DatabaseTables.syncOutbox), outbox);
    });

    test('an edition is never left without songs', () async {
      await expectLater(
        service.deleteDisc(
          albumEditionId: standard.id,
          discNumber: 1,
          placements: const [],
          removeSongIds: {for (final s in songs.values) s.id},
        ),
        throwsA(
          isA<DiscDeletionException>().having(
            (e) => e.refusal,
            'refusal',
            DiscDeletionRefusal.editionWouldBeEmpty,
          ),
        ),
      );
      expect(await listing(standard), hasLength(6));
    });

    test('a song to remove must be on that disc', () async {
      await expectLater(
        service.deleteDisc(
          albumEditionId: standard.id,
          discNumber: 2,
          placements: [
            for (final p in await shown())
              if (p.songId != id('A')) p,
          ],
          removeSongIds: {id('A')},
        ),
        throwsA(
          isA<DiscDeletionException>().having(
            (e) => e.refusal,
            'refusal',
            DiscDeletionRefusal.notOnDisc,
          ),
        ),
      );
    });

    test('all or nothing: a failure after the removals undoes them', () async {
      final db = await appDatabase.database;
      await AlbumEditionTrackDao(db).insert(
        AlbumEditionTrack(
          albumEditionId: deluxe.id,
          songId: id('D'),
          discNumber: 1,
          trackNumber: 6,
          sortPosition: 5,
          createdAt: created,
          updatedAt: created,
        ),
      );
      final listingBefore = await listing(standard);
      final songsBefore = await db.query(DatabaseTables.songs, orderBy: 'id');
      // F is missing from the layout, so the arrangement fails after C and
      // D have already been removed inside the transaction.
      final incomplete = [
        for (final p in afterDeletingDisc(await shown(), 2))
          if (p.songId != id('F')) p,
      ];

      await expectLater(
        service.deleteDisc(
          albumEditionId: standard.id,
          discNumber: 2,
          placements: incomplete,
          removeSongIds: {id('C'), id('D')},
        ),
        throwsStateError,
      );

      expect(await listing(standard), listingBefore);
      expect(await db.query(DatabaseTables.songs, orderBy: 'id'), songsBefore);
      expect(await labels(), {1: 'Main', 2: 'Bonus', 3: 'Live'});
    });

    test(
      'an empty named disc goes with its name; nothing else moves',
      () async {
        final db = await appDatabase.database;
        await SqliteAlbumEditionDiscLabelRepository(db).save(
          AlbumEditionDiscLabel(
            albumEditionId: standard.id,
            discNumber: 4,
            label: 'Extras',
            createdAt: created,
            updatedAt: created,
          ),
        );
        final listingBefore = await listing(standard);

        final result = await service.deleteDisc(
          albumEditionId: standard.id,
          discNumber: 4,
          placements: afterDeletingDisc(await shown(), 4),
        );

        expect(result.changed, isTrue);
        expect(await listing(standard), listingBefore);
        expect(await labels(), {1: 'Main', 2: 'Bonus', 3: 'Live'});
      },
    );

    test('the changed songs are queued for sync', () async {
      final db = await appDatabase.database;
      await service.deleteDisc(
        albumEditionId: standard.id,
        discNumber: 2,
        placements: afterDeletingDisc(await shown(), 2, moveTo: 1),
        userId: 'user-1',
      );
      final queued = {
        for (final r in await db.query(DatabaseTables.syncOutbox))
          r['entity_id'],
      };
      // Every disc changed: Disc 1 gains C and D, and is numbered again.
      expect(queued, {for (final s in songs.values) s.id});
    });

    test('a backup made afterwards restores the same edition', () async {
      await service.deleteDisc(
        albumEditionId: standard.id,
        discNumber: 2,
        placements: afterDeletingDisc(await shown(), 2, moveTo: 3),
      );
      final expected = (await listing(standard), await labels());

      final backup = await createFixtureBackup(
        source: appDatabase,
        directory: root,
      );
      final contents = await const BackupArchiveVerifier().verifyAndExtract(
        backupFile: backup,
        targetDirectory: Directory(path.join(root.path, '.restore')),
      );
      await appDatabase.close();
      appDatabase = fileAppDatabase(root, 'restored.db');
      final target = await appDatabase.database;
      await target.transaction(
        (transaction) => const SqliteRestoreExecutor().apply(
          transaction: transaction,
          backup: contents.backup,
          artworkPaths: const {},
        ),
      );

      expect(await listing(standard), expected.$1);
      expect(await labels(), expected.$2);
      expect(expected.$1, [
        ('A', 1, 1),
        ('B', 1, 2),
        ('E', 2, 1),
        ('F', 2, 2),
        ('C', 2, 3),
        ('D', 2, 4),
      ]);
      expect(expected.$2, {1: 'Main', 2: 'Live'});
    });
  });

  group('moving several songs to a disc', () {
    test('from several discs, keeping their order, numbering both the '
        'source and destination discs', () async {
      final result = await service.arrangeEdition(
        albumEditionId: standard.id,
        placements: movedToDisc(await shown(), {id('F'), id('B'), id('D')}, 1),
      );

      expect(result.changed, isTrue);
      expect(await listing(standard), [
        ('A', 1, 1),
        ('B', 1, 2),
        ('D', 1, 3),
        ('F', 1, 4),
        ('C', 2, 1),
        ('E', 3, 1),
      ]);
    });

    test(
      'to a new disc, with duplicate titles kept apart by Song ID',
      () async {
        final db = await appDatabase.database;
        // Two songs both titled "Intro" (a fictional reprise).
        await db.update(
          DatabaseTables.songs,
          {'title': 'Intro'},
          where: 'id IN (?, ?)',
          whereArgs: [id('A'), id('E')],
        );
        final idsBefore = {
          for (final r in await db.query(DatabaseTables.songs)) r['id'],
        };

        await service.arrangeEdition(
          albumEditionId: standard.id,
          placements: movedToDisc(await shown(), {id('E')}, 4),
        );

        expect(await listing(standard), [
          ('Intro', 1, 1),
          ('B', 1, 2),
          ('C', 2, 1),
          ('D', 2, 2),
          ('F', 3, 1),
          ('Intro', 4, 1),
        ]);
        final placed = await db.query(
          DatabaseTables.albumEditionTracks,
          where: 'album_edition_id = ? AND disc_number = 4',
          whereArgs: [standard.id],
        );
        expect(placed.single['song_id'], id('E'));
        expect({
          for (final r in await db.query(DatabaseTables.songs)) r['id'],
        }, idsBefore);
      },
    );

    test('emptying a source disc removes its listings there, never '
        'duplicating one', () async {
      await service.arrangeEdition(
        albumEditionId: standard.id,
        placements: movedToDisc(await shown(), {id('C'), id('D')}, 3),
      );

      final rows = await listing(standard);
      expect(rows, hasLength(6));
      expect(rows.where((r) => r.$2 == 2), isEmpty);
      expect(rows.sublist(2), [
        ('E', 3, 1),
        ('F', 3, 2),
        ('C', 3, 3),
        ('D', 3, 4),
      ]);
      // A disc left with no songs loses its name (REF-13c).
      expect(await labels(), {1: 'Main', 3: 'Live'});
    });
  });
}
