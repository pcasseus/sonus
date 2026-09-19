import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sonus_next/features/account/application/controllers/account_controller.dart';
import 'package:sonus_next/features/import/application/services/import_review_service.dart';
import 'package:sonus_next/features/import/application/models/import_batch.dart';
import 'package:sonus_next/features/import/application/models/import_execution_summary.dart';
import 'package:sonus_next/features/import/application/services/import_batch_runner.dart';
import 'package:sonus_next/features/import/application/services/import_source_picker.dart';
import 'package:sonus_next/features/import/application/services/import_workflow_service.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_source_discovery_exception.dart';
import 'package:sonus_next/features/import/domain/services/import_candidate_discovery.dart';
import 'package:sonus_next/features/import/presentation/pages/imports_page.dart';

void main() {
  group('ImportsPage', () {
    testWidgets('shows loading state while workflow is unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ImportWorkflowService?>.value(value: null),
            Provider<ImportReviewService?>.value(value: null),
            Provider<AccountController?>.value(value: null),
          ],
          child: const MaterialApp(home: ImportsPage()),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('imports-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('imports-loading')),
        findsOneWidget,
      );
    });

    testWidgets('shows import source choices and folder guidance', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());

      expect(find.text('Add music to Sonus'), findsOneWidget);
      expect(find.text('Import one song'), findsOneWidget);
      expect(find.text('Import a music folder'), findsOneWidget);
      expect(find.text('Choose MP3'), findsOneWidget);
      expect(find.text('Choose folder'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('import-single-song-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('import-folder-card')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('import-folder-structure-card')),
        300,
      );

      expect(
        find.byKey(const ValueKey<String>('import-folder-structure-card')),
        findsOneWidget,
      );
      expect(find.textContaining('Music Folder'), findsOneWidget);
    });

    testWidgets('shows busy state while choosing a source', (tester) async {
      final selectionGate = Completer<String?>();

      await tester.pumpWidget(
        _buildApp(
          sourcePicker: _FakeImportSourcePicker(
            onPickSongFile: () => selectionGate.future,
          ),
        ),
      );

      await tester.tap(find.text('Choose MP3'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('import-progress-card')),
        findsOneWidget,
      );
      expect(find.text('Choose a source'), findsOneWidget);
      expect(find.text('Preparing import...'), findsOneWidget);

      expect(
        find.byKey(const ValueKey<String>('import-single-song-card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('import-folder-card')),
        findsNothing,
      );

      selectionGate.complete(null);
      await tester.pumpAndSettle();

      expect(find.text('Choose MP3'), findsOneWidget);
      expect(find.text('Choose folder'), findsOneWidget);
    });

    testWidgets('imports one song and shows result summary', (tester) async {
      final discovery = _FakeCandidateDiscovery();

      final runner = _FakeBatchRunner(
        onExecute: (batch, onProgress) async {
          final running = batch.start(DateTime(2026, 9, 16, 12));
          onProgress?.call(running);

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

      await tester.pumpWidget(
        _buildApp(
          sourcePicker: _FakeImportSourcePicker(
            onPickSongFile: () async => r'C:\Music\Artist\Album\01 - Song.mp3',
          ),
          candidateDiscovery: discovery,
          batchRunner: runner,
        ),
      );

      await tester.tap(find.text('Choose MP3'));
      await tester.pumpAndSettle();

      expect(discovery.lastFilePath, r'C:\Music\Artist\Album\01 - Song.mp3');

      expect(
        find.byKey(const ValueKey<String>('import-result-card')),
        findsOneWidget,
      );
      expect(find.text('Import complete'), findsOneWidget);
      expect(find.text('Processed'), findsOneWidget);
      expect(find.text('Imported'), findsOneWidget);
      expect(find.text('Relinked'), findsOneWidget);
      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Import more music'), findsOneWidget);
    });

    testWidgets('shows folder discovery error and can reset', (tester) async {
      final discovery = _FakeCandidateDiscovery(
        folderError: const ImportSourceDiscoveryException(
          type: ImportSourceDiscoveryFailureType.invalidStructure,
          message: 'Artist folders may contain only album folders.',
        ),
      );

      await tester.pumpWidget(
        _buildApp(
          sourcePicker: _FakeImportSourcePicker(
            onPickStructuredFolder: () async => r'C:\BrokenMusic',
          ),
          candidateDiscovery: discovery,
        ),
      );

      await tester.ensureVisible(find.text('Choose folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('import-error-card')),
        findsOneWidget,
      );
      expect(find.text('Import failed'), findsOneWidget);
      expect(
        find.text('Artist folders may contain only album folders.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Try again'));
      await tester.pump();

      expect(find.text('Choose MP3'), findsOneWidget);
      expect(find.text('Choose folder'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('import-error-card')),
        findsNothing,
      );
    });

    testWidgets('can reset after a completed import', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          sourcePicker: _FakeImportSourcePicker(
            onPickSongFile: () async => r'C:\Music\Artist\Album\Song.mp3',
          ),
        ),
      );

      await tester.tap(find.text('Choose MP3'));
      await tester.pumpAndSettle();

      expect(find.text('Import complete'), findsOneWidget);

      await tester.tap(find.text('Import more music'));
      await tester.pump();

      expect(find.text('Choose MP3'), findsOneWidget);
      expect(find.text('Choose folder'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('import-result-card')),
        findsNothing,
      );
    });
  });
}

Widget _buildApp({
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

  final workflowService = ImportWorkflowService(
    candidateDiscovery: discovery,
    batchRunner: runner,
    batchIdFactory: () => 'import-page-test',
  );

  return MultiProvider(
    providers: [
      Provider<ImportWorkflowService?>.value(value: workflowService),
      Provider<ImportReviewService?>.value(value: null),
      Provider<AccountController?>.value(value: null),
      Provider<ImportSourcePicker>.value(
        value: sourcePicker ?? const _FakeImportSourcePicker(),
      ),
    ],
    child: const MaterialApp(home: ImportsPage()),
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
  _FakeCandidateDiscovery({this.folderError});

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

    return [
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
