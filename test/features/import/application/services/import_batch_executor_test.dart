import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:sonus_next/core/database/app_database.dart';
import 'package:sonus_next/features/import/application/models/import_batch.dart';
import 'package:sonus_next/features/import/application/models/import_batch_item.dart';
import 'package:sonus_next/features/import/application/services/atomic_library_importer.dart';
import 'package:sonus_next/features/import/application/services/import_batch_executor.dart';
import 'package:sonus_next/features/import/application/services/library_import_service.dart';
import 'package:sonus_next/features/import/application/services/metadata_resolver.dart';
import 'package:sonus_next/features/import/data/daos/import_batch_dao.dart';
import 'package:sonus_next/features/import/data/repositories/sqlite_import_batch_repository.dart';
import 'package:sonus_next/features/import/domain/entities/import_batch_record.dart';
import 'package:sonus_next/features/import/domain/models/audio_metadata.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/services/audio_metadata_reader.dart';

class CallbackAudioMetadataReader implements AudioMetadataReader {
  CallbackAudioMetadataReader(this.callback);

  final Future<AudioMetadata> Function(ImportCandidate candidate) callback;

  @override
  Future<AudioMetadata> read(ImportCandidate candidate) {
    return callback(candidate);
  }
}

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late SqliteImportBatchRepository batchRepository;

  final createdAt = DateTime.utc(2026, 9, 10, 12);
  final startedAt = DateTime.utc(2026, 9, 10, 12, 1);
  final completedAt = DateTime.utc(2026, 9, 10, 12, 5);

  setUp(() async {
    appDatabase = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );

    batchRepository = SqliteImportBatchRepository(
      ImportBatchDao(await appDatabase.database),
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  ImportCandidate candidate(String filePath) {
    return ImportCandidate(
      filePath: filePath,
      normalizedPath: filePath.replaceAll('\\', '/').toLowerCase(),
      discoveredAt: createdAt,
    );
  }

  AudioMetadata metadataFor(ImportCandidate candidate) {
    final fileName = candidate.filePath
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll('.mp3', '');

    return AudioMetadata(
      title: fileName,
      artistName: 'Batch Artist',
      albumTitle: 'Batch Album',
      durationSeconds: 200,
      trackNumber: 1,
      discNumber: 1,
      isSingle: false,
      featuredArtists: const [],
    );
  }

  LibraryImportService buildImportService() {
    return LibraryImportService(
      metadataResolver: MetadataResolver(
        primaryReader: CallbackAudioMetadataReader(
          (candidate) async => metadataFor(candidate),
        ),
        fallbackReader: CallbackAudioMetadataReader(
          (_) async => throw StateError('Fallback should not run'),
        ),
      ),
      atomicImporter: AtomicLibraryImporter(appDatabase: appDatabase),
    );
  }

  ImportBatch buildBatch() {
    return ImportBatch(
      id: 'batch_execution',
      createdAt: createdAt,
      items: [
        ImportBatchItem(
          candidate: candidate(
            r'C:\Music\Batch Artist\Batch Album\01 First Song.mp3',
          ),
        ),
        ImportBatchItem(
          candidate: candidate(
            r'C:\Music\Batch Artist\Batch Album\02 Second Song.mp3',
          ),
        ),
      ],
    );
  }

  test('executes every candidate and persists completed batch', () async {
    final executor = ImportBatchExecutor(
      libraryImportService: buildImportService(),
      batchRepository: batchRepository,
    );

    final summary = await executor.execute(
      buildBatch(),
      startedAt: startedAt,
      completedAt: completedAt,
    );

    expect(summary.batchId, 'batch_execution');
    expect(summary.totalCount, 2);
    expect(summary.importedCount, 2);
    expect(summary.relinkedCount, 0);
    expect(summary.skippedCount, 0);
    expect(summary.failedCount, 0);
    expect(summary.isComplete, isTrue);

    final persisted = await batchRepository.getById('batch_execution');

    expect(persisted, isNotNull);
    expect(persisted!.status, ImportBatchRecordStatus.completed);
    expect(persisted.totalCount, 2);
    expect(persisted.importedCount, 2);
    expect(persisted.relinkedCount, 0);
    expect(persisted.skippedCount, 0);
    expect(persisted.failedCount, 0);
    expect(persisted.startedAt, startedAt);
    expect(persisted.completedAt, completedAt);
    expect(persisted.isComplete, isTrue);
  });

  test('reports progress as candidates complete', () async {
    final executor = ImportBatchExecutor(
      libraryImportService: buildImportService(),
      batchRepository: batchRepository,
    );

    final progress = <ImportBatch>[];

    await executor.execute(
      buildBatch(),
      startedAt: startedAt,
      completedAt: completedAt,
      onProgress: progress.add,
    );

    expect(progress, hasLength(4));

    expect(progress[0].status, ImportBatchStatus.running);
    expect(progress[0].completedCount, 0);

    expect(progress[1].status, ImportBatchStatus.running);
    expect(progress[1].completedCount, 1);

    expect(progress[2].status, ImportBatchStatus.running);
    expect(progress[2].completedCount, 2);

    expect(progress[3].status, ImportBatchStatus.completed);
    expect(progress[3].completedCount, 2);
    expect(progress[3].progress, 1);
  });

  test('persists failed candidate and continues remaining batch', () async {
    final importService = LibraryImportService(
      metadataResolver: MetadataResolver(
        primaryReader: CallbackAudioMetadataReader((candidate) async {
          if (candidate.filePath.contains('Broken')) {
            throw StateError('Unreadable metadata');
          }

          return metadataFor(candidate);
        }),
        fallbackReader: CallbackAudioMetadataReader((candidate) async {
          if (candidate.filePath.contains('Broken')) {
            throw StateError('Fallback metadata also unreadable');
          }

          return metadataFor(candidate);
        }),
      ),
      atomicImporter: AtomicLibraryImporter(appDatabase: appDatabase),
    );

    final executor = ImportBatchExecutor(
      libraryImportService: importService,
      batchRepository: batchRepository,
    );

    final batch = ImportBatch(
      id: 'batch_with_failure',
      createdAt: createdAt,
      items: [
        ImportBatchItem(
          candidate: candidate(
            r'C:\Music\Batch Artist\Batch Album\01 Good Song.mp3',
          ),
        ),
        ImportBatchItem(
          candidate: candidate(
            r'C:\Music\Batch Artist\Batch Album\02 Broken Song.mp3',
          ),
        ),
        ImportBatchItem(
          candidate: candidate(
            r'C:\Music\Batch Artist\Batch Album\03 Another Song.mp3',
          ),
        ),
      ],
    );

    final summary = await executor.execute(
      batch,
      startedAt: startedAt,
      completedAt: completedAt,
    );

    expect(summary.totalCount, 3);
    expect(summary.importedCount, 2);
    expect(summary.failedCount, 1);
    expect(summary.processedCount, 3);
    expect(summary.hasFailures, isTrue);
    expect(summary.isComplete, isTrue);

    final persisted = await batchRepository.getById('batch_with_failure');

    expect(persisted, isNotNull);
    expect(persisted!.status, ImportBatchRecordStatus.completed);
    expect(persisted.importedCount, 2);
    expect(persisted.failedCount, 1);
    expect(persisted.processedCount, 3);
  });

  test('rejects execution of non-pending batch', () async {
    final executor = ImportBatchExecutor(
      libraryImportService: buildImportService(),
      batchRepository: batchRepository,
    );

    final runningBatch = buildBatch().start(startedAt);

    await expectLater(
      executor.execute(runningBatch),
      throwsA(isA<StateError>()),
    );

    expect(await batchRepository.getById(runningBatch.id), isNull);
  });

  test('completes empty batch without importing candidates', () async {
    final executor = ImportBatchExecutor(
      libraryImportService: buildImportService(),
      batchRepository: batchRepository,
    );

    final batch = ImportBatch(
      id: 'batch_empty',
      items: const [],
      createdAt: createdAt,
    );

    final summary = await executor.execute(
      batch,
      startedAt: startedAt,
      completedAt: completedAt,
    );

    expect(summary.totalCount, 0);
    expect(summary.processedCount, 0);
    expect(summary.isComplete, isTrue);

    final persisted = await batchRepository.getById(batch.id);

    expect(persisted, isNotNull);
    expect(persisted!.status, ImportBatchRecordStatus.completed);
    expect(persisted.totalCount, 0);
    expect(persisted.isComplete, isTrue);
  });
}
