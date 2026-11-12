// App Update 1.2, REF-13 / REF-13c: arranging an edition in Release Studio
// (order, discs, automatic numbering) and naming its discs. Disposable
// in-memory database; fictional songs.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/library/application/services/album_edition_track_ordering_service.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/artist_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_album_edition_disc_label_repository.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition.dart';
import 'package:sonus_next/features/library/domain/entities/album_edition_track.dart';
import 'package:sonus_next/features/library/domain/entities/entity_factory.dart';
import 'package:sonus_next/features/library/domain/entities/song.dart';
import 'package:sonus_next/features/sync/data/repositories/sync_mutation_transaction_runner.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late AlbumEditionTrackOrderingService service;
  late AlbumEdition standard;
  late AlbumEdition deluxe;
  late Map<String, Song> songs;

  final created = DateTime.utc(2026, 11, 1);
  final now = DateTime.utc(2026, 11, 12, 9);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
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
    for (final (index, title) in ['A', 'B', 'C', 'D'].indexed) {
      final song = EntityFactory.createSong(
        artistId: artist.id,
        albumId: album.id,
        albumEditionId: standard.id,
        title: title,
        trackNumber: index + 1,
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
          discNumber: 1,
          trackNumber: index + 1,
          sortPosition: index,
          createdAt: created,
          updatedAt: created,
        ),
      );
    }
    // "A" is also on Deluxe, with its own placement there.
    await AlbumEditionTrackDao(db).insert(
      AlbumEditionTrack(
        albumEditionId: deluxe.id,
        songId: songs['A']!.id,
        discNumber: 2,
        trackNumber: 7,
        sortPosition: 9,
        createdAt: created,
        updatedAt: created,
      ),
    );
  });

  tearDown(() => appDatabase.close());

  EditionPlacement at(String title, int disc) =>
      EditionPlacement(songId: songs[title]!.id, discNumber: disc);

  /// Title, disc and number of each listing of [edition], in shown order.
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

  Future<Map<int, String>> labels(AlbumEdition edition) async => {
    for (final l in await SqliteAlbumEditionDiscLabelRepository(
      await appDatabase.database,
    ).getByEditionId(edition.id))
      l.discNumber: l.label,
  };

  test(
    'a reorder keeps the order given and numbers the disc 1, 2, 3, 4',
    () async {
      final result = await service.arrangeEdition(
        albumEditionId: standard.id,
        placements: [at('C', 1), at('A', 1), at('D', 1), at('B', 1)],
      );

      expect(result.changed, isTrue);
      expect(await listing(standard), [
        ('C', 1, 1),
        ('A', 1, 2),
        ('D', 1, 3),
        ('B', 1, 4),
      ]);
      // The listener's own numbers now, so file tags do not move them.
      expect(result.memberships.map((m) => m.numberingAuthority).toSet(), {
        AlbumEditionTrackAuthority.manual,
      });
    },
  );

  test('moving songs to another disc numbers each disc from 1, and the '
      "songs' own disc and number follow on their home edition", () async {
    await service.arrangeEdition(
      albumEditionId: standard.id,
      placements: [at('A', 1), at('B', 1), at('C', 2), at('D', 2)],
    );

    expect(await listing(standard), [
      ('A', 1, 1),
      ('B', 1, 2),
      ('C', 2, 1),
      ('D', 2, 2),
    ]);
    final db = await appDatabase.database;
    final c = (await SongDao(db).findById(songs['C']!.id))!;
    expect((c.discNumber, c.trackNumber), (2, 1));
  });

  test('Song IDs and the placement on other editions are untouched', () async {
    final db = await appDatabase.database;
    final idsBefore = {
      for (final r in await db.query(DatabaseTables.songs)) r['id'],
    };
    await service.arrangeEdition(
      albumEditionId: standard.id,
      placements: [at('D', 2), at('C', 2), at('B', 3), at('A', 3)],
    );

    expect({
      for (final r in await db.query(DatabaseTables.songs)) r['id'],
    }, idsBefore);
    final deluxeA = (await db.query(
      DatabaseTables.albumEditionTracks,
      where: 'album_edition_id = ?',
      whereArgs: [deluxe.id],
    )).single;
    expect(
      (
        deluxeA['disc_number'],
        deluxeA['track_number'],
        deluxeA['sort_position'],
      ),
      (2, 7, 9),
    );
  });

  Future<void> number(String title, int disc, int track, {bool? manual}) async {
    final db = await appDatabase.database;
    await db.update(
      DatabaseTables.albumEditionTracks,
      {
        'disc_number': disc,
        'track_number': track,
        if (manual != null)
          'numbering_authority': manual ? 'manual' : 'inferred',
      },
      where: 'song_id = ? AND album_edition_id = ?',
      whereArgs: [songs[title]!.id, standard.id],
    );
  }

  test('a deliberate reorder renumbers the disc without asking, a number '
      'typed by hand included', () async {
    await number('B', 1, 12, manual: true);

    await service.arrangeEdition(
      albumEditionId: standard.id,
      placements: [at('B', 1), at('A', 1), at('C', 1), at('D', 1)],
    );

    expect(await listing(standard), [
      ('B', 1, 1),
      ('A', 1, 2),
      ('C', 1, 3),
      ('D', 1, 4),
    ]);
  });

  test('a disc the arrangement leaves as it was keeps its unusual imported '
      'numbers; only the changed discs are renumbered', () async {
    // Imported: disc 1 numbered 3, 7; disc 2 numbered 5, 9.
    await number('A', 1, 3);
    await number('B', 1, 7);
    await number('C', 2, 5);
    await number('D', 2, 9);

    // D moves up within disc 2; disc 1 is untouched.
    await service.arrangeEdition(
      albumEditionId: standard.id,
      placements: [at('A', 1), at('B', 1), at('D', 2), at('C', 2)],
    );

    expect(await listing(standard), [
      ('A', 1, 3),
      ('B', 1, 7),
      ('D', 2, 1),
      ('C', 2, 2),
    ]);
    final db = await appDatabase.database;
    final a = (await db.query(
      DatabaseTables.albumEditionTracks,
      where: 'song_id = ? AND album_edition_id = ?',
      whereArgs: [songs['A']!.id, standard.id],
    )).single;
    expect(a['numbering_authority'], 'inferred');
    expect(a['updated_at'], created.toIso8601String());
  });

  test(
    'moving a song between discs renumbers both discs, and no other',
    () async {
      await service.arrangeEdition(
        albumEditionId: standard.id,
        placements: [at('A', 1), at('B', 1), at('C', 2), at('D', 3)],
      );
      await number('D', 3, 8); // an imported-looking number on disc 3

      await service.arrangeEdition(
        albumEditionId: standard.id,
        placements: [at('B', 1), at('A', 2), at('C', 2), at('D', 3)],
      );

      expect(await listing(standard), [
        ('B', 1, 1),
        ('A', 2, 1),
        ('C', 2, 2),
        ('D', 3, 8),
      ]);
    },
  );

  test("only the song's placement follows; its title, duration, album and "
      'other fields are unchanged', () async {
    final db = await appDatabase.database;
    Future<Map<String, Object?>> row() async => Map.of(
      (await db.query(
        DatabaseTables.songs,
        where: 'id = ?',
        whereArgs: [songs['C']!.id],
      )).single,
    );
    final before = await row();

    await service.arrangeEdition(
      albumEditionId: standard.id,
      placements: [at('A', 1), at('B', 1), at('D', 1), at('C', 2)],
    );

    final after = await row();
    expect((after['disc_number'], after['track_number']), (2, 1));
    for (final placement in ['disc_number', 'track_number', 'updated_at']) {
      before.remove(placement);
      after.remove(placement);
    }
    expect(after, before);
  });

  test('the same arrangement again changes nothing', () async {
    final placements = [at('B', 1), at('A', 1), at('C', 2), at('D', 2)];
    await service.arrangeEdition(
      albumEditionId: standard.id,
      placements: placements,
    );
    final again = await service.arrangeEdition(
      albumEditionId: standard.id,
      placements: placements,
    );
    expect(again.changed, isFalse);
  });

  test(
    'an arrangement that is not exactly the edition changes nothing',
    () async {
      final before = await listing(standard);
      for (final placements in [
        [at('A', 1), at('B', 1), at('C', 1)], // D missing
        [at('A', 1), at('A', 1), at('C', 1), at('D', 1)], // twice
        [at('A', 0), at('B', 1), at('C', 1), at('D', 1)], // disc 0
      ]) {
        await expectLater(
          () => service.arrangeEdition(
            albumEditionId: standard.id,
            placements: placements,
          ),
          throwsA(anything),
        );
      }
      expect(await listing(standard), before);
    },
  );

  group('disc names (REF-13c)', () {
    test('a name is set, changed and cleared per edition and disc', () async {
      await service.arrangeEdition(
        albumEditionId: standard.id,
        placements: [at('A', 1), at('B', 1), at('C', 2), at('D', 2)],
      );
      await service.setDiscLabel(
        albumEditionId: standard.id,
        discNumber: 2,
        label: '  Bonus Tracks ',
      );
      expect(await labels(standard), {2: 'Bonus Tracks'});
      expect(await labels(deluxe), isEmpty);

      await service.setDiscLabel(
        albumEditionId: standard.id,
        discNumber: 2,
        label: 'Live Performances',
      );
      expect(await labels(standard), {2: 'Live Performances'});

      await service.setDiscLabel(
        albumEditionId: standard.id,
        discNumber: 2,
        label: '   ',
      );
      expect(await labels(standard), isEmpty);
    });

    test(
      'names stay on their disc while songs are reordered and moved',
      () async {
        await service.arrangeEdition(
          albumEditionId: standard.id,
          placements: [at('A', 1), at('B', 1), at('C', 2), at('D', 2)],
        );
        await service.setDiscLabel(
          albumEditionId: standard.id,
          discNumber: 1,
          label: 'Standard Album',
        );
        await service.setDiscLabel(
          albumEditionId: standard.id,
          discNumber: 2,
          label: 'Bonus Tracks',
        );

        await service.arrangeEdition(
          albumEditionId: standard.id,
          placements: [at('B', 1), at('D', 1), at('A', 2), at('C', 2)],
        );

        expect(await labels(standard), {
          1: 'Standard Album',
          2: 'Bonus Tracks',
        });
      },
    );

    test(
      'a disc left empty loses its name, so a new disc 2 starts unnamed',
      () async {
        await service.arrangeEdition(
          albumEditionId: standard.id,
          placements: [at('A', 1), at('B', 1), at('C', 2), at('D', 2)],
        );
        await service.setDiscLabel(
          albumEditionId: standard.id,
          discNumber: 2,
          label: 'Bonus Tracks',
        );

        await service.arrangeEdition(
          albumEditionId: standard.id,
          placements: [at('A', 1), at('B', 1), at('C', 1), at('D', 1)],
        );
        expect(await labels(standard), isEmpty);

        await service.arrangeEdition(
          albumEditionId: standard.id,
          placements: [at('A', 1), at('B', 1), at('C', 1), at('D', 2)],
        );
        expect(await labels(standard), isEmpty);
      },
    );

    test('disc 0 is refused', () async {
      expect(
        () => service.setDiscLabel(
          albumEditionId: standard.id,
          discNumber: 0,
          label: 'Zero',
        ),
        throwsArgumentError,
      );
    });
  });
}
