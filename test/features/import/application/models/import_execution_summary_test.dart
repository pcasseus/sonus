import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/models/import_batch.dart';
import 'package:sonus_next/features/import/application/models/import_batch_item.dart';
import 'package:sonus_next/features/import/application/models/import_execution_summary.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';

void main() {
  final discoveredAt = DateTime.utc(2026, 9, 10);

  ImportBatchItem item(String path, ImportResult result) {
    return ImportBatchItem(
      candidate: ImportCandidate(
        filePath: path,
        normalizedPath: path.toLowerCase(),
        discoveredAt: discoveredAt,
      ),
      result: result,
    );
  }

  test('summarizes completed batch outcomes', () {
    final batch = ImportBatch(
      id: 'batch_summary',
      createdAt: DateTime.utc(2026, 9, 10),
      status: ImportBatchStatus.completed,
      items: [
        item(
          'one.mp3',
          const ImportResult(
            status: ImportResultStatus.imported,
            filePath: 'one.mp3',
            songId: 'song_1',
          ),
        ),
        item(
          'two.mp3',
          const ImportResult(
            status: ImportResultStatus.relinked,
            filePath: 'two.mp3',
            songId: 'song_2',
          ),
        ),
        item(
          'three.mp3',
          const ImportResult(
            status: ImportResultStatus.skipped,
            filePath: 'three.mp3',
          ),
        ),
        item(
          'four.mp3',
          const ImportResult(
            status: ImportResultStatus.failed,
            filePath: 'four.mp3',
            failure: ImportFailure(
              type: ImportFailureType.metadataUnreadable,
              message: 'Unreadable',
            ),
          ),
        ),
      ],
    );

    final summary = ImportExecutionSummary.fromBatch(batch);

    expect(summary.totalCount, 4);
    expect(summary.importedCount, 1);
    expect(summary.relinkedCount, 1);
    expect(summary.skippedCount, 1);
    expect(summary.failedCount, 1);
    expect(summary.successfulCount, 2);
    expect(summary.processedCount, 4);
    expect(summary.hasFailures, isTrue);
    expect(summary.isComplete, isTrue);
  });
}
