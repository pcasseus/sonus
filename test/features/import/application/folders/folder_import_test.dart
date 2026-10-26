// SN-45 Part 4: the folder a group of files is in is the album, whatever
// the individual files' album or artist tags say.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/application/folders/folder_album_planner.dart';
import 'package:sonus_next/features/import/application/folders/source_folder_key.dart';
import 'package:sonus_next/features/import/application/models/import_batch.dart';
import 'package:sonus_next/features/import/application/models/import_batch_item.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/import_batch_executor.dart';
import 'package:sonus_next/features/import/application/services/library_import_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/data/daos/import_batch_dao.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_import_batch_repository.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';

class _TagReader implements AudioMetadataReader {
  _TagReader(this.tags);

  final Map<String, AudioMetadata> tags;
  int reads = 0;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async {
    reads++;
    final metadata = tags[candidate.filePath];
    if (metadata == null) throw StateError('No tags for ${candidate.filePath}');
    return metadata;
  }
}

AudioMetadata tags(
  String title,
  String artist, {
  String album = 'Starstruck',
  String? albumArtist,
  int track = 1,
  int disc = 1,
  int duration = 200,
}) => AudioMetadata(
  title: title,
  artistName: artist,
  albumTitle: album,
  albumArtistName: albumArtist,
  durationSeconds: duration,
  trackNumber: track,
  discNumber: disc,
  isSingle: false,
  featuredArtists: const [],
);

FolderPlanEntry entry(
  String path,
  AudioMetadata metadata, {
  String? folder,
  String? name,
}) => FolderPlanEntry(
  normalizedPath: path,
  folderKey: folder,
  folderName: name,
  metadata: metadata,
);

void main() {
  sqfliteFfiInit();

  group('SourceFolderKey', () {
    test('file paths use their parent folder, case- and slash-insensitive', () {
      expect(
        SourceFolderKey.of(r'C:\Music\Starstruck\01 A.mp3'),
        SourceFolderKey.of('c:/music/starstruck/02 B.mp3'),
      );
      expect(
        SourceFolderKey.of('/music/Starstruck/01.mp3'),
        isNot(SourceFolderKey.of('/music/Starstruck (Deluxe)/01.mp3')),
      );
    });

    test('device-storage document URIs use the document path', () {
      const base =
          'content://com.android.externalstorage.documents/tree/'
          'primary%3AMusic/document/primary%3AMusic%2FStarstruck%2F';
      expect(SourceFolderKey.of('${base}01.mp3'), isNotNull);
      expect(
        SourceFolderKey.of('${base}01.mp3'),
        SourceFolderKey.of('${base}02.mp3'),
      );
      // The same file reached through another picked tree is one folder.
      expect(
        SourceFolderKey.of(
          'content://com.android.externalstorage.documents/tree/'
          'primary%3AMusic%2FStarstruck/document/'
          'primary%3AMusic%2FStarstruck%2F01.mp3',
        ),
        SourceFolderKey.of('${base}01.mp3'),
      );
    });

    test('opaque document IDs have no folder: nothing is guessed', () {
      expect(
        SourceFolderKey.of(
          'content://com.example.cloud/tree/x/document/acc%3A12345',
        ),
        isNull,
      );
      expect(SourceFolderKey.of('content://media/external/audio/9'), isNull);
      expect(SourceFolderKey.of('song.mp3'), isNull);
    });

    test('folder names keep their capitalization', () {
      expect(
        SourceFolderKey.folderName('Disney/Starstruck OST/01.mp3'),
        'Starstruck OST',
      );
      expect(
        SourceFolderKey.folderName(
          'content://x/tree/t/document/primary%3AMusic%2FHigh%20School%2F1.mp3',
        ),
        'High School',
      );
    });
  });

  group('FolderAlbumPlanner', () {
    test('a multi-artist soundtrack folder is one album', () {
      final plan = FolderAlbumPlanner.plan([
        entry('a', tags('A', 'Artist 1'), folder: 'f'),
        entry('b', tags('B', 'Artist 2'), folder: 'f'),
        entry('c', tags('C', 'Artist 3'), folder: 'f'),
        entry('d', tags('D', 'Artist 4'), folder: 'f'),
      ]);

      expect(plan.values.toSet(), hasLength(1));
      expect(plan['a']!.albumTitle, 'Starstruck');
      expect(plan['a']!.albumArtistName, FolderAlbumPlanner.variousArtists);
    });

    test('an album artist the files agree on owns the album', () {
      final plan = FolderAlbumPlanner.plan([
        entry('a', tags('A', 'Artist 1', albumArtist: 'Disney'), folder: 'f'),
        entry('b', tags('B', 'Artist 2'), folder: 'f'),
      ]);

      expect(plan['b']!.albumArtistName, 'Disney');
    });

    test('conflicting album artists do not split the folder', () {
      final plan = FolderAlbumPlanner.plan([
        entry('a', tags('A', 'Artist 1', albumArtist: 'X'), folder: 'f'),
        entry('b', tags('B', 'Artist 2', albumArtist: 'Y'), folder: 'f'),
      ]);

      expect(plan['a'], plan['b']);
      expect(plan['a']!.albumArtistName, FolderAlbumPlanner.variousArtists);
    });

    test('one performer owns their own folder', () {
      final plan = FolderAlbumPlanner.plan([
        entry('a', tags('A', 'Madison Beer', album: 'locket'), folder: 'f'),
        entry('b', tags('B', 'madison beer', album: 'locket'), folder: 'f'),
      ]);

      expect(plan['a']!.albumArtistName, 'Madison Beer');
    });

    test('disagreeing album titles: the majority, else the folder name', () {
      final majority = FolderAlbumPlanner.plan([
        entry('a', tags('A', 'X', album: 'Hits'), folder: 'f'),
        entry('b', tags('B', 'X', album: 'Hits'), folder: 'f'),
        entry('c', tags('C', 'X', album: 'Single'), folder: 'f'),
      ]);
      expect(majority['c']!.albumTitle, 'Hits');

      final tie = FolderAlbumPlanner.plan([
        entry(
          'a',
          tags('A', 'X', album: 'One'),
          folder: 'f',
          name: 'Mixtape',
        ),
        entry(
          'b',
          tags('B', 'X', album: 'Two'),
          folder: 'f',
          name: 'Mixtape',
        ),
      ]);
      expect(tie['a']!.albumTitle, 'Mixtape');
    });

    test('different folders stay apart; unknown folders get no plan', () {
      final plan = FolderAlbumPlanner.plan([
        entry('a', tags('A', 'X', album: 'Hits'), folder: 'f1'),
        entry('b', tags('B', 'X', album: 'Hits'), folder: 'f2'),
        entry('c', tags('C', 'X', album: 'Hits')),
      ]);

      expect(plan['a']!.folderKey, isNot(plan['b']!.folderKey));
      expect(plan.containsKey('c'), isFalse);
    });
  });

  group('imports (disposable database)', () {
    late AppDatabase appDatabase;
    late Database db;
    final now = DateTime.utc(2026, 10, 25, 12);
    var batchCount = 0;

    setUp(() async {
      appDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      db = await appDatabase.database;
    });

    tearDown(() => appDatabase.close());

    Future<_TagReader> importBatch(Map<String, AudioMetadata> files) async {
      final reader = _TagReader(files);
      final service = LibraryImportService(
        metadataResolver: MetadataResolver(
          primaryReader: reader,
          fallbackReader: reader,
        ),
        atomicImporter: AtomicLibraryImporter(appDatabase: appDatabase),
        mediaFileBindingRepository: SqliteMediaFileBindingRepository(
          MediaFileBindingDao(db),
        ),
      );
      final executor = ImportBatchExecutor(
        libraryImportService: service,
        batchRepository: SqliteImportBatchRepository(ImportBatchDao(db)),
      );
      await executor.execute(
        ImportBatch(
          id: 'batch-${++batchCount}',
          createdAt: now,
          items: [
            for (final path in files.keys)
              ImportBatchItem(
                candidate: ImportCandidate(
                  filePath: path,
                  normalizedPath: path.toLowerCase(),
                  discoveredAt: now,
                ),
              ),
          ],
        ),
        startedAt: now,
        completedAt: now,
      );
      return reader;
    }

    Future<List<Map<String, Object?>>> albums() => db.rawQuery('''
      SELECT al.id, al.title, ar.name AS owner
      FROM ${DatabaseTables.albums} al
      JOIN ${DatabaseTables.artists} ar ON ar.id = al.artist_id
      ORDER BY al.created_at, al.title
    ''');

    Future<List<Map<String, Object?>>> songs() => db.rawQuery('''
      SELECT s.title, ar.name AS performer, s.album_id, s.track_number,
             s.disc_number, s.album_edition_id
      FROM ${DatabaseTables.songs} s
      JOIN ${DatabaseTables.artists} ar ON ar.id = s.artist_id
      ORDER BY s.disc_number, s.track_number
    ''');

    test(
      'Starstruck: four performers, one album, real performers kept',
      () async {
        await importBatch({
          '/m/Starstruck Soundtrack/01.mp3': tags(
            'Track A',
            'Artist 1',
            track: 1,
          ),
          '/m/Starstruck Soundtrack/02.mp3': tags(
            'Track B',
            'Artist 2',
            track: 2,
          ),
          '/m/Starstruck Soundtrack/03.mp3': tags(
            'Track C',
            'Artist 3',
            track: 3,
          ),
          '/m/Starstruck Soundtrack/04.mp3': tags(
            'Track D',
            'Artist 4',
            track: 4,
          ),
        });

        final albumRows = await albums();
        expect(albumRows, hasLength(1));
        expect(albumRows.single['title'], 'Starstruck');
        expect(albumRows.single['owner'], FolderAlbumPlanner.variousArtists);

        final songRows = await songs();
        expect(songRows.map((s) => s['performer']), [
          'Artist 1',
          'Artist 2',
          'Artist 3',
          'Artist 4',
        ]);
        expect(songRows.map((s) => s['album_id']).toSet(), hasLength(1));
        // Each song's primary credit is its real performer, not the album.
        final credits = await db.rawQuery('''
        SELECT credited_name FROM ${DatabaseTables.songArtistCredits}
        WHERE role = 'primary' ORDER BY credited_name
      ''');
        expect(credits.map((c) => c['credited_name']), [
          'Artist 1',
          'Artist 2',
          'Artist 3',
          'Artist 4',
        ]);
      },
    );

    test('tags are read once per new file', () async {
      final reader = await importBatch({
        '/m/F/1.mp3': tags('A', 'Artist 1'),
        '/m/F/2.mp3': tags('B', 'Artist 2'),
      });

      expect(reader.reads, 2);
    });

    test('the folder wins over conflicting album-artist tags', () async {
      await importBatch({
        '/m/Mix/1.mp3': tags('A', 'Artist 1', album: 'Mix', albumArtist: 'X'),
        '/m/Mix/2.mp3': tags('B', 'Artist 2', album: 'Mix', albumArtist: 'Y'),
      });

      expect(await albums(), hasLength(1));
    });

    test('unrelated songs put in one folder stay together', () async {
      await importBatch({
        '/m/Favourites/1.mp3': tags('A', 'Artist 1', album: 'One'),
        '/m/Favourites/2.mp3': tags('B', 'Artist 2', album: 'Two'),
      });

      final albumRows = await albums();
      expect(albumRows, hasLength(1));
      expect(albumRows.single['title'], 'Favourites');
    });

    test('nested artist folders: each album folder is its own album', () async {
      await importBatch({
        '/m/Madison Beer/locket/1.mp3': tags('A', 'Madison Beer', album: 'L'),
        '/m/Madison Beer/Life Support/1.mp3': tags(
          'B',
          'Madison Beer',
          album: 'LS',
        ),
      });

      expect(await albums(), hasLength(2));
    });

    test('distinct folders with the same tags stay distinct', () async {
      await importBatch({
        '/m/Hits A/1.mp3': tags('A', 'Artist 1', album: 'Greatest Hits'),
      });
      await importBatch({
        '/m/Hits B/1.mp3': tags('B', 'Artist 1', album: 'Greatest Hits'),
      });
      // A third song in the second folder joins the second album, even
      // though two albums now share the title.
      await importBatch({
        '/m/Hits B/2.mp3': tags('C', 'Artist 1', album: 'Greatest Hits'),
      });

      final albumRows = await albums();
      expect(albumRows, hasLength(2));
      final songRows = await songs();
      final byTitle = {for (final s in songRows) s['title']: s['album_id']};
      expect(byTitle['B'], byTitle['C']);
      expect(byTitle['A'], isNot(byTitle['B']));
    });

    test('a file added to an imported folder joins its album', () async {
      await importBatch({
        '/m/Starstruck/1.mp3': tags('A', 'Artist 1'),
        '/m/Starstruck/2.mp3': tags('B', 'Artist 2'),
      });
      await importBatch({
        // Its own tags would have filed it under "Something Else".
        '/m/Starstruck/3.mp3': tags('C', 'Artist 5', album: 'Something Else'),
      });

      expect(await albums(), hasLength(1));
      expect(await songs(), hasLength(3));
    });

    test('Standard and Deluxe folders are editions of one album', () async {
      await importBatch({
        '/m/locket/1.mp3': tags('angel wings', 'Madison Beer', album: 'locket'),
        '/m/locket (Deluxe)/1.mp3': tags(
          'angel wings',
          'Madison Beer',
          album: 'locket (Deluxe)',
        ),
        '/m/locket (Deluxe)/9.mp3': tags(
          'bonus',
          'Madison Beer',
          album: 'locket (Deluxe)',
          track: 9,
        ),
      });

      expect(await albums(), hasLength(1));
      final editions = await db.query(DatabaseTables.albumEditions);
      expect(editions, hasLength(2));
      // The shared song is one song listed on both editions.
      final angel = await db.query(
        DatabaseTables.songs,
        where: 'title = ?',
        whereArgs: ['angel wings'],
      );
      expect(angel, hasLength(1));
    });

    test('repeated titles by different performers are different songs', () {
      return importBatch({
        '/m/Covers/1.mp3': tags('Hallelujah', 'Artist 1', album: 'Covers'),
        '/m/Covers/2.mp3': tags(
          'Hallelujah',
          'Artist 2',
          album: 'Covers',
          track: 2,
        ),
      }).then((_) async {
        final rows = await songs();
        expect(rows, hasLength(2));
        expect(rows.map((s) => s['album_id']).toSet(), hasLength(1));
      });
    });

    test('distinct recordings of one song stay distinct', () async {
      await importBatch({
        '/m/Live/1.mp3': tags('Song', 'Artist 1', album: 'Live', duration: 200),
        '/m/Live/2.mp3': tags(
          'Song',
          'Artist 1',
          album: 'Live',
          duration: 320,
          track: 2,
        ),
      });

      expect(await songs(), hasLength(2));
    });

    test('disc and track order are kept', () async {
      await importBatch({
        '/m/Double/b.mp3': tags('Second', 'X', album: 'Double', disc: 2),
        '/m/Double/a.mp3': tags('First', 'Y', album: 'Double', disc: 1),
      });

      final rows = await songs();
      expect(rows.map((s) => (s['title'], s['disc_number'])), [
        ('First', 1),
        ('Second', 2),
      ]);
    });

    test('files with no reliable folder keep tag-based albums', () async {
      await importBatch({
        'content://com.example.cloud/tree/x/document/acc%3A1': tags(
          'A',
          'Artist 1',
        ),
        'content://com.example.cloud/tree/x/document/acc%3A2': tags(
          'B',
          'Artist 2',
        ),
      });

      // Exactly as before SN-45: one album per album artist.
      expect(await albums(), hasLength(2));
    });

    test('device-storage document folders group like file paths', () async {
      const base =
          'content://com.android.externalstorage.documents/tree/'
          'primary%3AMusic/document/primary%3AMusic%2FStarstruck%2F';
      await importBatch({
        '${base}1.mp3': tags('A', 'Artist 1'),
        '${base}2.mp3': tags('B', 'Artist 2'),
      });

      expect(await albums(), hasLength(1));
    });

    test('relinking after a restore ignores folders', () async {
      // A library imported before SN-45: one album per artist.
      for (final (path, title, artist) in [
        ('/old/Starstruck/1.mp3', 'A', 'Artist 1'),
        ('/old/Starstruck/2.mp3', 'B', 'Artist 2'),
      ]) {
        await AtomicLibraryImporter(appDatabase: appDatabase).import(
          candidate: ImportCandidate(
            filePath: path,
            normalizedPath: path.toLowerCase(),
            discoveredAt: now,
          ),
          metadata: tags(title, artist),
          now: now,
        );
      }
      final before = await songs();

      // The same files at a new location, relinked as recovery does.
      final relinker = AtomicLibraryImporter(
        appDatabase: appDatabase,
        relinkOnly: true,
      );
      final placement = FolderAlbumPlanner.plan([
        entry('/new/starstruck/1.mp3', tags('A', 'Artist 1'), folder: 'f'),
        entry('/new/starstruck/2.mp3', tags('B', 'Artist 2'), folder: 'f'),
      ]);
      for (final (path, title, artist) in [
        ('/new/Starstruck/1.mp3', 'A', 'Artist 1'),
        ('/new/Starstruck/2.mp3', 'B', 'Artist 2'),
      ]) {
        final result = await relinker.import(
          candidate: ImportCandidate(
            filePath: path,
            normalizedPath: path.toLowerCase(),
            discoveredAt: now,
          ),
          metadata: tags(title, artist),
          folderPlacement: placement[path.toLowerCase()],
          now: now,
        );
        expect(result.songId, isNotNull, reason: 'relinked to its song');
      }

      expect(await songs(), before);
      expect(await albums(), hasLength(2));
    });

    test('a rescan changes nothing and reads no tags', () async {
      final files = {
        '/m/Starstruck/1.mp3': tags('A', 'Artist 1'),
        '/m/Starstruck/2.mp3': tags('B', 'Artist 2'),
      };
      await importBatch(files);
      final before = await songs();

      final reader = await importBatch(files);

      expect(reader.reads, 0);
      expect(await songs(), before);
    });
  });
}
