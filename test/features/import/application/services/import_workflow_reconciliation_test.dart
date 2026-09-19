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
  final createdAt = DateTime.utc(2026, 9, 17, 12);
  final completedAt = DateTime.utc(2026, 9, 17, 12, 5);

  test('folder import remembers source and tags every candidate', () async {
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

    final discovery = _FakeDiscovery(folderCandidates: [first, second]);
    final runner = _RecordingRunner();
    final sourceRepository = _MemoryImportSourceRepository();
    final bindingRepository = _MemoryMediaFileBindingRepository();

    final service = ImportWorkflowService(
      candidateDiscovery: discovery,
      batchRunner: runner,
      importSourceRepository: sourceRepository,
      mediaFileBindingRepository: bindingRepository,
      batchIdFactory: () => 'batch_1',
      sourceIdFactory: () => 'source_1',
    );

    await service.importStructuredFolder(
      r'C:\Music',
      createdAt: createdAt,
      completedAt: completedAt,
    );

    final sources = await sourceRepository.getAll();

    expect(sources, hasLength(1));
    expect(sources.single.id, 'source_1');
    expect(sources.single.rootPath, r'C:\Music');
    expect(sources.single.normalizedRootPath, 'c:/music');
    expect(sources.single.lastScannedAt, completedAt);

    final batch = runner.lastBatch;

    expect(batch, isNotNull);
    expect(batch!.items, hasLength(2));
    expect(
      batch.items.every((item) => item.candidate.sourceId == 'source_1'),
      isTrue,
    );
  });

  test(
    'rescan marks missing source binding unavailable without deleting it',
    () async {
      final source = ImportSource(
        id: 'source_1',
        rootPath: r'C:\Music',
        normalizedRootPath: 'c:/music',
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final binding = MediaFileBinding(
        id: 'media_1',
        songId: 'song_1',
        filePath: r'C:\Music\Artist\Album\Song.mp3',
        normalizedPath: 'c:/music/artist/album/song.mp3',
        sourceId: source.id,
        isAvailable: true,
        lastSeenAt: createdAt,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final sourceRepository = _MemoryImportSourceRepository([source]);
      final bindingRepository = _MemoryMediaFileBindingRepository([binding]);

      final service = ImportWorkflowService(
        candidateDiscovery: _FakeDiscovery(),
        batchRunner: _RecordingRunner(),
        importSourceRepository: sourceRepository,
        mediaFileBindingRepository: bindingRepository,
        batchIdFactory: () => 'batch_missing',
      );

      await service.rescanSource(
        source.id,
        createdAt: createdAt,
        completedAt: completedAt,
      );

      final restored = await bindingRepository.getById(binding.id);

      expect(restored, isNotNull);
      expect(restored!.songId, 'song_1');
      expect(restored.isAvailable, isFalse);
      expect(restored.updatedAt, completedAt);

      final refreshedSource = await sourceRepository.getById(source.id);

      expect(refreshedSource!.lastScannedAt, completedAt);
    },
  );

  test('rescan does not affect bindings belonging to another source', () async {
    final sourceA = ImportSource(
      id: 'source_a',
      rootPath: r'C:\Music A',
      normalizedRootPath: 'c:/music a',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final sourceB = ImportSource(
      id: 'source_b',
      rootPath: r'D:\Music B',
      normalizedRootPath: 'd:/music b',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final bindingA = MediaFileBinding(
      id: 'media_a',
      songId: 'song_a',
      filePath: r'C:\Music A\Artist\Album\Song.mp3',
      normalizedPath: 'c:/music a/artist/album/song.mp3',
      sourceId: sourceA.id,
      isAvailable: true,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final bindingB = MediaFileBinding(
      id: 'media_b',
      songId: 'song_b',
      filePath: r'D:\Music B\Artist\Album\Song.mp3',
      normalizedPath: 'd:/music b/artist/album/song.mp3',
      sourceId: sourceB.id,
      isAvailable: true,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final sourceRepository = _MemoryImportSourceRepository([sourceA, sourceB]);
    final bindingRepository = _MemoryMediaFileBindingRepository([
      bindingA,
      bindingB,
    ]);

    final service = ImportWorkflowService(
      candidateDiscovery: _FakeDiscovery(),
      batchRunner: _RecordingRunner(),
      importSourceRepository: sourceRepository,
      mediaFileBindingRepository: bindingRepository,
      batchIdFactory: () => 'batch_isolation',
    );

    await service.rescanSource(
      sourceA.id,
      createdAt: createdAt,
      completedAt: completedAt,
    );

    final restoredA = await bindingRepository.getById(bindingA.id);
    final restoredB = await bindingRepository.getById(bindingB.id);

    expect(restoredA!.isAvailable, isFalse);
    expect(restoredB!.isAvailable, isTrue);
    expect(restoredB.updatedAt, createdAt);
  });

  test(
    'repeated missing-file rescan is idempotent for unavailable binding',
    () async {
      final source = ImportSource(
        id: 'source_1',
        rootPath: r'C:\Music',
        normalizedRootPath: 'c:/music',
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final binding = MediaFileBinding(
        id: 'media_1',
        songId: 'song_1',
        filePath: r'C:\Music\Artist\Album\Song.mp3',
        normalizedPath: 'c:/music/artist/album/song.mp3',
        sourceId: source.id,
        isAvailable: true,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final sourceRepository = _MemoryImportSourceRepository([source]);
      final bindingRepository = _MemoryMediaFileBindingRepository([binding]);

      final service = ImportWorkflowService(
        candidateDiscovery: _FakeDiscovery(),
        batchRunner: _RecordingRunner(),
        importSourceRepository: sourceRepository,
        mediaFileBindingRepository: bindingRepository,
        batchIdFactory: () => 'batch_repeat',
      );

      final firstScan = completedAt;
      final secondScan = completedAt.add(const Duration(minutes: 5));

      await service.rescanSource(
        source.id,
        createdAt: createdAt,
        completedAt: firstScan,
      );

      final afterFirst = await bindingRepository.getById(binding.id);

      expect(afterFirst!.isAvailable, isFalse);
      expect(afterFirst.updatedAt, firstScan);

      await service.rescanSource(
        source.id,
        createdAt: secondScan,
        completedAt: secondScan,
      );

      final afterSecond = await bindingRepository.getById(binding.id);

      expect(afterSecond!.isAvailable, isFalse);
      expect(afterSecond.updatedAt, firstScan);
    },
  );

  test('existing remembered source is reused instead of duplicated', () async {
    final source = ImportSource(
      id: 'source_existing',
      rootPath: r'C:\Music',
      normalizedRootPath: 'c:/music',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final sourceRepository = _MemoryImportSourceRepository([source]);
    final runner = _RecordingRunner();

    final service = ImportWorkflowService(
      candidateDiscovery: _FakeDiscovery(
        folderCandidates: [
          ImportCandidate(
            filePath: r'C:\Music\Artist\Album\Song.mp3',
            normalizedPath: 'c:/music/artist/album/song.mp3',
            discoveredAt: createdAt,
          ),
        ],
      ),
      batchRunner: runner,
      importSourceRepository: sourceRepository,
      mediaFileBindingRepository: _MemoryMediaFileBindingRepository(),
      batchIdFactory: () => 'batch_existing',
      sourceIdFactory: () => 'should_not_be_used',
    );

    await service.importStructuredFolder(
      r'C:\Music',
      createdAt: createdAt,
      completedAt: completedAt,
    );

    expect(await sourceRepository.getAll(), hasLength(1));
    expect(
      runner.lastBatch!.items.single.candidate.sourceId,
      'source_existing',
    );
  });
}

class _FakeDiscovery implements ImportCandidateDiscovery {
  _FakeDiscovery({this.folderCandidates = const []});
  final List<ImportCandidate> folderCandidates;

  @override
  Future<ImportCandidate> discoverFile(
    String filePath, {
    DateTime? discoveredAt,
  }) {
    throw StateError('File discovery is not used by reconciliation tests.');
  }

  @override
  Future<List<ImportCandidate>> discoverFolder(
    String rootPath, {
    DateTime? discoveredAt,
  }) async {
    return folderCandidates;
  }
}

class _RecordingRunner implements ImportBatchRunner {
  ImportBatch? lastBatch;

  @override
  Future<ImportExecutionSummary> execute(
    ImportBatch batch, {
    DateTime? startedAt,
    DateTime? completedAt,
    ImportBatchProgressCallback? onProgress,
  }) async {
    lastBatch = batch;

    return ImportExecutionSummary(
      batchId: batch.id,
      totalCount: batch.totalCount,
      importedCount: 0,
      relinkedCount: 0,
      skippedCount: batch.totalCount,
      failedCount: 0,
    );
  }
}

class _MemoryImportSourceRepository implements ImportSourceRepository {
  _MemoryImportSourceRepository([Iterable<ImportSource> initial = const []]) {
    for (final source in initial) {
      _sources[source.id] = source;
    }
  }

  final Map<String, ImportSource> _sources = {};

  @override
  Future<void> create(ImportSource source) async {
    if (_sources.containsKey(source.id)) {
      throw StateError('Duplicate source: ${source.id}');
    }

    _sources[source.id] = source;
  }

  @override
  Future<void> save(ImportSource source) async {
    if (!_sources.containsKey(source.id)) {
      throw StateError('Unknown source: ${source.id}');
    }

    _sources[source.id] = source;
  }

  @override
  Future<ImportSource?> getById(String id) async {
    return _sources[id];
  }

  @override
  Future<ImportSource?> getByNormalizedRootPath(
    String normalizedRootPath,
  ) async {
    for (final source in _sources.values) {
      if (source.normalizedRootPath == normalizedRootPath) {
        return source;
      }
    }

    return null;
  }

  @override
  Future<List<ImportSource>> getAll() async {
    return List.unmodifiable(_sources.values);
  }
}

class _MemoryMediaFileBindingRepository implements MediaFileBindingRepository {
  _MemoryMediaFileBindingRepository([
    Iterable<MediaFileBinding> initial = const [],
  ]) {
    for (final binding in initial) {
      _bindings[binding.id] = binding;
    }
  }

  final Map<String, MediaFileBinding> _bindings = {};

  @override
  Future<void> create(MediaFileBinding binding) async {
    _bindings[binding.id] = binding;
  }

  @override
  Future<void> save(MediaFileBinding binding) async {
    _bindings[binding.id] = binding;
  }

  @override
  Future<MediaFileBinding?> getById(String id) async {
    return _bindings[id];
  }

  @override
  Future<MediaFileBinding?> getByNormalizedPath(String normalizedPath) async {
    for (final binding in _bindings.values) {
      if (binding.normalizedPath == normalizedPath) {
        return binding;
      }
    }

    return null;
  }

  @override
  Future<List<MediaFileBinding>> getBySongId(String songId) async {
    return _bindings.values
        .where((binding) => binding.songId == songId)
        .toList(growable: false);
  }

  @override
  Future<List<MediaFileBinding>> getBySourceId(String sourceId) async {
    return _bindings.values
        .where((binding) => binding.sourceId == sourceId)
        .toList(growable: false);
  }
}
