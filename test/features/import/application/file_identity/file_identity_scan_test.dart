// App Update 1.2, BUG-09: a file edited, renamed, moved or rewritten outside
// Sonus stays the same song. Real scans, through the app's import workflow,
// of disposable MP3 files and a disposable database (never the user's).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/events/library_change_signal.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/existing_song_tag_updater.dart';
import 'package:sonus_next/features/import/application/services/file_identity_service.dart';
import 'package:sonus_next/features/import/application/services/import_batch_executor.dart';
import 'package:sonus_next/features/import/application/services/import_source_reconciliation_service.dart';
import 'package:sonus_next/features/import/application/services/import_workflow_service.dart';
import 'package:sonus_next/features/import/application/services/library_import_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/application/services/possible_recording_review_service.dart';
import 'package:sonus_next/features/import/data/daos/import_batch_dao.dart';
import 'package:sonus_next/features/import/data/daos/import_source_dao.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_import_batch_repository.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_import_source_repository.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/data/services/audio_byte_sources.dart';
import 'package:sonus_next/features/import/data/services/file_system_import_candidate_discovery.dart';
import 'package:sonus_next/features/import/data/services/possible_recording_store.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/models/pending_possible_recording.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';
import 'package:sonus_next/features/library/application/services/permanent_deletion_service.dart';
import 'package:sonus_next/features/library/data/daos/song_dao.dart';
import 'package:sonus_next/features/library/data/repositories/sqlite_song_repository.dart';
import 'package:sonus_next/features/library/domain/deletion/permanent_deletion_impact.dart';

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

AudioMetadata _tags(String title, {int track = 1, int duration = 197}) =>
    AudioMetadata(
      title: title,
      artistName: 'Justin Bieber',
      albumTitle: 'Purpose',
      durationSeconds: duration,
      trackNumber: track,
      discNumber: 1,
      isSingle: false,
      featuredArtists: const [],
    );

const _userId = 'user_1';

void main() {
  sqfliteFfiInit();

  late Directory sandbox;
  late Directory album;
  late AppDatabase appDatabase;
  late Map<String, AudioMetadata> tags;
  late Map<String, String> preferences;
  late PossibleRecordingStore store;
  var scanNumber = 0;
  String? sourceId;
  final base = DateTime.utc(2026, 11, 9, 12);

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('sonus_file_identity_');
    album = Directory(p.join(sandbox.path, 'Music', 'Justin Bieber', 'Purpose'))
      ..createSync(recursive: true);
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(sandbox.path, 'library.db'),
    );
    tags = {};
    preferences = {};
    store = PossibleRecordingStore.forTesting(
      getString: (key) async => preferences[key],
      setString: (key, value) async => preferences[key] = value,
    );
    scanNumber = 0;
    sourceId = null;
  });

  tearDown(() async {
    await appDatabase.close();
    await sandbox.delete(recursive: true);
  });

  MetadataResolver resolver() => MetadataResolver(
    primaryReader: _TagsByFileName(tags),
    fallbackReader: _TagsByFileName(tags),
  );

  FileIdentityService identityService() => FileIdentityService(
    appDatabase: appDatabase,
    openSource: audioByteSourceOpener(),
    metadataResolver: resolver(),
    tagUpdater: const ExistingSongTagUpdater(userId: _userId),
    reviewStore: store,
  );

  LibraryImportService importService(Database db) => LibraryImportService(
    metadataResolver: resolver(),
    atomicImporter: AtomicLibraryImporter(
      appDatabase: appDatabase,
      userId: _userId,
    ),
    mediaFileBindingRepository: SqliteMediaFileBindingRepository(
      MediaFileBindingDao(db),
    ),
    possibleRecordingStore: store,
    fileIdentityService: identityService(),
  );

  /// One scan of the source through the real workflow. Returns each file's
  /// result by file name.
  Future<Map<String, ImportResult>> scan({bool withIdentity = true}) async {
    final db = await appDatabase.database;
    final createdAt = base.add(Duration(hours: ++scanNumber));
    final bindings = SqliteMediaFileBindingRepository(MediaFileBindingDao(db));
    final workflow = ImportWorkflowService(
      candidateDiscovery: const FileSystemImportCandidateDiscovery(),
      batchRunner: ImportBatchExecutor(
        libraryImportService: LibraryImportService(
          metadataResolver: resolver(),
          atomicImporter: AtomicLibraryImporter(
            appDatabase: appDatabase,
            userId: _userId,
          ),
          mediaFileBindingRepository: bindings,
          possibleRecordingStore: store,
          fileIdentityService: withIdentity ? identityService() : null,
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
    );
    final completedAt = createdAt.add(const Duration(minutes: 1));
    final results = <String, ImportResult>{};
    void collect(dynamic batch) {
      for (final item in batch.items) {
        final result = item.result as ImportResult?;
        if (result != null) {
          results[p.basename(result.filePath).toLowerCase()] = result;
        }
      }
    }

    final root = p.join(sandbox.path, 'Music');
    if (sourceId == null) {
      await workflow.importStructuredFolder(
        root,
        createdAt: createdAt,
        startedAt: createdAt,
        completedAt: completedAt,
        onProgress: collect,
      );
      sourceId = 'source_music';
    } else {
      await workflow.rescanSource(
        sourceId!,
        createdAt: createdAt,
        startedAt: createdAt,
        completedAt: completedAt,
        onProgress: collect,
      );
    }
    return results;
  }

  /// Writes [name] with the audio of [seed] and an ID3 tag titled
  /// [tagTitle]; its tags as Sonus reads them are [metadata].
  File writeSong(
    String name,
    AudioMetadata metadata, {
    required int seed,
    String? tagTitle,
    Directory? folder,
    DateTime? modified,
  }) {
    final file = File(p.join((folder ?? album).path, name));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      syntheticMp3(
        syntheticAudio(frames: 80, seed: seed),
        leading: [id3v2Tag(title: tagTitle ?? metadata.title)],
      ),
    );
    file.setLastModifiedSync(modified ?? base);
    tags[name.toLowerCase()] = metadata;
    return file;
  }

  Future<List<Map<String, Object?>>> songs() async =>
      (await appDatabase.database).query(DatabaseTables.songs, orderBy: 'id');

  Future<Map<String, Object?>> bindingOf(String songId) async =>
      (await (await appDatabase.database).query(
        DatabaseTables.mediaFileBindings,
        where: 'song_id = ?',
        whereArgs: [songId],
      )).single;

  Future<String?> fieldAuthority(String songId, String field) async {
    final rows = await (await appDatabase.database).query(
      DatabaseTables.metadataFieldStates,
      where: "entity_type = 'song' AND entity_id = ? AND field_name = ?",
      whereArgs: [songId, field],
    );
    return rows.isEmpty ? null : rows.single['authority'] as String?;
  }

  Future<Map<String, List<Map<String, Object?>>>> libraryState() async {
    final db = await appDatabase.database;
    return {
      for (final table in [
        DatabaseTables.songs,
        DatabaseTables.mediaFileBindings,
        DatabaseTables.albumEditionTracks,
        DatabaseTables.metadataFieldStates,
        DatabaseTables.albums,
        DatabaseTables.albumEditions,
        'sync_outbox',
      ])
        table: await db.rawQuery('SELECT * FROM $table ORDER BY rowid'),
    };
  }

  Future<String> importOne({
    String name = 'ill show you.mp3',
    String title = 'Ill Show You',
    int track = 3,
    int seed = 1,
  }) async {
    writeSong(name, _tags(title, track: track), seed: seed);
    final result = (await scan())[name]!;
    expect(result.status, ImportResultStatus.imported);
    return result.songId!;
  }

  group('a known file', () {
    test('first sight records its audio identity from its own bytes', () async {
      final songId = await importOne();
      final binding = await bindingOf(songId);
      expect(binding['audio_signature'], startsWith('v1:'));
      expect(binding['audio_full_hash'], isNotNull);
      expect(binding['signature_version'], 1);
      expect(binding['file_size_bytes'], isNotNull);
      expect(binding['modified_at'], isNotNull);
    });

    test('tags edited in place update the same song: title, number and its '
        'place on the edition', () async {
      final songId = await importOne();
      final before = await bindingOf(songId);

      writeSong(
        'ill show you.mp3',
        _tags("I'll Show You", track: 2),
        seed: 1,
        modified: base.add(const Duration(days: 1)),
      );
      final result = (await scan())['ill show you.mp3']!;

      expect(result.skipReason, ImportSkipReason.knownFile);
      final all = await songs();
      expect(all, hasLength(1));
      expect(all.single['id'], songId);
      expect(all.single['title'], "I'll Show You");
      expect(all.single['canonical_title'], "i'll show you");
      expect(all.single['track_number'], 2);
      final listing = (await (await appDatabase.database).query(
        DatabaseTables.albumEditionTracks,
        where: 'song_id = ?',
        whereArgs: [songId],
      )).single;
      expect(listing['track_number'], 2);
      expect(await fieldAuthority(songId, 'title'), 'imported');
      final after = await bindingOf(songId);
      expect(after['id'], before['id']);
      expect(after['audio_full_hash'], before['audio_full_hash']);
      expect(after['modified_at'], isNot(before['modified_at']));
    });

    test(
      'a title set in Sonus and a hand-made track number are kept',
      () async {
        final songId = await importOne();
        final db = await appDatabase.database;
        await db.update(
          DatabaseTables.songs,
          {'title': 'My Own Title'},
          where: 'id = ?',
          whereArgs: [songId],
        );
        await db.update(
          DatabaseTables.metadataFieldStates,
          {'authority': 'manual', 'source': 'user'},
          where: "entity_id = ? AND field_name = 'title'",
          whereArgs: [songId],
        );
        await db.update(
          DatabaseTables.albumEditionTracks,
          {'numbering_authority': 'manual'},
          where: 'song_id = ?',
          whereArgs: [songId],
        );

        writeSong(
          'ill show you.mp3',
          _tags("I'll Show You", track: 2),
          seed: 1,
          modified: base.add(const Duration(days: 1)),
        );
        await scan();

        final song = (await songs()).single;
        expect(song['title'], 'My Own Title');
        final listing = (await db.query(
          DatabaseTables.albumEditionTracks,
          where: 'song_id = ?',
          whereArgs: [songId],
        )).single;
        expect(listing['track_number'], 3);
      },
    );

    test('changed audio at the same location waits for review; nothing '
        'changes', () async {
      final songId = await importOne();
      final before = await libraryState();

      writeSong(
        'ill show you.mp3',
        _tags('Ill Show You', track: 3),
        seed: 99,
        modified: base.add(const Duration(days: 1)),
      );
      await scan();

      final after = await libraryState();
      expect(after[DatabaseTables.songs], before[DatabaseTables.songs]);
      expect(
        (await bindingOf(songId))['audio_full_hash'],
        before[DatabaseTables.mediaFileBindings]!.single['audio_full_hash'],
      );
      final pending = await store.getPending();
      expect(pending.single.kind, PendingFileReviewKind.audioChanged);
      expect(pending.single.candidateSongId, songId);
    });

    test('repeated scans are idempotent: nothing is written after the '
        'first', () async {
      writeSong('ill show you.mp3', _tags('Ill Show You', track: 3), seed: 1);
      writeSong('sorry.mp3', _tags('Sorry', track: 5, duration: 198), seed: 2);
      await scan();
      final first = await libraryState();

      for (var pass = 0; pass < 3; pass++) {
        final results = await scan();
        expect(
          results.values.map((r) => r.skipReason),
          everyElement(ImportSkipReason.knownFile),
        );
      }
      final after = await libraryState();
      expect(after[DatabaseTables.songs], first[DatabaseTables.songs]);
      expect(
        after[DatabaseTables.metadataFieldStates],
        first[DatabaseTables.metadataFieldStates],
      );
      expect(after['sync_outbox'], first['sync_outbox']);
      expect(
        [
          for (final b in after[DatabaseTables.mediaFileBindings]!)
            {...b}
              ..remove('last_seen_at')
              ..remove('updated_at'),
        ],
        [
          for (final b in first[DatabaseTables.mediaFileBindings]!)
            {...b}
              ..remove('last_seen_at')
              ..remove('updated_at'),
        ],
      );
    });
  });

  group('a renamed, moved or rewritten file', () {
    test(
      'renamed with a new title (the Purpose case) keeps its Song ID',
      () async {
        final songId = await importOne();
        File(
          p.join(album.path, 'ill show you.mp3'),
        ).renameSync(p.join(album.path, "i'll show you.mp3"));
        tags["i'll show you.mp3"] = _tags("I'll Show You", track: 2);

        final result = (await scan())["i'll show you.mp3"]!;

        expect(result.status, ImportResultStatus.relinked);
        expect(result.songId, songId);
        final all = await songs();
        expect(all, hasLength(1), reason: 'no duplicate song');
        expect(all.single['title'], "I'll Show You");
        final binding = await bindingOf(songId);
        expect(binding['normalized_path'], endsWith("i'll show you.mp3"));
        expect(binding['is_available'], 1);
        expect(await store.getPending(), isEmpty);
      },
    );

    test('a whole folder moved elsewhere keeps every Song ID', () async {
      writeSong('ill show you.mp3', _tags('Ill Show You', track: 3), seed: 1);
      writeSong('sorry.mp3', _tags('Sorry', track: 5, duration: 198), seed: 2);
      await scan();
      final ids = {for (final s in await songs()) s['id']};

      final moved = Directory(
        p.join(sandbox.path, 'Music', 'Justin Bieber', 'Purpose (Deluxe)'),
      );
      album.renameSync(moved.path);

      final results = await scan();
      expect(
        results.values.map((r) => r.status),
        everyElement(ImportResultStatus.relinked),
      );
      expect({for (final s in await songs()) s['id']}, ids);
      for (final id in ids) {
        final binding = await bindingOf(id! as String);
        expect(binding['is_available'], 1);
        expect(binding['normalized_path'], contains('purpose (deluxe)'));
      }
    });

    test('rewritten as a new file with new tags keeps its Song ID', () async {
      final songId = await importOne();
      File(p.join(album.path, 'ill show you.mp3')).deleteSync();
      writeSong(
        '02 i_ll show you.mp3',
        _tags("I'll Show You", track: 2),
        seed: 1,
        tagTitle: 'Rewritten by another editor',
        modified: base.add(const Duration(days: 2)),
      );

      final result = (await scan())['02 i_ll show you.mp3']!;
      expect(result.status, ImportResultStatus.relinked);
      expect(result.songId, songId);
      expect(await songs(), hasLength(1));
    });

    test(
      'a byte-identical copy beside the original is not a new song',
      () async {
        final songId = await importOne();
        writeSong('copy.mp3', _tags('Ill Show You (copy)', track: 3), seed: 1);

        final result = (await scan())['copy.mp3']!;
        expect(result.skipReason, ImportSkipReason.duplicateRecording);
        expect(result.songId, songId);
        expect(await songs(), hasLength(1));
      },
    );
  });

  group('when the audio cannot prove it', () {
    test('a different recording with the same title and length, while the '
        'song is missing, waits for review instead of replacing it', () async {
      final songId = await importOne();
      File(p.join(album.path, 'ill show you.mp3')).deleteSync();
      writeSong(
        "i'll show you (live).mp3",
        _tags("I'll Show You", track: 3),
        seed: 50,
      );

      final result = (await scan())["i'll show you (live).mp3"]!;
      expect(result.skipReason, ImportSkipReason.awaitingFileReview);
      expect(await songs(), hasLength(1), reason: 'no new song meanwhile');
      expect((await bindingOf(songId))['is_available'], 0);
      final pending = (await store.getPending()).single;
      expect(pending.kind, PendingFileReviewKind.possibleReplacedFile);
      expect(pending.candidateSongId, songId);
    });

    test('a different recording with the same title beside the original '
        'imports as its own song', () async {
      final songId = await importOne();
      writeSong(
        "i'll show you (live).mp3",
        _tags("I'll Show You", track: 3),
        seed: 50,
      );

      await scan();
      final all = await songs();
      expect(all, hasLength(2));
      expect((await bindingOf(songId))['is_available'], 1);
    });

    test('the same sampled signature with different audio in the middle is '
        'never relinked: the whole audio must match', () async {
      final songId = await importOne();
      final original = File(p.join(album.path, 'ill show you.mp3'));
      final bytes = original.readAsBytesSync();
      original.deleteSync();
      // One byte changed half-way: outside both sampled ends.
      bytes[bytes.length ~/ 2] ^= 0x01;
      final renamed = File(p.join(album.path, "i'll show you.mp3"))
        ..writeAsBytesSync(bytes);
      renamed.setLastModifiedSync(base.add(const Duration(days: 1)));
      tags["i'll show you.mp3"] = _tags("I'll Show You", track: 2);

      final result = (await scan())["i'll show you.mp3"]!;

      expect(result.skipReason, ImportSkipReason.awaitingFileReview);
      expect((await bindingOf(songId))['is_available'], 0);
      expect(await songs(), hasLength(1));
      expect(
        (await store.getPending()).single.kind,
        PendingFileReviewKind.possibleReplacedFile,
      );
    });

    test('a known file whose audio can no longer be read with confidence is '
        'not reported as changed audio', () async {
      final songId = await importOne();
      final before = await bindingOf(songId);
      File(p.join(album.path, 'ill show you.mp3'))
        ..writeAsBytesSync(List<int>.filled(4000, 7))
        ..setLastModifiedSync(base.add(const Duration(days: 1)));

      await scan();

      expect(await store.getPending(), isEmpty);
      expect(
        (await bindingOf(songId))['audio_full_hash'],
        before['audio_full_hash'],
      );
    });

    test('a known file that cannot be read now is left as it is', () async {
      final songId = await importOne();
      final before = await bindingOf(songId);
      final service = FileIdentityService(
        appDatabase: appDatabase,
        openSource: (_) async => null,
        metadataResolver: resolver(),
        tagUpdater: const ExistingSongTagUpdater(),
        reviewStore: store,
      );

      final plan = await service.plan([
        ImportCandidate(
          filePath: before['file_path']! as String,
          normalizedPath: before['normalized_path']! as String,
          discoveredAt: base,
          fileSizeBytes: 1,
          modifiedAt: base.add(const Duration(days: 9)),
        ),
      ], now: base);

      expect(plan.results, isEmpty);
      expect(await bindingOf(songId), before);
      expect(await store.getPending(), isEmpty);
    });

    test(
      'audio matching two missing songs waits for the user to pick',
      () async {
        writeSong('a.mp3', _tags('Song A', track: 1), seed: 7);
        await scan();
        final first = (await songs()).single['id']! as String;
        // A second song whose file has the very same audio (an older
        // version's duplicate), and then both files disappear.
        final db = await appDatabase.database;
        final song = (await songs()).single;
        await db.insert(DatabaseTables.songs, {
          ...song,
          'id': 'song_twin',
          'title': 'Song A (twin)',
          'canonical_title': 'song a (twin)',
        });
        final binding = await bindingOf(first);
        await db.insert(DatabaseTables.mediaFileBindings, {
          ...binding,
          'id': 'binding_twin',
          'song_id': 'song_twin',
          'normalized_path': '${binding['normalized_path']}.twin',
          'file_path': '${binding['file_path']}.twin',
        });
        File(
          p.join(album.path, 'a.mp3'),
        ).renameSync(p.join(album.path, 'b.mp3'));
        tags['b.mp3'] = _tags('Song A', track: 1);

        final result = (await scan())['b.mp3']!;
        expect(result.skipReason, ImportSkipReason.awaitingFileReview);
        final pending = (await store.getPending()).single;
        expect(pending.candidateSongIds.toSet(), {first, 'song_twin'});
        expect(await songs(), hasLength(2));
      },
    );

    test('the Purpose duplicates as they happened: files known from before '
        'version 43 are held for review, and no song is created', () async {
      // Before audio identity, files were known by location only.
      writeSong('ill show you.mp3', _tags('Ill Show You', track: 3), seed: 1);
      writeSong(
        'where are u now.mp3',
        _tags('Where Are U Now', track: 12, duration: 240),
        seed: 2,
      );
      await scan(withIdentity: false);
      expect(await songs(), hasLength(2));

      File(
        p.join(album.path, 'ill show you.mp3'),
      ).renameSync(p.join(album.path, "i'll show you.mp3"));
      File(
        p.join(album.path, 'where are u now.mp3'),
      ).renameSync(p.join(album.path, 'where are ü now.mp3'));
      tags["i'll show you.mp3"] = _tags("I'll Show You", track: 2);
      tags['where are ü now.mp3'] = _tags(
        'Where Are Ü Now',
        track: 21,
        duration: 240,
      );

      final results = await scan();

      expect(await songs(), hasLength(2), reason: 'no duplicates');
      expect(
        results.values.map((r) => r.skipReason),
        everyElement(ImportSkipReason.awaitingFileReview),
      );
      expect(
        (await store.getPending()).map((e) => e.kind),
        everyElement(PendingFileReviewKind.possibleReplacedFile),
      );
    });
  });

  group('the user decides in Import Review', () {
    Future<PossibleRecordingReviewService> reviewService() async =>
        PossibleRecordingReviewService(
          store: store,
          libraryImportService: importService(await appDatabase.database),
          mediaFileBindingRepository: SqliteMediaFileBindingRepository(
            MediaFileBindingDao(await appDatabase.database),
          ),
          songRepository: SqliteSongRepository(
            SongDao(await appDatabase.database),
          ),
          fileIdentityService: identityService(),
          now: () => base.add(const Duration(days: 5)),
        );

    Future<(String, PendingPossibleRecording)> legacyRename() async {
      writeSong('ill show you.mp3', _tags('Ill Show You', track: 3), seed: 1);
      await scan(withIdentity: false);
      final songId = (await songs()).single['id']! as String;
      File(
        p.join(album.path, 'ill show you.mp3'),
      ).renameSync(p.join(album.path, "i'll show you.mp3"));
      tags["i'll show you.mp3"] = _tags("I'll Show You", track: 2);
      await scan();
      return (songId, (await store.getPending()).single);
    }

    test('"Same song" attaches the file to the song: same Song ID, title '
        'updated, nothing new', () async {
      final (songId, entry) = await legacyRename();

      final result = await (await reviewService()).useFileForSong(
        entry,
        songId: songId,
      );

      expect(result.outcome, PossibleRecordingOutcome.usedForSong);
      final all = await songs();
      expect(all, hasLength(1));
      expect(all.single['id'], songId);
      expect(all.single['title'], "I'll Show You");
      final binding = await bindingOf(songId);
      expect(binding['is_available'], 1);
      expect(binding['normalized_path'], endsWith("i'll show you.mp3"));
      expect(binding['audio_full_hash'], isNotNull);
      expect(await store.getPending(), isEmpty);

      // Afterwards the file is simply known.
      final again = (await scan())["i'll show you.mp3"]!;
      expect(again.skipReason, ImportSkipReason.knownFile);
    });

    test('"Different song" adds it as its own song once', () async {
      final (songId, entry) = await legacyRename();

      final result = await (await reviewService()).importSeparately(entry);

      expect(result.outcome, PossibleRecordingOutcome.imported);
      expect(await songs(), hasLength(2));
      expect((await bindingOf(songId))['is_available'], 0);
      final again = await scan();
      expect(again.values.single.skipReason, ImportSkipReason.knownFile);
      expect(await songs(), hasLength(2));
    });

    test('"Keep as this song" accepts changed audio', () async {
      final songId = await importOne();
      writeSong(
        'ill show you.mp3',
        _tags('Ill Show You', track: 3),
        seed: 99,
        modified: base.add(const Duration(days: 1)),
      );
      await scan();
      final entry = (await store.getPending()).single;
      final before = (await bindingOf(songId))['audio_full_hash'];

      final result = await (await reviewService()).keepChangedAudio(entry);

      expect(result.outcome, PossibleRecordingOutcome.audioKept);
      expect((await bindingOf(songId))['audio_full_hash'], isNot(before));
      expect(await store.getPending(), isEmpty);
      expect(
        (await scan()).values.single.skipReason,
        ImportSkipReason.knownFile,
      );
      expect(await store.getPending(), isEmpty);
    });
  });

  group('permanent deletion', () {
    PermanentDeletionService deletion() => PermanentDeletionService(
      appDatabase: appDatabase,
      userId: _userId,
      isCloudLinked: (_) async => false,
      now: () => base.add(const Duration(days: 3)),
      generateOutboxId: () => 'outbox_${DateTime.now().microsecondsSinceEpoch}',
      generateOperationId: () => 'operation_1',
      changes: LibraryChangeSignal(),
    );

    test('a renamed copy of a deleted song stays out', () async {
      final songId = await importOne();
      // Everything already synced: deletion waits for pending cloud writes.
      await (await appDatabase.database).delete('sync_outbox');
      final service = deletion();
      await service.delete(
        await service.preview(PermanentDeletionTarget.song(songId)),
      );
      final deleted = await (await appDatabase.database).query(
        DatabaseTables.deletedAudioSignatures,
      );
      expect(deleted.single['song_id'], songId);

      File(
        p.join(album.path, 'ill show you.mp3'),
      ).renameSync(p.join(album.path, 'ill show you (again).mp3'));
      tags['ill show you (again).mp3'] = _tags('Ill Show You', track: 3);

      final result = (await scan())['ill show you (again).mp3']!;
      expect(result.skipReason, ImportSkipReason.deletedFromLibrary);
      expect(await songs(), isEmpty);
    });

    test('a file never read leaves no made-up audio record', () async {
      writeSong('ill show you.mp3', _tags('Ill Show You', track: 3), seed: 1);
      await scan(withIdentity: false);
      final songId = (await songs()).single['id']! as String;
      // Everything already synced: deletion waits for pending cloud writes.
      await (await appDatabase.database).delete('sync_outbox');
      final service = deletion();
      await service.delete(
        await service.preview(PermanentDeletionTarget.song(songId)),
      );

      expect(
        await (await appDatabase.database).query(
          DatabaseTables.deletedAudioSignatures,
        ),
        isEmpty,
      );
    });
  });

  group('sync and restore', () {
    test(
      'a rename with new tags sends only an update of the same song',
      () async {
        final songId = await importOne();
        final db = await appDatabase.database;
        final outboxBefore = await db.query('sync_outbox');

        File(
          p.join(album.path, 'ill show you.mp3'),
        ).renameSync(p.join(album.path, "i'll show you.mp3"));
        tags["i'll show you.mp3"] = _tags("I'll Show You", track: 2);
        await scan();

        // The outbox keeps one row per record: the song's row is updated, and
        // no record of any other id appears.
        final outboxAfter = await db.query('sync_outbox');
        Set<(Object?, Object?)> ids(List<Map<String, Object?>> rows) => {
          for (final row in rows) (row['entity_type'], row['entity_id']),
        };
        expect(ids(outboxAfter), ids(outboxBefore));
        int revision(List<Map<String, Object?>> rows) =>
            rows.singleWhere(
                  (r) => r['entity_id'] == songId,
                )['mutation_revision']!
                as int;
        expect(revision(outboxAfter), greaterThan(revision(outboxBefore)));
        expect(
          outboxAfter.singleWhere((r) => r['entity_id'] == songId)['operation'],
          'upsert',
        );
      },
    );

    test('songs restored without their file links (a new device) are bound '
        'again by a scan, with no new song', () async {
      final songId = await importOne();
      final db = await appDatabase.database;
      // A restore brings portable tables only; file links are device-local.
      await db.delete(DatabaseTables.mediaFileBindings);

      final result = (await scan())['ill show you.mp3']!;
      expect(result.status, ImportResultStatus.relinked);
      expect(result.songId, songId);
      expect(await songs(), hasLength(1));
      expect((await bindingOf(songId))['audio_signature'], isNotNull);
    });
  });
}
