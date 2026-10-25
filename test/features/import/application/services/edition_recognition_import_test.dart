// J8: a Deluxe edition imported as its own album, with every shared
// Standard track duplicated as a second song.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/library/data/daos/album_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_dao.dart';
import 'package:sonus_next/features/library/data/daos/album_edition_track_dao.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  final now = DateTime.utc(2026, 10, 25, 12);

  setUp(() {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() => appDatabase.close());

  Future<ImportResult> importTrack({
    required String album,
    required String title,
    required int track,
    String artist = 'Madison Beer',
    int seconds = 180,
  }) {
    final path = '$artist/$album/$track $title.mp3';
    return AtomicLibraryImporter(appDatabase: appDatabase).import(
      candidate: ImportCandidate(
        filePath: path,
        normalizedPath: path.toLowerCase(),
        discoveredAt: now,
      ),
      metadata: AudioMetadata(
        title: title,
        artistName: artist,
        albumTitle: album,
        durationSeconds: seconds,
        trackNumber: track,
        discNumber: 1,
        isSingle: false,
        featuredArtists: const [],
      ),
      now: now,
    );
  }

  Future<void> importStandard() async {
    for (final (n, title) in [(1, 'One'), (2, 'Two'), (3, 'Three')]) {
      await importTrack(album: 'locket', title: title, track: n);
    }
  }

  Future<List<ImportResult>> importDeluxe() async => [
    for (final (n, title) in [
      (1, 'One'),
      (2, 'Two'),
      (3, 'Three'),
      (4, 'Bonus'),
    ])
      await importTrack(album: 'locket (Deluxe)', title: title, track: n),
  ];

  Future<Map<String, List<String>>> editionsOfOnlyAlbum() async {
    final db = await appDatabase.database;
    final albums = await AlbumDao(db).findAll();
    expect(albums, hasLength(1), reason: 'one album identity');
    final editions = await AlbumEditionDao(db).findByAlbumId(albums.single.id);
    final songs = {for (final s in await SongDao(db).findAll()) s.id: s.title};
    return {
      for (final e in editions)
        '${e.title}|${e.type.name}|${e.isPrimary ? 'primary' : ''}': [
          for (final m in await AlbumEditionTrackDao(db).findByEditionId(e.id))
            songs[m.songId]!,
        ],
    };
  }

  test(
    'a Deluxe joins its Standard album, sharing the Standard tracks',
    () async {
      await importStandard();
      final deluxe = await importDeluxe();

      expect(await editionsOfOnlyAlbum(), {
        'locket|standard|primary': ['One', 'Two', 'Three'],
        'locket (Deluxe)|deluxe|': ['One', 'Two', 'Three', 'Bonus'],
      });

      final db = await appDatabase.database;
      expect(
        await SongDao(db).findAll(),
        hasLength(4),
        reason: 'no duplicates',
      );

      expect(
        deluxe.take(3).map((r) => r.skipReason),
        everyElement(ImportSkipReason.sharedWithEdition),
      );
      expect(deluxe.last.status, ImportResultStatus.imported);
    },
  );

  test('a Deluxe imported first still makes one album', () async {
    await importDeluxe();
    await importStandard();

    expect(await editionsOfOnlyAlbum(), {
      'locket (Deluxe)|deluxe|primary': ['One', 'Two', 'Three', 'Bonus'],
      'locket|standard|': ['One', 'Two', 'Three'],
    });

    final db = await appDatabase.database;
    expect((await AlbumDao(db).findAll()).single.title, 'locket');
  });

  test('a different recording on the Deluxe stays its own song', () async {
    await importStandard();
    await importTrack(
      album: 'locket (Deluxe)',
      title: 'One',
      track: 1,
      seconds: 240,
    );

    final db = await appDatabase.database;
    expect(await SongDao(db).findAll(), hasLength(4));
  });

  test('bracketed words that are not an edition never join albums', () async {
    await importTrack(album: "it's not that deep", title: 'A', track: 1);
    await importTrack(
      album: "it's not that deep (unless you want it to be)",
      title: 'A',
      track: 1,
    );

    final db = await appDatabase.database;
    expect(await AlbumDao(db).findAll(), hasLength(2));
  });

  test("another artist's Deluxe never joins", () async {
    await importStandard();
    await importTrack(
      album: 'locket (Deluxe)',
      title: 'One',
      track: 1,
      artist: 'Someone Else',
    );

    final db = await appDatabase.database;
    expect(await AlbumDao(db).findAll(), hasLength(2));
  });

  test(
    'a library that already has a separate Deluxe album keeps using it',
    () async {
      final db = await appDatabase.database;
      // Imported before edition recognition: "locket (Deluxe)" is its own album.
      final first = await importTrack(
        album: 'locket (Deluxe)',
        title: 'One',
        track: 1,
      );
      final separate = (await SongDao(db).findById(first.songId!))!.albumId;
      final album = (await AlbumDao(db).findById(separate))!;
      await AlbumDao(db).update(
        album.copyWith(
          title: 'locket (Deluxe)',
          canonicalTitle: 'locket (deluxe)',
        ),
      );

      await importStandard();
      final later = await importTrack(
        album: 'locket (Deluxe)',
        title: 'Two',
        track: 2,
      );

      expect(await AlbumDao(db).findAll(), hasLength(2));
      expect((await SongDao(db).findById(later.songId!))!.albumId, separate);
    },
  );
}
