import 'package:flutter_test/flutter_test.dart';

import 'package:sonus_next/features/import/application/models/import_batch.dart';
import 'package:sonus_next/features/import/application/models/import_execution_summary.dart';
import 'package:sonus_next/features/import/application/services/import_batch_runner.dart';
import 'package:sonus_next/features/import/application/services/import_workflow_service.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
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
