import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/application/models/import_batch.dart';
import 'package:sonus_next/features/import/application/models/import_execution_summary.dart';
import 'package:sonus_next/features/import/application/services/import_batch_runner.dart';
import 'package:sonus_next/features/import/application/services/import_workflow_service.dart';
import 'package:sonus_next/features/import/domain/entities/import_source.dart';
import 'package:sonus_next/features/import/domain/entities/media_file_binding.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/repositories/import_source_repository.dart';
import 'package:sonus_next/features/import/domain/repositories/media_file_binding_repository.dart';
import 'package:sonus_next/features/import/domain/services/import_candidate_discovery.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 10, 12);
  final startedAt = DateTime.utc(2026, 9, 10, 12, 1);
  final completedAt = DateTime.utc(2026, 9, 10, 12, 2);

  test(
    'single-song workflow discovers candidate and executes one-item batch',
    () async {
      final candidate = ImportCandidate(
        filePath: r'C:\Music\Artist\Album\Song.mp3',
        normalizedPath: 'c:/music/artist/album/song.mp3',
        discoveredAt: createdAt,
      );

      final discovery = _FakeImportCandidateDiscovery(fileCandidate: candidate);

      final runner = _RecordingImportBatchRunner();

      final service = ImportWorkflowService(
        candidateDiscovery: discovery,
        batchRunner: runner,
        batchIdFactory: () => 'import_batch_test',
      );

      final summary = await service.importSingleSong(
        candidate.filePath,
        createdAt: createdAt,
        startedAt: startedAt,
        completedAt: completedAt,
      );

      expect(discovery.lastFilePath, candidate.filePath);
      expect(discovery.lastDiscoveredAt, createdAt);

      final batch = runner.lastBatch;

      expect(batch, isNotNull);
      expect(batch!.id, 'import_batch_test');
      expect(batch.createdAt, createdAt);
      expect(batch.totalCount, 1);
      expect(batch.items.single.candidate, candidate);

      expect(runner.lastStartedAt, startedAt);
      expect(runner.lastCompletedAt, completedAt);

      expect(summary.batchId, 'import_batch_test');
      expect(summary.totalCount, 1);
    },
  );

  test(
    'folder workflow creates one batch containing every discovered candidate',
    () async {
      final first = ImportCandidate(
        filePath: r'C:\Music\Artist\Album\01 First.mp3',
        normalizedPath: 'c:/music/artist/album/01 first.mp3',
        discoveredAt: createdAt,
      );

      final second = ImportCandidate(
        filePath: r'C:\Music\Artist\Album\02 Second.mp3',
        normalizedPath: 'c:/music/artist/album/02 second.mp3',
        discoveredAt: createdAt,
      );

      final discovery = _FakeImportCandidateDiscovery(
        folderCandidates: [first, second],
      );

      final runner = _RecordingImportBatchRunner();

      final service = ImportWorkflowService(
        candidateDiscovery: discovery,
        batchRunner: runner,
        batchIdFactory: () => 'import_batch_folder',
      );

      final summary = await service.importStructuredFolder(
        r'C:\Music',
        createdAt: createdAt,
      );

      expect(discovery.lastFolderPath, r'C:\Music');
      expect(discovery.lastDiscoveredAt, createdAt);

      final batch = runner.lastBatch;

      expect(batch, isNotNull);
      expect(batch!.id, 'import_batch_folder');
      expect(batch.totalCount, 2);
      expect(batch.items[0].candidate, first);
      expect(batch.items[1].candidate, second);

      expect(summary.totalCount, 2);
    },
  );

  test('workflow forwards progress callback to batch runner', () async {
    final candidate = ImportCandidate(
      filePath: r'C:\Music\Artist\Album\Song.mp3',
      normalizedPath: 'c:/music/artist/album/song.mp3',
      discoveredAt: createdAt,
    );

    final discovery = _FakeImportCandidateDiscovery(fileCandidate: candidate);

    final runner = _RecordingImportBatchRunner(emitProgress: true);

    final service = ImportWorkflowService(
      candidateDiscovery: discovery,
      batchRunner: runner,
      batchIdFactory: () => 'import_batch_progress',
    );

    final progress = <ImportBatch>[];

    await service.importSingleSong(
      candidate.filePath,
      createdAt: createdAt,
      startedAt: startedAt,
      onProgress: progress.add,
    );

    expect(progress, hasLength(1));
    expect(progress.single.id, 'import_batch_progress');
    expect(progress.single.status, ImportBatchStatus.running);
  });

  test('rescan notifies only songs with no remaining usable binding', () async {
    final source = ImportSource(
      id: 'source_1',
      rootPath: r'C:\Music',
      normalizedRootPath: 'c:/music',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final otherSource = ImportSource(
      id: 'source_2',
      rootPath: r'D:\Backup',
      normalizedRootPath: 'd:/backup',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final sourceRepository = _FakeImportSourceRepository([source, otherSource]);

    final bindingRepository = _FakeMediaFileBindingRepository([
      MediaFileBinding(
        id: 'binding_only',
        songId: 'song_only',
        filePath: r'C:\Music\Only.mp3',
        normalizedPath: 'c:/music/only.mp3',
        sourceId: source.id,
        isAvailable: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      MediaFileBinding(
        id: 'binding_multi_missing',
        songId: 'song_multi',
        filePath: r'C:\Music\Multi.mp3',
        normalizedPath: 'c:/music/multi.mp3',
        sourceId: source.id,
        isAvailable: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      MediaFileBinding(
        id: 'binding_multi_surviving',
        songId: 'song_multi',
        filePath: r'D:\Backup\Multi.mp3',
        normalizedPath: 'd:/backup/multi.mp3',
        sourceId: otherSource.id,
        isAvailable: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    ]);

    Set<String>? unavailableSongIds;

    final service = ImportWorkflowService(
      candidateDiscovery: _FakeImportCandidateDiscovery(),
      batchRunner: _RecordingImportBatchRunner(),
      importSourceRepository: sourceRepository,
      mediaFileBindingRepository: bindingRepository,
      batchIdFactory: () => 'import_batch_rescan',
      onSongsBecameUnavailable: (songIds) async {
        unavailableSongIds = Set<String>.of(songIds);
      },
    );

    await service.rescanSource(
      source.id,
      createdAt: createdAt,
      completedAt: completedAt,
    );

    final onlyBindings = await bindingRepository.getBySongId('song_only');

    final multiBindings = await bindingRepository.getBySongId('song_multi');

    expect(onlyBindings.single.isAvailable, isFalse);

    expect(
      multiBindings
          .firstWhere((binding) => binding.id == 'binding_multi_missing')
          .isAvailable,
      isFalse,
    );

    expect(
      multiBindings
          .firstWhere((binding) => binding.id == 'binding_multi_surviving')
          .isAvailable,
      isTrue,
    );

    expect(unavailableSongIds, {'song_only'});

    final updatedSource = await sourceRepository.getById(source.id);

    expect(updatedSource?.lastScannedAt, completedAt);
  });

  test('discovery failure prevents batch execution', () async {
    final discovery = _ThrowingImportCandidateDiscovery();
    final runner = _RecordingImportBatchRunner();

    final service = ImportWorkflowService(
      candidateDiscovery: discovery,
      batchRunner: runner,
      batchIdFactory: () => 'import_batch_unused',
    );

    await expectLater(
      service.importSingleSong(r'C:\Missing.mp3', createdAt: createdAt),
      throwsA(isA<StateError>()),
    );

    expect(runner.lastBatch, isNull);
  });
}

class _FakeImportSourceRepository implements ImportSourceRepository {
  _FakeImportSourceRepository(List<ImportSource> sources)
    : _sources = List<ImportSource>.of(sources);

  final List<ImportSource> _sources;

  @override
  Future<void> create(ImportSource source) async {
    _sources.add(source);
  }

  @override
  Future<void> save(ImportSource source) async {
    final index = _sources.indexWhere((candidate) => candidate.id == source.id);

    if (index == -1) {
      throw StateError('Import source not found: ${source.id}');
    }

    _sources[index] = source;
  }

  @override
  Future<ImportSource?> getById(String id) async {
    for (final source in _sources) {
      if (source.id == id) {
        return source;
      }
    }

    return null;
  }

  @override
  Future<ImportSource?> getByNormalizedRootPath(
    String normalizedRootPath,
  ) async {
    for (final source in _sources) {
      if (source.normalizedRootPath == normalizedRootPath) {
        return source;
      }
    }

    return null;
  }

  @override
  Future<List<ImportSource>> getAll() async {
    return List<ImportSource>.unmodifiable(_sources);
  }
}

class _FakeMediaFileBindingRepository implements MediaFileBindingRepository {
  _FakeMediaFileBindingRepository(List<MediaFileBinding> bindings)
    : _bindings = List<MediaFileBinding>.of(bindings);

  final List<MediaFileBinding> _bindings;

  @override
  Future<void> create(MediaFileBinding binding) async {
    _bindings.add(binding);
  }

  @override
  Future<void> save(MediaFileBinding binding) async {
    final index = _bindings.indexWhere(
      (candidate) => candidate.id == binding.id,
    );

    if (index == -1) {
      throw StateError('Media binding not found: ${binding.id}');
    }

    _bindings[index] = binding;
  }

  @override
  Future<MediaFileBinding?> getById(String id) async {
    for (final binding in _bindings) {
      if (binding.id == id) {
        return binding;
      }
    }

    return null;
  }

  @override
  Future<MediaFileBinding?> getByNormalizedPath(String normalizedPath) async {
    for (final binding in _bindings) {
      if (binding.normalizedPath == normalizedPath) {
        return binding;
      }
    }

    return null;
  }

  @override
  Future<List<MediaFileBinding>> getBySongId(String songId) async {
    return _bindings
        .where((binding) => binding.songId == songId)
        .toList(growable: false);
  }

  @override
  Future<List<MediaFileBinding>> getBySourceId(String sourceId) async {
    return _bindings
        .where((binding) => binding.sourceId == sourceId)
        .toList(growable: false);
  }
}

class _FakeImportCandidateDiscovery implements ImportCandidateDiscovery {
  _FakeImportCandidateDiscovery({
    this.fileCandidate,
    this.folderCandidates = const [],
  });

  final ImportCandidate? fileCandidate;
  final List<ImportCandidate> folderCandidates;

  String? lastFilePath;
  String? lastFolderPath;
  DateTime? lastDiscoveredAt;

  @override
  Future<ImportCandidate> discoverFile(
    String filePath, {
    DateTime? discoveredAt,
  }) async {
    lastFilePath = filePath;
    lastDiscoveredAt = discoveredAt;

    final candidate = fileCandidate;

    if (candidate == null) {
      throw StateError('No fake file candidate configured.');
    }

    return candidate;
  }

  @override
  Future<List<ImportCandidate>> discoverFolder(
    String rootPath, {
    DateTime? discoveredAt,
  }) async {
    lastFolderPath = rootPath;
    lastDiscoveredAt = discoveredAt;

    return folderCandidates;
  }
}

class _ThrowingImportCandidateDiscovery implements ImportCandidateDiscovery {
  @override
  Future<ImportCandidate> discoverFile(
    String filePath, {
    DateTime? discoveredAt,
  }) {
    throw StateError('Discovery failed.');
  }

  @override
  Future<List<ImportCandidate>> discoverFolder(
    String rootPath, {
    DateTime? discoveredAt,
  }) {
    throw StateError('Discovery failed.');
  }
}

class _RecordingImportBatchRunner implements ImportBatchRunner {
  _RecordingImportBatchRunner({this.emitProgress = false});

  final bool emitProgress;

  ImportBatch? lastBatch;
  DateTime? lastStartedAt;
  DateTime? lastCompletedAt;

  @override
  Future<ImportExecutionSummary> execute(
    ImportBatch batch, {
    DateTime? startedAt,
    DateTime? completedAt,
    ImportBatchProgressCallback? onProgress,
  }) async {
    lastBatch = batch;
    lastStartedAt = startedAt;
    lastCompletedAt = completedAt;

    if (emitProgress) {
      onProgress?.call(batch.start(startedAt ?? batch.createdAt));
    }

    return ImportExecutionSummary(
      batchId: batch.id,
      totalCount: batch.totalCount,
      importedCount: 0,
      relinkedCount: 0,
      skippedCount: 0,
      failedCount: 0,
    );
  }
}
