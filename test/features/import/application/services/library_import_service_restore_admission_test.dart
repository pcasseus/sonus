import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/core/database/library_mutation_coordinator.dart';
import 'package:sonus_next/features/import/application/models/import_batch.dart';
import 'package:sonus_next/features/import/application/models/import_batch_item.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/import_batch_executor.dart';
import 'package:sonus_next/features/import/application/services/library_import_service.dart';
import 'package:sonus_next/features/import/application/services/lyrics_ingestion_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/data/daos/import_batch_dao.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_import_batch_repository.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';
import 'package:sonus_next/features/import/domain/services/lyrics_source_reader.dart';
import 'package:sonus_next/features/player/data/daos/track_lyrics_dao.dart';
import 'package:sonus_next/features/player/data/repositories/sqlite_track_lyrics_repository.dart';

import '../../../../support/library_seed.dart';

class _FixedTags implements AudioMetadataReader {
  const _FixedTags();

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async {
    return const AudioMetadata(
      title: 'Fresh',
      artistName: 'Fresh Artist',
      albumTitle: 'Fresh Album',
      durationSeconds: 180,
      trackNumber: 1,
      discNumber: 1,
      isSingle: false,
      featuredArtists: [],
    );
  }
}

class _UnreadableTags implements AudioMetadataReader {
  const _UnreadableTags();

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async {
    throw const FormatException('Unreadable tags');
  }
}

/// Tags titled after the file name, counting each read.
class _TitleFromPath implements AudioMetadataReader {
  const _TitleFromPath(this.onRead);

  final void Function() onRead;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) async {
    onRead();
    final title = candidate.filePath.split('/').last.replaceAll('.mp3', '');

    return AudioMetadata(
      title: title,
      artistName: 'Fresh Artist',
      albumTitle: 'Fresh Album',
      durationSeconds: 180,
      trackNumber: title == 'First' ? 1 : 2,
      discNumber: 1,
      isSingle: false,
      featuredArtists: const [],
    );
  }
}

// SN-42 3B-3B-2B: the production ImportScope composition of normal imports.
// Reactivating an existing media binding must participate in restore
// admission like every other library write.
void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late LibraryImportService service;

  const knownPath = 'C:/Music/Artist a/Album a/01 Song.mp3';
  const knownNormalized = 'c:/music/artist a/album a/01 song.mp3';
  const stamp = '2026-10-01T00:00:00.000Z';
  final importedAt = DateTime.utc(2026, 10, 23, 12);

  setUp(() async {
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await database.database;
    await seedConnectedLibrary(db, key: 'a');

    // Built exactly as ImportScope builds it.
    service = LibraryImportService(
      metadataResolver: MetadataResolver(
        primaryReader: const _FixedTags(),
        fallbackReader: const _FixedTags(),
      ),
      atomicImporter: AtomicLibraryImporter(appDatabase: database),
      mediaFileBindingRepository: SqliteMediaFileBindingRepository(
        MediaFileBindingDao(db),
        appDatabase: database,
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedBinding({required bool available}) async {
    await (await database.database).insert(DatabaseTables.mediaFileBindings, {
      'id': 'binding-a',
      'song_id': 'song-a',
      'file_path': knownPath,
      'normalized_path': knownNormalized,
      'is_available': available ? 1 : 0,
      'created_at': stamp,
      'updated_at': stamp,
    });
  }

  Future<List<Map<String, Object?>>> bindings() async {
    return (await database.database).query(
      DatabaseTables.mediaFileBindings,
      orderBy: 'id',
    );
  }

  ImportCandidate candidate(String filePath, String normalizedPath) {
    return ImportCandidate(
      filePath: filePath,
      normalizedPath: normalizedPath,
      discoveredAt: importedAt,
    );
  }

  test(
    'binding reactivation cannot write during an exclusive restore',
    () async {
      await seedBinding(available: false);
      final before = await bindings();

      final entered = Completer<void>();
      final release = Completer<void>();
      final restore = database.mutationCoordinator.runExclusiveRestore(
        () async {
          entered.complete();
          await release.future;
        },
      );
      await entered.future;

      try {
        // A restore interrupts the import instead of failing the item;
        // nothing was written.
        await expectLater(
          service.importCandidate(
            candidate(knownPath, knownNormalized),
            now: importedAt,
          ),
          throwsA(isA<LibraryMutationUnavailable>()),
        );
        expect(await bindings(), before);
      } finally {
        release.complete();
        await restore;
      }

      // Once the restore ends, the same import relinks as before.
      final retried = await service.importCandidate(
        candidate(knownPath, knownNormalized),
        now: importedAt,
      );

      expect(retried.status, ImportResultStatus.relinked);
      expect(retried.songId, 'song-a');
      expect((await bindings()).single['is_available'], 1);
    },
  );

  group('restore rejection is an interruption, not an item failure', () {
    Future<T> whileRestoring<T>(Future<T> Function() body) async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final restore = database.mutationCoordinator.runExclusiveRestore(
        () async {
          entered.complete();
          await release.future;
        },
      );
      await entered.future;

      try {
        return await body();
      } finally {
        release.complete();
        await restore;
      }
    }

    LibraryImportService importing({
      AudioMetadataReader reader = const _FixedTags(),
      AtomicLibraryImporter? importer,
    }) {
      return LibraryImportService(
        metadataResolver: MetadataResolver(
          primaryReader: reader,
          fallbackReader: reader,
        ),
        atomicImporter:
            importer ?? AtomicLibraryImporter(appDatabase: database),
      );
    }

    test('a refused atomic import propagates and writes nothing', () async {
      final db = await database.database;
      final before = await snapshotDatabase(db);

      await whileRestoring(() async {
        await expectLater(
          importing().importCandidate(
            candidate('C:/Music/New/New.mp3', 'c:/music/new/new.mp3'),
            now: importedAt,
          ),
          throwsA(isA<LibraryMutationUnavailable>()),
        );
      });

      expect(await snapshotDatabase(db), before);
      expect(database.mutationCoordinator.activeMutations, 0);
    });

    test('unreadable metadata keeps its classification', () async {
      final result = await importing(reader: const _UnreadableTags())
          .importCandidate(
            candidate('C:/Music/New/New.mp3', 'c:/music/new/new.mp3'),
            now: importedAt,
          );

      expect(result.status, ImportResultStatus.failed);
      expect(result.failure?.type, ImportFailureType.metadataUnreadable);
    });

    test('a genuine persistence failure keeps its classification', () async {
      final result =
          await importing(
            importer: AtomicLibraryImporter(
              appDatabase: database,
              beforeBindingWrite: () async => throw StateError('disk full'),
            ),
          ).importCandidate(
            candidate('C:/Music/New/New.mp3', 'c:/music/new/new.mp3'),
            now: importedAt,
          );

      expect(result.status, ImportResultStatus.failed);
      expect(result.failure?.type, ImportFailureType.persistenceFailure);
    });

    test('an interrupted batch keeps earlier imports and reported progress '
        'and retries nothing', () async {
      final db = await database.database;
      final release = Completer<void>();
      Future<void>? restore;
      final progress = <int>[];
      var imports = 0;

      final executor = ImportBatchExecutor(
        libraryImportService: importing(
          reader: _TitleFromPath(() => imports++),
        ),
        batchRepository: SqliteImportBatchRepository(
          ImportBatchDao(db),
          appDatabase: database,
        ),
      );

      final batch = ImportBatch(
        id: 'batch-interrupted',
        createdAt: importedAt,
        items: [
          ImportBatchItem(
            candidate: candidate(
              'C:/Music/New/First.mp3',
              'c:/music/new/first.mp3',
            ),
          ),
          ImportBatchItem(
            candidate: candidate(
              'C:/Music/New/Second.mp3',
              'c:/music/new/second.mp3',
            ),
          ),
        ],
      );

      try {
        await expectLater(
          executor.execute(
            batch,
            startedAt: importedAt,
            onProgress: (current) {
              progress.add(current.completedCount);
              // The restore begins once the first item is recorded.
              if (current.completedCount == 1) {
                restore ??= database.mutationCoordinator.runExclusiveRestore(
                  () => release.future,
                );
              }
            },
          ),
          throwsA(isA<LibraryMutationUnavailable>()),
        );
      } finally {
        release.complete();
        await restore;
      }
      await pumpEventQueue();

      final titles = (await db.query(
        DatabaseTables.songs,
      )).map((row) => row['title']);
      expect(titles, containsAll(['Song', 'First']));
      expect(titles, isNot(contains('Second')));
      expect(progress, [0, 1]);
      expect(imports, 2);

      // Pre-existing bookkeeping: the interrupted batch stays recorded as
      // running with the progress it had reached.
      final record = (await db.query(
        DatabaseTables.importBatches,
        where: 'id = ?',
        whereArgs: ['batch-interrupted'],
      )).single;
      expect(record['status'], 'running');
      expect(record['imported_count'], 1);
    });
  });

  group('ordinary imports are unchanged', () {
    test('an unavailable binding is relinked and stamped', () async {
      await seedBinding(available: false);

      final result = await service.importCandidate(
        candidate(knownPath, knownNormalized),
        now: importedAt,
      );

      expect(result.status, ImportResultStatus.relinked);
      final binding = (await bindings()).single;
      expect(binding['is_available'], 1);
      expect(binding['updated_at'], importedAt.toIso8601String());
      expect(binding['last_seen_at'], importedAt.toIso8601String());
    });

    test('an available binding is skipped but refreshed', () async {
      await seedBinding(available: true);

      final result = await service.importCandidate(
        candidate(knownPath, knownNormalized),
        now: importedAt,
      );

      expect(result.status, ImportResultStatus.skipped);
      expect(
        (await bindings()).single['last_seen_at'],
        importedAt.toIso8601String(),
      );
    });

    test('a new file still imports through the atomic importer', () async {
      final result = await service.importCandidate(
        candidate('C:/Music/new.mp3', 'c:/music/new.mp3'),
        now: importedAt,
      );

      expect(result.status, ImportResultStatus.imported);
      final created = (await bindings()).single;
      expect(created['normalized_path'], 'c:/music/new.mp3');
      expect(created['is_available'], 1);
    });
  });

  // SN-42 3B-3B-3A: sidecar lyrics are written after the song import
  // commits, through the coordinated ImportScope lyrics repository.
  group('sidecar lyrics', () {
    Future<LibraryImportService> withLyrics(_ScriptedSidecar sidecar) async {
      final db = await database.database;

      return LibraryImportService(
        metadataResolver: MetadataResolver(
          primaryReader: const _FixedTags(),
          fallbackReader: const _FixedTags(),
        ),
        atomicImporter: AtomicLibraryImporter(appDatabase: database),
        mediaFileBindingRepository: SqliteMediaFileBindingRepository(
          MediaFileBindingDao(db),
          appDatabase: database,
        ),
        lyricsIngestionService: LyricsIngestionService(
          sourceReader: sidecar,
          trackLyricsRepository: SqliteTrackLyricsRepository(
            TrackLyricsDao(db),
            appDatabase: database,
          ),
        ),
      );
    }

    ImportCandidate withSidecar(String filePath, String normalizedPath) {
      return ImportCandidate(
        filePath: filePath,
        normalizedPath: normalizedPath,
        lyricsPath: '$filePath.lrc',
        discoveredAt: importedAt,
      );
    }

    // seedConnectedLibrary gives song-a the plain lyrics 'Lyrics a'.
    Future<Map<String, Object?>?> lyricsOf(String songId) async {
      final rows = await (await database.database).query(
        DatabaseTables.trackLyrics,
        where: 'song_id = ?',
        whereArgs: [songId],
      );
      return rows.isEmpty ? null : rows.single;
    }

    test('a restore that begins during the sidecar read rejects the lyrics '
        'write and propagates', () async {
      await seedBinding(available: false);
      final lyricsBefore = await lyricsOf('song-a');

      final release = Completer<void>();
      Future<void>? restore;

      final sidecar = _ScriptedSidecar((_) async {
        // The song work has committed; a restore starts while the file
        // is still being read.
        restore ??= database.mutationCoordinator.runExclusiveRestore(
          () => release.future,
        );
        return '[00:01.00]New line';
      });

      try {
        await expectLater(
          (await withLyrics(
            sidecar,
          )).importCandidate(withSidecar(knownPath, knownNormalized)),
          throwsA(isA<LibraryMutationUnavailable>()),
        );

        expect(await lyricsOf('song-a'), lyricsBefore);
        // The binding refresh committed before the restore began.
        expect((await bindings()).single['is_available'], 1);
      } finally {
        release.complete();
        await restore;
      }

      // After the restore ends, a later rescan ingests the sidecar.
      final rescan = await (await withLyrics(
        _ScriptedSidecar((_) async => '[00:01.00]New line'),
      )).importCandidate(withSidecar(knownPath, knownNormalized));

      expect(rescan.status, ImportResultStatus.skipped);
      final lyrics = await lyricsOf('song-a');
      expect(lyrics?['synced_text'], '[00:01.00]New line');
      expect(lyrics?['plain_text'], isNull);
    });

    test(
      'rejection after a new import propagates and keeps the song',
      () async {
        final release = Completer<void>();
        Future<void>? restore;

        final sidecar = _ScriptedSidecar((_) async {
          restore ??= database.mutationCoordinator.runExclusiveRestore(
            () => release.future,
          );
          return 'Plain words';
        });

        try {
          // Not reported as unreadable metadata: the rejection escapes.
          await expectLater(
            (await withLyrics(sidecar)).importCandidate(
              withSidecar('C:/Music/new.mp3', 'c:/music/new.mp3'),
            ),
            throwsA(isA<LibraryMutationUnavailable>()),
          );

          final created = (await bindings()).single;
          expect(created['normalized_path'], 'c:/music/new.mp3');
          expect(await lyricsOf(created['song_id']! as String), isNull);
        } finally {
          release.complete();
          await restore;
        }
      },
    );

    test('an ordinary sidecar read failure stays best-effort', () async {
      await seedBinding(available: false);
      final lyricsBefore = await lyricsOf('song-a');

      final result = await (await withLyrics(
        _ScriptedSidecar((_) async => throw const _SidecarUnreadable()),
      )).importCandidate(withSidecar(knownPath, knownNormalized));

      expect(result.status, ImportResultStatus.relinked);
      expect(await lyricsOf('song-a'), lyricsBefore);
    });

    test('an ordinary lyrics persistence failure stays best-effort', () async {
      await seedBinding(available: false);
      final lyricsBefore = await lyricsOf('song-a');

      await (await database.database).execute('''
        CREATE TRIGGER reject_lyrics
        BEFORE UPDATE ON ${DatabaseTables.trackLyrics}
        BEGIN
          SELECT RAISE(ABORT, 'test rejection');
        END
      ''');

      final result = await (await withLyrics(
        _ScriptedSidecar((_) async => 'Plain words'),
      )).importCandidate(withSidecar(knownPath, knownNormalized));

      expect(result.status, ImportResultStatus.relinked);
      expect(await lyricsOf('song-a'), lyricsBefore);
    });

    test('plain sidecar text is stored as plain lyrics', () async {
      await seedBinding(available: true);

      final result = await (await withLyrics(
        _ScriptedSidecar((_) async => 'Plain words'),
      )).importCandidate(withSidecar(knownPath, knownNormalized));

      expect(result.status, ImportResultStatus.skipped);
      final lyrics = await lyricsOf('song-a');
      expect(lyrics?['plain_text'], 'Plain words');
      expect(lyrics?['synced_text'], isNull);
    });

    test('a timestamped sidecar on a new import is stored as synced', () async {
      final result = await (await withLyrics(
        _ScriptedSidecar((_) async => '[00:02.00]Second\n[00:01.00]First'),
      )).importCandidate(withSidecar('C:/Music/new.mp3', 'c:/music/new.mp3'));

      expect(result.status, ImportResultStatus.imported);
      final lyrics = await lyricsOf(result.songId!);
      expect(lyrics?['synced_text'], '[00:02.00]Second\n[00:01.00]First');
      expect(lyrics?['plain_text'], isNull);
      expect(database.mutationCoordinator.activeMutations, 0);
    });
  });
}

class _ScriptedSidecar implements LyricsSourceReader {
  _ScriptedSidecar(this.onRead);

  final Future<String?> Function(ImportCandidate candidate) onRead;

  @override
  Future<String?> read(ImportCandidate candidate) => onRead(candidate);
}

/// An ordinary I/O-style failure, distinct from restore admission.
class _SidecarUnreadable implements Exception {
  const _SidecarUnreadable();
}
