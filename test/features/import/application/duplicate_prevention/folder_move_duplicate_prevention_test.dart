// App Update 1.2: moving or renaming an album's folder never creates a new
// album. Reproduces the 2026-11-07 Zendaya sequence on disposable files and
// a disposable database (never the user's library):
//   1. 11 songs directly inside the artist folder;
//   2. moved into a nested folder with another name ("Zendayaa"), import;
//   3. that folder renamed ("Zendaya"), import.
// Exactly one album must remain, with 11 playable songs, its artwork,
// release date and listening history.
//
// BUG-09 (App Update 1.2): moved files are recognised by their audio, so
// each file holds real MP3 bytes (distinct audio per song) and every scan
// runs the app's file identity pass.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/import_batch_executor.dart';
import 'package:sonus_next/features/import/application/services/import_source_reconciliation_service.dart';
import 'package:sonus_next/features/import/application/services/import_workflow_service.dart';
import 'package:sonus_next/features/import/application/services/library_import_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/data/daos/import_batch_dao.dart';
import 'package:sonus_next/features/import/data/daos/import_source_dao.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_import_batch_repository.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_import_source_repository.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/data/services/file_system_import_candidate_discovery.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';
import 'package:sonus_next/features/import/application/services/existing_song_tag_updater.dart';
import 'package:sonus_next/features/import/application/services/file_identity_service.dart';
import 'package:sonus_next/features/import/data/services/audio_byte_sources.dart';
import 'package:sonus_next/features/library/application/services/duplicate_album_reconciliation_service.dart';

import '../../../../support/synthetic_mp3.dart';

/// Tags travel with the file: keyed by file name, whatever folder it is in.
class _TagsByFileName implements AudioMetadataReader {
  _TagsByFileName(this.tags);

  final Map<String, AudioMetadata> tags;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async {
    final name = p.basename(candidate.filePath).toLowerCase();
    final metadata = tags[name];
    if (metadata == null) throw StateError('No tags for $name');
    return metadata;
  }
}

AudioMetadata _tags(
  String title, {
  String artist = 'Zendaya',
  String album = 'Zendaya',
  int track = 1,
  int duration = 200,
}) => AudioMetadata(
  title: title,
  artistName: artist,
  albumTitle: album,
  durationSeconds: duration,
  trackNumber: track,
  discNumber: 1,
  isSingle: false,
  featuredArtists: const [],
);

const _albumTracks = [
  ('Replay', 215),
  ('Fireflies', 260),
  ('Butterflies', 234),
  ('Putcha Body Down', 206),
  ('Heaven Lost an Angel', 197),
  ('Cry for Love', 236),
  ('Only When Youre Close', 231),
  ('Bottle You Up', 227),
  ('Scared', 185),
  ('Love You Forever', 255),
  ('My Baby', 194),
];

String _fileName(String title) => '${title.toLowerCase()}.mp3';

void main() {
  sqfliteFfiInit();

  late Directory sandbox;
  late Directory root;
  late String dbPath;
  late AppDatabase appDatabase;
  late Map<String, AudioMetadata> tags;
  var scanNumber = 0;
  String? sourceId;
  final base = DateTime.utc(2026, 11, 6, 12);

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('sonus_dup_prevention_');
    root = Directory(p.join(sandbox.path, 'Music'))..createSync();
    dbPath = p.join(sandbox.path, 'library.db');
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: dbPath,
    );
    tags = {
      for (final (index, (title, duration)) in _albumTracks.indexed)
        _fileName(title): _tags(title, track: index + 1, duration: duration),
      'swag it out.mp3': _tags(
        'Swag It Out',
        album: 'Swag It Out',
        duration: 189,
      ),
    };
    scanNumber = 0;
    sourceId = null;
  });

  tearDown(() async {
    await appDatabase.close();
    await sandbox.delete(recursive: true);
  });

  /// One scan of the source, through the app's real import workflow:
  /// discovery, the batch executor and the after-scan reconciliation.
  Future<void> scan({bool reconcileDuplicates = false}) async {
    final db = await appDatabase.database;
    final createdAt = base.add(Duration(hours: ++scanNumber));
    final bindings = SqliteMediaFileBindingRepository(MediaFileBindingDao(db));
    final resolver = MetadataResolver(
      primaryReader: _TagsByFileName(tags),
      fallbackReader: _TagsByFileName(tags),
    );
    final workflow = ImportWorkflowService(
      candidateDiscovery: const FileSystemImportCandidateDiscovery(),
      batchRunner: ImportBatchExecutor(
        libraryImportService: LibraryImportService(
          metadataResolver: resolver,
          atomicImporter: AtomicLibraryImporter(appDatabase: appDatabase),
          mediaFileBindingRepository: bindings,
          fileIdentityService: FileIdentityService(
            appDatabase: appDatabase,
            openSource: audioByteSourceOpener(),
            metadataResolver: resolver,
            tagUpdater: const ExistingSongTagUpdater(),
          ),
        ),
        batchRepository: SqliteImportBatchRepository(ImportBatchDao(db)),
      ),
      importSourceRepository: SqliteImportSourceRepository(ImportSourceDao(db)),
      mediaFileBindingRepository: bindings,
      sourceReconciliationService: ImportSourceReconciliationService(
        appDatabase: appDatabase,
      ),
      batchIdFactory: () => 'batch_$scanNumber',
      sourceIdFactory: () => 'source_music',
      changes: LibraryChangeSignal(),
      afterSourceScan: reconcileDuplicates
          ? () => DuplicateAlbumReconciliationService(
              appDatabase: appDatabase,
              changes: LibraryChangeSignal(),
            ).reconcile()
          : null,
    );
    final completedAt = createdAt.add(const Duration(minutes: 1));
    if (sourceId == null) {
      await workflow.importStructuredFolder(
        root.path,
        createdAt: createdAt,
        startedAt: createdAt,
        completedAt: completedAt,
      );
      sourceId = 'source_music';
    } else {
      await workflow.rescanSource(
        sourceId!,
        createdAt: createdAt,
        startedAt: createdAt,
        completedAt: completedAt,
      );
    }
  }

  void writeAlbumFiles(Directory folder) {
    folder.createSync(recursive: true);
    for (final (title, _) in _albumTracks) {
      File(p.join(folder.path, _fileName(title))).writeAsBytesSync(
        syntheticMp3(syntheticAudio(frames: 60, seed: title.hashCode)),
      );
    }
  }

  Future<List<Map<String, Object?>>> albumsNamed(String title) async {
    final db = await appDatabase.database;
    return db.query(
      DatabaseTables.albums,
      where: 'canonical_title = ?',
      whereArgs: [title.toLowerCase()],
    );
  }

  /// Song id → its bindings (path, available).
  Future<Map<String, List<(String, bool)>>> bindingsOf(String albumId) async {
    final db = await appDatabase.database;
    final rows = await db.rawQuery(
      '''
      SELECT s.id AS song_id, mb.normalized_path AS path,
             mb.is_available AS available
      FROM ${DatabaseTables.songs} s
      LEFT JOIN ${DatabaseTables.mediaFileBindings} mb ON mb.song_id = s.id
      WHERE s.album_id = ?
      ''',
      [albumId],
    );
    final out = <String, List<(String, bool)>>{};
    for (final row in rows) {
      final list = out[row['song_id']! as String] ??= [];
      if (row['path'] != null) {
        list.add((row['path']! as String, row['available'] == 1));
      }
    }
    return out;
  }

  String folderKeyOf(Directory folder) =>
      folder.path.replaceAll(r'\', '/').toLowerCase();

  /// What the user did after the first import: chose artwork, the release
  /// date came from MusicBrainz, and two songs were played.
  Future<void> curateAndPlay(String albumId) async {
    final db = await appDatabase.database;
    final now = base.toIso8601String();
    await db.insert(DatabaseTables.artworkAssets, {
      'id': 'artwork_user_choice',
      'file_path': '/artwork/zendaya.jpg',
      'normalized_path': '/artwork/zendaya.jpg',
      'created_at': now,
      'updated_at': now,
    });
    await db.update(
      DatabaseTables.albumEditions,
      {
        'artwork_id': 'artwork_user_choice',
        'release_date': '2013-09-17T00:00:00.000Z',
        'release_date_precision': 'day',
      },
      where: 'album_id = ?',
      whereArgs: [albumId],
    );
    final songs = await db.query(
      DatabaseTables.songs,
      where: 'album_id = ?',
      whereArgs: [albumId],
      orderBy: 'track_number',
    );
    for (final song in [songs.first, songs.last]) {
      final id = song['id']! as String;
      await db.insert(DatabaseTables.playbackSessions, {
        'id': 'session_$id',
        'song_id': id,
        'artist_id': song['artist_id'],
        'album_id': albumId,
        'album_edition_id': song['album_edition_id'],
        'song_title': song['title'],
        'artist_name': 'Zendaya',
        'album_title': 'Zendaya',
        'album_edition_title': 'Zendaya',
        'started_at': now,
        'ended_at': now,
        'listened_duration_ms': 200000,
        'track_duration_ms': 200000,
        'created_at': now,
        'updated_at': now,
      });
      await db.insert(DatabaseTables.qualifiedPlays, {
        'id': 'play_$id',
        'playback_session_id': 'session_$id',
        'song_id': id,
        'artist_id': song['artist_id'],
        'album_id': albumId,
        'album_edition_id': song['album_edition_id'],
        'qualified_at': now,
        'listened_duration_ms': 200000,
        'track_duration_ms': 200000,
        'created_at': now,
      });
    }
  }

  Future<void> expectOneIntactAlbum({
    required String albumId,
    required Set<String> songIds,
    required Directory playableFrom,
  }) async {
    final db = await appDatabase.database;
    final albums = await albumsNamed('Zendaya');
    expect(albums.map((a) => a['id']), [albumId], reason: 'one album only');

    final bindings = await bindingsOf(albumId);
    expect(bindings.keys.toSet(), songIds, reason: 'the same 11 songs');
    for (final entry in bindings.entries) {
      expect(entry.value, hasLength(1), reason: 'one file per song');
      final (path, available) = entry.value.single;
      expect(available, isTrue, reason: 'every song plays');
      expect(p.posix.dirname(path), folderKeyOf(playableFrom));
    }

    final edition = (await db.query(
      DatabaseTables.albumEditions,
      where: 'album_id = ?',
      whereArgs: [albumId],
    )).single;
    expect(edition['artwork_id'], 'artwork_user_choice');
    expect(edition['release_date'], '2013-09-17T00:00:00.000Z');
    expect(edition['release_date_precision'], 'day');

    final plays = await db.rawQuery(
      'SELECT q.song_id FROM ${DatabaseTables.qualifiedPlays} q '
      'JOIN ${DatabaseTables.songs} s ON s.id = q.song_id '
      'WHERE s.album_id = ?',
      [albumId],
    );
    expect(plays, hasLength(2), reason: 'history still points at the songs');

    final orphanSongs = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM ${DatabaseTables.songs} '
      "WHERE album_id <> ? AND canonical_title IN ('replay', 'my baby')",
      [albumId],
    );
    expect(orphanSongs.single['n'], 0, reason: 'no duplicate songs');
  }

  test('the Zendaya sequence keeps exactly one album', () async {
    final artistFolder = Directory(p.join(root.path, 'Zendaya'));

    // 1. Directly inside the artist folder (self-titled, no nesting).
    writeAlbumFiles(artistFolder);
    await scan();
    final first = await albumsNamed('Zendaya');
    expect(first, hasLength(1));
    final albumId = first.single['id']! as String;
    final songIds = (await bindingsOf(albumId)).keys.toSet();
    expect(songIds, hasLength(11));
    await curateAndPlay(albumId);

    // 2. Moved into a nested folder with another name, plus a new single.
    final typo = Directory(p.join(artistFolder.path, 'Zendayaa'));
    typo.createSync();
    for (final (title, _) in _albumTracks) {
      File(
        p.join(artistFolder.path, _fileName(title)),
      ).renameSync(p.join(typo.path, _fileName(title)));
    }
    final single = Directory(p.join(artistFolder.path, 'Swag It Out'))
      ..createSync();
    File(p.join(single.path, 'swag it out.mp3')).writeAsBytesSync([0]);
    await scan();
    await expectOneIntactAlbum(
      albumId: albumId,
      songIds: songIds,
      playableFrom: typo,
    );
    expect(await albumsNamed('Swag It Out'), hasLength(1));

    // 3. The nested folder renamed.
    final renamed = typo.renameSync(p.join(artistFolder.path, 'Zendaya'));
    await scan();
    await expectOneIntactAlbum(
      albumId: albumId,
      songIds: songIds,
      playableFrom: renamed,
    );

    // 4. Rescanning again changes nothing.
    final db = await appDatabase.database;
    Future<List<int>> counts() async => [
      for (final table in [
        DatabaseTables.albums,
        DatabaseTables.albumEditions,
        DatabaseTables.songs,
        DatabaseTables.mediaFileBindings,
        DatabaseTables.qualifiedPlays,
      ])
        (await db.rawQuery('SELECT COUNT(*) AS n FROM $table')).single['n']!
            as int,
    ];
    final before = await counts();
    await scan();
    await scan();
    expect(await counts(), before);
    await expectOneIntactAlbum(
      albumId: albumId,
      songIds: songIds,
      playableFrom: renamed,
    );
  });

  test('duplicates left by an older version are merged after a scan', () async {
    final artistFolder = Directory(p.join(root.path, 'Zendaya'));
    writeAlbumFiles(artistFolder);
    await scan();
    final albumId = (await albumsNamed('Zendaya')).single['id']! as String;
    final songIds = (await bindingsOf(albumId)).keys.toSet();
    await curateAndPlay(albumId);

    // What the old folder rule left behind: the files moved to a nested
    // folder, and a second album owns them there.
    final nested = Directory(p.join(artistFolder.path, 'Zendaya'));
    nested.createSync();
    for (final (title, _) in _albumTracks) {
      File(
        p.join(artistFolder.path, _fileName(title)),
      ).renameSync(p.join(nested.path, _fileName(title)));
    }
    final db = await appDatabase.database;
    await db.transaction((txn) async {
      String copy(String id) => '${id}_legacy_copy';
      final album = (await txn.query(
        DatabaseTables.albums,
        where: 'id = ?',
        whereArgs: [albumId],
      )).single;
      await txn.insert(DatabaseTables.albums, {
        ...album,
        'id': copy(albumId),
        'created_at': '2026-11-07T07:43:56.746952Z',
      });
      final edition = (await txn.query(
        DatabaseTables.albumEditions,
        where: 'album_id = ?',
        whereArgs: [albumId],
      )).single;
      await txn.insert(DatabaseTables.albumEditions, {
        ...edition,
        'id': copy(edition['id']! as String),
        'album_id': copy(albumId),
        'artwork_id': null,
        'release_date': '2013-01-01T05:00:00.000Z',
        'release_date_precision': 'year',
      });
      for (final song in await txn.query(
        DatabaseTables.songs,
        where: 'album_id = ?',
        whereArgs: [albumId],
      )) {
        final id = song['id']! as String;
        await txn.insert(DatabaseTables.songs, {
          ...song,
          'id': copy(id),
          'album_id': copy(albumId),
          'album_edition_id': copy(edition['id']! as String),
        });
        final binding = (await txn.query(
          DatabaseTables.mediaFileBindings,
          where: 'song_id = ?',
          whereArgs: [id],
        )).single;
        final newPath = p.join(
          nested.path,
          p.basename(binding['file_path']! as String),
        );
        await txn.update(
          DatabaseTables.mediaFileBindings,
          {'is_available': 0},
          where: 'id = ?',
          whereArgs: [binding['id']],
        );
        await txn.insert(DatabaseTables.mediaFileBindings, {
          ...binding,
          'id': copy(binding['id']! as String),
          'song_id': copy(id),
          'file_path': newPath,
          // Windows separators become '/', as the scan normalizes paths
          // (BUG-09: the empty pattern here garbled every stored path).
          'normalized_path': newPath.replaceAll('\\', '/').toLowerCase(),
          'is_available': 1,
        });
      }
    });
    expect(await albumsNamed('Zendaya'), hasLength(2));

    await scan(reconcileDuplicates: true);

    await expectOneIntactAlbum(
      albumId: albumId,
      songIds: songIds,
      playableFrom: nested,
    );
  });

  test('the sequence survives app restarts between scans', () async {
    final artistFolder = Directory(p.join(root.path, 'Zendaya'));
    writeAlbumFiles(artistFolder);
    await scan();
    final albumId = (await albumsNamed('Zendaya')).single['id']! as String;
    final songIds = (await bindingsOf(albumId)).keys.toSet();
    await curateAndPlay(albumId);

    Future<void> restart() async {
      await appDatabase.close();
      appDatabase = AppDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: dbPath,
      );
    }

    final nested = Directory(p.join(artistFolder.path, 'Zendayaa'))
      ..createSync();
    for (final (title, _) in _albumTracks) {
      File(
        p.join(artistFolder.path, _fileName(title)),
      ).renameSync(p.join(nested.path, _fileName(title)));
    }
    await restart();
    await scan();
    await restart();
    final renamed = nested.renameSync(p.join(artistFolder.path, 'Zendaya'));
    await scan();
    await restart();
    await scan();

    await expectOneIntactAlbum(
      albumId: albumId,
      songIds: songIds,
      playableFrom: renamed,
    );
  });

  test('a folder that disappears is never treated as deleted', () async {
    final folder = Directory(p.join(root.path, 'Zendaya'));
    writeAlbumFiles(folder);
    await scan();
    final albumId = (await albumsNamed('Zendaya')).single['id']! as String;
    await curateAndPlay(albumId);

    // The files are gone (an unmounted card, a folder moved off the
    // source). The library keeps everything; the songs just do not play.
    folder.deleteSync(recursive: true);
    await scan();

    final bindings = await bindingsOf(albumId);
    expect(bindings, hasLength(11));
    expect(bindings.values.every((b) => b.single.$2 == false), isTrue);
    final db = await appDatabase.database;
    expect(await db.query(DatabaseTables.qualifiedPlays), hasLength(2));

    // They come back: relinked to the same songs, nothing new.
    writeAlbumFiles(folder);
    await scan();
    expect(await albumsNamed('Zendaya'), hasLength(1));
    final back = await bindingsOf(albumId);
    expect(back.values.every((b) => b.single.$2), isTrue);
  });

  test(
    'a copy of a playing album joins it instead of duplicating it',
    () async {
      final original = Directory(p.join(root.path, 'Zendaya'));
      writeAlbumFiles(original);
      await scan();
      final albumId = (await albumsNamed('Zendaya')).single['id']! as String;
      final songIds = (await bindingsOf(albumId)).keys.toSet();

      // root/<album>/ files: the tags name the owner, as for the original.
      final copy = Directory(p.join(root.path, 'Zendaya Backup'));
      writeAlbumFiles(copy);
      await scan();
      expect(await albumsNamed('Zendaya'), hasLength(1));
      expect((await bindingsOf(albumId)).keys.toSet(), songIds);

      // Deleting the original folder leaves the copy playing the same songs.
      original.listSync().whereType<File>().forEach(
        (file) => file.deleteSync(),
      );
      await scan();
      expect(await albumsNamed('Zendaya'), hasLength(1));
      final bindings = await bindingsOf(albumId);
      expect(bindings.keys.toSet(), songIds);
      expect(
        bindings.values.every(
          (b) =>
              b.single.$2 && p.posix.dirname(b.single.$1) == folderKeyOf(copy),
        ),
        isTrue,
      );
    },
  );

  test('a different release with the same title stays separate', () async {
    final first = Directory(p.join(root.path, 'Hits 1999'));
    first.createSync();
    tags['a.mp3'] = _tags('Song A', album: 'Greatest Hits', duration: 200);
    tags['b.mp3'] = _tags('Song B', album: 'Greatest Hits', track: 2);
    File(p.join(first.path, 'a.mp3')).writeAsBytesSync([0]);
    File(p.join(first.path, 'b.mp3')).writeAsBytesSync([0]);
    await scan();

    // Another "Greatest Hits": other songs, and a re-recorded Song A
    // (a minute longer). Not verifiably the same recordings.
    final second = Directory(p.join(root.path, 'Hits 2010'));
    second.createSync();
    tags['a2.mp3'] = _tags('Song A', album: 'Greatest Hits', duration: 260);
    tags['c.mp3'] = _tags('Song C', album: 'Greatest Hits', track: 2);
    File(p.join(second.path, 'a2.mp3')).writeAsBytesSync([0]);
    File(p.join(second.path, 'c.mp3')).writeAsBytesSync([0]);
    await scan();

    expect(await albumsNamed('Greatest Hits'), hasLength(2));
  });

  test(
    'a one-song release is not absorbed by a larger same-titled one',
    () async {
      // A one-track release called "Nova" that still plays...
      final single = Directory(p.join(root.path, 'Nova Single'));
      single.createSync();
      tags['nova.mp3'] = _tags('Nova', artist: 'Nova', album: 'Nova');
      File(p.join(single.path, 'nova.mp3')).writeAsBytesSync([0]);
      await scan();

      // ...and a later 3-track album with the same title that includes it.
      final album = Directory(p.join(root.path, 'Nova Album'));
      album.createSync();
      for (final (index, title) in ['Nova', 'Two', 'Three'].indexed) {
        final name = 'album ${title.toLowerCase()}.mp3';
        tags[name] = _tags(
          title,
          artist: 'Nova',
          album: 'Nova',
          track: index + 1,
        );
        File(p.join(album.path, name)).writeAsBytesSync([0]);
      }
      await scan();

      expect(await albumsNamed('Nova'), hasLength(2));
    },
  );

  test('a Deluxe folder is an edition, never merged into Standard', () async {
    final standard = Directory(p.join(root.path, 'Zendaya'));
    writeAlbumFiles(standard);
    await scan();

    final deluxe = Directory(p.join(root.path, 'Zendaya (Deluxe)'));
    deluxe.createSync();
    for (final (index, (title, duration)) in _albumTracks.indexed) {
      final name = 'deluxe ${_fileName(title)}';
      tags[name] = _tags(
        title,
        album: 'Zendaya (Deluxe Edition)',
        track: index + 1,
        duration: duration,
      );
      File(p.join(deluxe.path, name)).writeAsBytesSync([0]);
    }
    tags['bonus.mp3'] = _tags(
      'Bonus',
      album: 'Zendaya (Deluxe Edition)',
      track: 12,
    );
    File(p.join(deluxe.path, 'bonus.mp3')).writeAsBytesSync([0]);
    await scan();

    final albums = await albumsNamed('Zendaya');
    expect(albums, hasLength(1));
    final db = await appDatabase.database;
    final editions = await db.query(
      DatabaseTables.albumEditions,
      where: 'album_id = ?',
      whereArgs: [albums.single['id']],
    );
    expect(editions, hasLength(2), reason: 'Standard and Deluxe');
  });

  test(
    'a moved live recording is not absorbed into the studio album',
    () async {
      final studio = Directory(p.join(root.path, 'Zendaya'));
      writeAlbumFiles(studio);
      await scan();
      final albumId = (await albumsNamed('Zendaya')).single['id']! as String;

      final live = Directory(p.join(root.path, 'Zendaya Live'));
      live.createSync();
      tags['replay live.mp3'] = _tags('Replay (Live)', duration: 300);
      File(p.join(live.path, 'replay live.mp3')).writeAsBytesSync([0]);
      await scan();

      final db = await appDatabase.database;
      final replays = await db.query(
        DatabaseTables.songs,
        where: 'canonical_title = ?',
        whereArgs: ['replay'],
      );
      expect(replays, hasLength(2), reason: 'the live version is its own song');
      final liveSong = replays.firstWhere((s) => s['version_label'] != null);
      expect(liveSong['album_id'], isNot(albumId));
    },
  );
}
