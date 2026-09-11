import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/models/import_batch.dart';
import 'package:sonus_next/features/import/application/models/import_batch_item.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';

void main() {
  final discoveredAt = DateTime.utc(2026, 9, 10);

  ImportBatchItem pendingItem(String path) {
    return ImportBatchItem(
      candidate: ImportCandidate(
        filePath: path,
        normalizedPath: path.toLowerCase(),
        discoveredAt: discoveredAt,
      ),
    );
  }

  test('tracks lifecycle and progress', () {
    final createdAt = DateTime.utc(2026, 9, 10, 12);
    final startedAt = DateTime.utc(2026, 9, 10, 12, 1);
    final completedAt = DateTime.utc(2026, 9, 10, 12, 2);

    final first = pendingItem('one.mp3');
    final second = pendingItem('two.mp3');

    var batch = ImportBatch(
      id: 'batch_1',
      items: [first, second],
      createdAt: createdAt,
    );

    expect(batch.status, ImportBatchStatus.pending);
    expect(batch.totalCount, 2);
    expect(batch.completedCount, 0);
    expect(batch.progress, 0);

    batch = batch.start(startedAt);

    expect(batch.status, ImportBatchStatus.running);
    expect(batch.startedAt, startedAt);

    batch = batch.withItems([
      first.completeWith(
        const ImportResult(
          status: ImportResultStatus.imported,
          filePath: 'one.mp3',
          songId: 'song_1',
        ),
      ),
      second,
    ]);

    expect(batch.completedCount, 1);
    expect(batch.pendingCount, 1);
    expect(batch.importedCount, 1);
    expect(batch.progress, 0.5);

    batch = batch.complete(completedAt);

    expect(batch.status, ImportBatchStatus.completed);
    expect(batch.completedAt, completedAt);
  });

  test('empty batch reports complete progress', () {
    final batch = ImportBatch(
      id: 'empty',
      items: const [],
      createdAt: DateTime.utc(2026, 9, 10),
    );

    expect(batch.progress, 1);
  });
}
