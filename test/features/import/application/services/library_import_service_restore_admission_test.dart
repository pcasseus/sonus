import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/core/database/database_tables.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/library_import_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/data/daos/media_file_binding_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_media_file_binding_repository.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';

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
        final result = await service.importCandidate(
          candidate(knownPath, knownNormalized),
          now: importedAt,
        );

        // The rejected write surfaces as a failed item; nothing was written.
        expect(result.status, ImportResultStatus.failed);
        expect(result.failure?.type, ImportFailureType.persistenceFailure);
        expect(result.failure?.message, contains('LibraryMutationUnavailable'));
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
}
