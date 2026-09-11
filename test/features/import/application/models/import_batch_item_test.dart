import 'package:flutter_test/flutter_test.dart';
import 'package:sonus_next/features/import/application/models/import_batch_item.dart';
import 'package:sonus_next/features/import/domain/models/import_candidate.dart';
import 'package:sonus_next/features/import/domain/models/import_failure.dart';
import 'package:sonus_next/features/import/domain/models/import_result.dart';

void main() {
  final discoveredAt = DateTime.utc(2026, 9, 10);

  ImportCandidate candidate(String path) {
    return ImportCandidate(
      filePath: path,
      normalizedPath: path.toLowerCase(),
      discoveredAt: discoveredAt,
    );
  }

  test('starts pending before result exists', () {
    final item = ImportBatchItem(candidate: candidate(r'C:\Music\Track.mp3'));

    expect(item.isComplete, isFalse);
    expect(item.status, ImportBatchItemStatus.pending);
  });

  test('maps import result status into batch item status', () {
    final base = ImportBatchItem(candidate: candidate(r'C:\Music\Track.mp3'));

    final imported = base.completeWith(
      const ImportResult(
        status: ImportResultStatus.imported,
        filePath: r'C:\Music\Track.mp3',
        songId: 'song_1',
      ),
    );

    final relinked = base.completeWith(
      const ImportResult(
        status: ImportResultStatus.relinked,
        filePath: r'C:\Music\Track.mp3',
        songId: 'song_1',
      ),
    );

    final skipped = base.completeWith(
      const ImportResult(
        status: ImportResultStatus.skipped,
        filePath: r'C:\Music\Track.mp3',
        songId: 'song_1',
      ),
    );

    final failed = base.completeWith(
      const ImportResult(
        status: ImportResultStatus.failed,
        filePath: r'C:\Music\Track.mp3',
        failure: ImportFailure(
          type: ImportFailureType.persistenceFailure,
          message: 'Failure',
        ),
      ),
    );

    expect(imported.status, ImportBatchItemStatus.imported);
    expect(relinked.status, ImportBatchItemStatus.relinked);
    expect(skipped.status, ImportBatchItemStatus.skipped);
    expect(failed.status, ImportBatchItemStatus.failed);
  });
}
