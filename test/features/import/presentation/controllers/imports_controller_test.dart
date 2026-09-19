import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/models/import_batch.dart';
import 'package:sonus_next/features/import/application/models/import_execution_summary.dart';
import 'package:sonus_next/features/import/application/services/import_batch_runner.dart';
import 'package:sonus_next/features/import/application/services/import_source_picker.dart';
import 'package:sonus_next/features/import/application/services/import_workflow_service.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_source_discovery_exception.dart';
import 'package:sonus_next/features/import/domain/services/import_candidate_discovery.dart';
import 'package:sonus_next/features/import/presentation/controllers/imports_controller.dart';

void main() {
  group('ImportsController', () {
    test('starts idle', () {
      final controller = _buildController();

      expect(controller.status, ImportsControllerStatus.idle);
      expect(controller.isBusy, isFalse);
      expect(controller.isSelectingSource, isFalse);
      expect(controller.isImporting, isFalse);
      expect(controller.hasCompleted, isFalse);
      expect(controller.hasError, isFalse);
      expect(controller.currentBatch, isNull);
      expect(controller.summary, isNull);
      expect(controller.error, isNull);
      expect(controller.errorMessage, isNull);
      expect(controller.progress, 0);
      expect(controller.totalCount, 0);
      expect(controller.completedCount, 0);

      controller.dispose();
    });

    test('cancelled single-song selection returns to idle', () async {
      final picker = _FakeImportSourcePicker(onPickSongFile: () async => null);

      final controller = _buildController(sourcePicker: picker);

      final result = await controller.importSingleSong();

      expect(result, isFalse);
      expect(controller.status, ImportsControllerStatus.idle);
      expect(controller.isBusy, isFalse);
      expect(controller.hasError, isFalse);

      controller.dispose();
    });

    test('imports a single song and exposes completion summary', () async {
      final picker = _FakeImportSourcePicker(
        onPickSongFile: () async => r'C:\Music\Artist\Album\01 - Song.mp3',
      );

      final discovery = _FakeCandidateDiscovery();

      final runner = _FakeBatchRunner(
        onExecute: (batch, onProgress) async {
          final running = batch.start(DateTime(2026, 9, 16, 12));
          onProgress?.call(running);

          final completed = running.complete(DateTime(2026, 9, 16, 12, 1));
          onProgress?.call(completed);

          return ImportExecutionSummary(
            batchId: batch.id,
            totalCount: 1,
            importedCount: 1,
            relinkedCount: 0,
            skippedCount: 0,
            failedCount: 0,
          );
        },
      );

      final controller = _buildController(
        sourcePicker: picker,
        candidateDiscovery: discovery,
        batchRunner: runner,
      );

      final result = await controller.importSingleSong();

      expect(result, isTrue);
      expect(discovery.lastFilePath, r'C:\Music\Artist\Album\01 - Song.mp3');
      expect(controller.status, ImportsControllerStatus.completed);
      expect(controller.hasCompleted, isTrue);
      expect(controller.summary, isNotNull);
      expect(controller.summary!.totalCount, 1);
      expect(controller.summary!.importedCount, 1);
      expect(controller.summary!.hasFailures, isFalse);

      controller.dispose();
    });

    test('imports a structured folder', () async {
      final picker = _FakeImportSourcePicker(
        onPickStructuredFolder: () async => r'C:\Music',
      );

      final discovery = _FakeCandidateDiscovery(
        folderCandidates: [
          _candidate(r'C:\Music\Artist\Album\01 - First.mp3'),
          _candidate(r'C:\Music\Artist\Album\02 - Second.mp3'),
        ],
      );

      final runner = _FakeBatchRunner(
        onExecute: (batch, onProgress) async {
          expect(batch.totalCount, 2);

          return ImportExecutionSummary(
            batchId: batch.id,
            totalCount: 2,
            importedCount: 2,
            relinkedCount: 0,
            skippedCount: 0,
            failedCount: 0,
          );
        },
      );

      final controller = _buildController(
        sourcePicker: picker,
        candidateDiscovery: discovery,
        batchRunner: runner,
      );

      final result = await controller.importStructuredFolder();

      expect(result, isTrue);
      expect(discovery.lastFolderPath, r'C:\Music');
      expect(controller.status, ImportsControllerStatus.completed);
      expect(controller.summary!.totalCount, 2);
      expect(controller.summary!.importedCount, 2);

      controller.dispose();
    });

    test('exposes live batch progress while importing', () async {
      final picker = _FakeImportSourcePicker(
        onPickSongFile: () async => r'C:\Music\Artist\Album\Song.mp3',
      );

      final progressGate = Completer<void>();

      final runner = _FakeBatchRunner(
        onExecute: (batch, onProgress) async {
          final running = batch.start(DateTime(2026, 9, 16, 12));
          onProgress?.call(running);

          await progressGate.future;

          return ImportExecutionSummary(
            batchId: batch.id,
            totalCount: 1,
            importedCount: 1,
            relinkedCount: 0,
            skippedCount: 0,
            failedCount: 0,
          );
        },
      );

      final controller = _buildController(
        sourcePicker: picker,
        batchRunner: runner,
      );

      final future = controller.importSingleSong();

      await Future<void>.delayed(Duration.zero);

      expect(controller.status, ImportsControllerStatus.importing);
      expect(controller.isImporting, isTrue);
      expect(controller.currentBatch, isNotNull);
      expect(controller.totalCount, 1);
      expect(controller.completedCount, 0);
      expect(controller.progress, 0);

      progressGate.complete();

      expect(await future, isTrue);
      expect(controller.status, ImportsControllerStatus.completed);

      controller.dispose();
    });

    test('shows discovery error message', () async {
      final picker = _FakeImportSourcePicker(
        onPickStructuredFolder: () async => r'C:\BrokenMusic',
      );

      final discovery = _FakeCandidateDiscovery(
        folderError: const ImportSourceDiscoveryException(
          type: ImportSourceDiscoveryFailureType.invalidStructure,
          message: 'Artist folders may contain only album folders.',
          path: r'C:\BrokenMusic',
        ),
      );

      final controller = _buildController(
        sourcePicker: picker,
        candidateDiscovery: discovery,
      );

      final result = await controller.importStructuredFolder();

      expect(result, isFalse);
      expect(controller.status, ImportsControllerStatus.failed);
      expect(controller.hasError, isTrue);
      expect(
        controller.errorMessage,
        'Artist folders may contain only album folders.\n\n'
        'Problem path:\n'
        r'C:\BrokenMusic',
      );

      controller.dispose();
    });

    test('shows generic message when picker throws', () async {
      final picker = _FakeImportSourcePicker(
        onPickSongFile: () async {
          throw StateError('picker exploded');
        },
      );

      final controller = _buildController(sourcePicker: picker);

      final result = await controller.importSingleSong();

      expect(result, isFalse);
      expect(controller.status, ImportsControllerStatus.failed);
      expect(controller.error, isA<StateError>());
      expect(controller.errorMessage, 'Could not complete the import.');

      controller.dispose();
    });

    test('blocks another import while source selection is active', () async {
      final selectionGate = Completer<String?>();

      final picker = _FakeImportSourcePicker(
        onPickSongFile: () => selectionGate.future,
      );

      final controller = _buildController(sourcePicker: picker);

      final firstImport = controller.importSingleSong();

      expect(controller.status, ImportsControllerStatus.selectingSource);
      expect(controller.isBusy, isTrue);

      final secondResult = await controller.importStructuredFolder();

      expect(secondResult, isFalse);
      expect(controller.status, ImportsControllerStatus.selectingSource);

      selectionGate.complete(null);

      expect(await firstImport, isFalse);
      expect(controller.status, ImportsControllerStatus.idle);

      controller.dispose();
    });

    test('reset clears completed state', () async {
      final picker = _FakeImportSourcePicker(
        onPickSongFile: () async => r'C:\Music\Artist\Album\Song.mp3',
      );

      final controller = _buildController(sourcePicker: picker);

      expect(await controller.importSingleSong(), isTrue);
      expect(controller.hasCompleted, isTrue);

      controller.reset();

      expect(controller.status, ImportsControllerStatus.idle);
      expect(controller.currentBatch, isNull);
      expect(controller.summary, isNull);
      expect(controller.error, isNull);
      expect(controller.errorMessage, isNull);

      controller.dispose();
    });
  });
}

ImportsController _buildController({
  ImportSourcePicker? sourcePicker,
  ImportCandidateDiscovery? candidateDiscovery,
  ImportBatchRunner? batchRunner,
}) {
  final discovery = candidateDiscovery ?? _FakeCandidateDiscovery();

  final runner =
      batchRunner ??
      _FakeBatchRunner(
        onExecute: (batch, onProgress) async {
          return ImportExecutionSummary(
            batchId: batch.id,
            totalCount: batch.totalCount,
            importedCount: batch.totalCount,
            relinkedCount: 0,
            skippedCount: 0,
            failedCount: 0,
          );
        },
      );

  return ImportsController(
    workflowService: ImportWorkflowService(
      candidateDiscovery: discovery,
      batchRunner: runner,
      batchIdFactory: () => 'import-batch-test',
    ),
    sourcePicker: sourcePicker ?? const _FakeImportSourcePicker(),
  );
}

ImportCandidate _candidate(String filePath) {
  return ImportCandidate(
    filePath: filePath,
    normalizedPath: filePath.toLowerCase(),
    discoveredAt: DateTime(2026, 9, 16),
  );
}

class _FakeImportSourcePicker implements ImportSourcePicker {
  const _FakeImportSourcePicker({
    this.onPickSongFile,
    this.onPickStructuredFolder,
  });

  final Future<String?> Function()? onPickSongFile;
  final Future<String?> Function()? onPickStructuredFolder;

  @override
  Future<String?> pickSongFile() {
    return onPickSongFile?.call() ?? Future<String?>.value(null);
  }

  @override
  Future<String?> pickStructuredFolder() {
    return onPickStructuredFolder?.call() ?? Future<String?>.value(null);
  }
}

class _FakeCandidateDiscovery implements ImportCandidateDiscovery {
  _FakeCandidateDiscovery({this.folderCandidates, this.folderError});

  final List<ImportCandidate>? folderCandidates;
  final Object? folderError;

  String? lastFilePath;
  String? lastFolderPath;

  @override
  Future<ImportCandidate> discoverFile(
    String filePath, {
    DateTime? discoveredAt,
  }) async {
    lastFilePath = filePath;

    return ImportCandidate(
      filePath: filePath,
      normalizedPath: filePath.toLowerCase(),
      discoveredAt: discoveredAt ?? DateTime(2026, 9, 16),
    );
  }

  @override
  Future<List<ImportCandidate>> discoverFolder(
    String rootPath, {
    DateTime? discoveredAt,
  }) async {
    lastFolderPath = rootPath;

    final error = folderError;

    if (error != null) {
      throw error;
    }

    return folderCandidates ??
        [
          ImportCandidate(
            filePath: '$rootPath/Artist/Album/Song.mp3',
            normalizedPath: '$rootPath/artist/album/song.mp3'.toLowerCase(),
            discoveredAt: discoveredAt ?? DateTime(2026, 9, 16),
          ),
        ];
  }
}

typedef _ExecuteCallback =
    Future<ImportExecutionSummary> Function(
      ImportBatch batch,
      ImportBatchProgressCallback? onProgress,
    );

class _FakeBatchRunner implements ImportBatchRunner {
  const _FakeBatchRunner({required this.onExecute});

  final _ExecuteCallback onExecute;

  @override
  Future<ImportExecutionSummary> execute(
    ImportBatch batch, {
    DateTime? startedAt,
    DateTime? completedAt,
    ImportBatchProgressCallback? onProgress,
  }) {
    return onExecute(batch, onProgress);
  }
}
